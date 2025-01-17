import Foundation
import Synchronization

struct UnsafeData: Hashable, CustomStringConvertible {
    let ubp: UnsafeRawBufferPointer

    init() {
        self.ubp = UnsafeRawBufferPointer(start: nil, count: 0)
    }
    init(_ ubp: UnsafeRawBufferPointer) {
        self.ubp = ubp
    }
    static func withData<R>(_ data: Data, cb: (UnsafeData) throws -> R) rethrows -> R {
        try data.withUnsafeBytes { try cb(UnsafeData($0)) }
    }

    static func == (lhs: UnsafeData, rhs: UnsafeData) -> Bool {
        return lhs.ubp.count == rhs.ubp.count
            && 0 == memcmp(lhs.ubp.baseAddress, rhs.ubp.baseAddress, lhs.ubp.count)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bytes: self.ubp)
    }

    var description: String {
        return "UnsafeData{\(d2s(self))}"
    }

    subscript(idx: Int) -> UInt8 {
        ubp.load(fromByteOffset: idx, as: UInt8.self)
    }
    subscript(idxs: Range<Int>) -> UnsafeData {
        UnsafeData(UnsafeRawBufferPointer(rebasing: self.ubp[idxs]))
    }
    var count: Int {
        self.ubp.count
    }
    func split(
        separator: Int, into buffer: UnsafeMutableBufferPointer<UnsafeData>, includingSpaces: Bool
    ) -> Int {
        let start = 0  //self.startIndex
        let end = count  //self.endIndex
        var i = start
        var lastStart = i
        var outIdx = 0
        while true {
            if i == end || self[i] == separator {
                var lastEnd = i
                if includingSpaces {
                    while true {
                        if lastEnd == lastStart { break }
                        let prev = lastEnd - 1
                        if !isSpace(self[prev]) { break }
                        lastEnd = prev
                    }
                    if i != end {
                        while true {
                            let next = i + 1
                            if next == end { break }
                            if !isSpace(self[next]) { break }
                            i = next
                        }
                    }
                }
                buffer[outIdx] = self[lastStart..<lastEnd]
                outIdx += 1
                if i == end { break }
                lastStart = i + 1
            }
            i += 1
        }
        return outIdx
    }
}

enum MaybeOwnedData: Hashable {
    case unowned(UnsafeData)
    case owned(Data)

    static func == (lhs: MaybeOwnedData, rhs: MaybeOwnedData) -> Bool {
        lhs.borrow { (lhsUnowned) in
            rhs.borrow { (rhsUnowned) in
                lhsUnowned == rhsUnowned
            }
        }
    }

    func hash(into hasher: inout Hasher) {
        self.borrow { $0.hash(into: &hasher) }
    }

    func borrow<R>(cb: (UnsafeData) throws -> R) rethrows -> R {
        switch self {
        case .unowned(let unsafeData):
            return try cb(unsafeData)
        case .owned(let data):
            return try UnsafeData.withData(data, cb: cb)
        }
    }

}

func parseNonnegativeInt(data: UnsafeData) -> Int? {
    var i = 0
    let end = data.count
    var ret: Int = 0
    while i < end {
        let c = data[i]
        if !(c >= 0x30 && c <= 0x39) {
            return nil
        }
        ret = (ret * 10) + Int(c - 0x30)
        i += 1
    }
    return ret
}

struct StableArray<T>: ~Copyable {
    let buf: UnsafeMutableBufferPointer<T>
    init(repeating t: T, count: Int) {
        let ptr = calloc(MemoryLayout<T>.stride, count).bindMemory(to: T.self, capacity: count)
        self.buf = UnsafeMutableBufferPointer(start: ptr, count: count)
        self.buf.initialize(repeating: t)
    }
    deinit {
        self.buf.deinitialize()
        free(self.buf.baseAddress)
    }
    var count: Int { self.buf.count }
    subscript(i: Int) -> T {
        get { self.buf[i] }
        set(newValue) { self.buf[i] = newValue }
    }
}

actor AsyncMutex<Value: ~Copyable> {
    var value: Value?
    var waiters: [CheckedContinuation<Void, Never>] = []
    init(_ value: consuming sending Value) {
        self.value = consume value
    }
    func withLock<Result: ~Copyable>(
        _ body: (inout sending Value) async throws -> sending Result,
        preWait: (() async -> Void)? = nil
        // ^^ can't change to
        //        preWait: () async -> Void = {}
        //    because compiler complains
    )
        async rethrows -> sending Result
    {
        while self.value == nil {
            await preWait?()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.waiters.append(continuation)
            }
        }
        // Safety: self.value is always disconnected
        nonisolated(unsafe) var tempVal = exchange(&self.value, with: nil)!
        do {
            let ret = try await body(&tempVal)
            returnValue(newVal: consume tempVal)
            return ret
        } catch let e {
            returnValue(newVal: consume tempVal)
            throw e
        }

    }

    private func returnValue(newVal: consuming Value) {
        self.value = consume newVal
        if !self.waiters.isEmpty {
            self.waiters.removeFirst().resume()
        }
    }
}

extension AtomicLazyReference {
    func initializeUnique(_ value: Instance) {
        // Just a double-check, in case `value` is actually not unique (in which
        // case we can't detect a race).  Would be better if storeIfNil just returned
        // success.
        let wasNonNil = self.load() != nil
        
        let actualValue = self.storeIfNil(value)
        if actualValue !== value || wasNonNil {
            fatalError("initializeUnique initing with \(value) but already got \(actualValue)")
        }
    }
}

struct TotallySendable<T: ~Copyable>: ~Copyable, @unchecked Sendable {
    let value: T
}

/*
class Box<T: ~Copyable> {
    let value: T
    init(value: consuming T) { self.value = value }
}
*/

typealias BlockOnCallback<T: ~Copyable> = () async throws -> sending T
func blockOnLikeYoureNotSupposedTo<T: ~Copyable>(_ cb: sending BlockOnCallback<T>) rethrows -> sending T {
    var t: T? = nil
    let sema: DispatchSemaphore = DispatchSemaphore(value: 0)
    withUnsafeMutablePointer(to: &t) { (tPtr) -> Void in
        withoutActuallyEscaping(consume cb) { (cb2) -> Void in
            withUnsafePointer(to: cb2) { (cbPtr) -> Void in
                let bundle = TotallySendable(value: (tPtr: tPtr, cbPtr: cbPtr))
                _ = Task {
                    bundle.value.tPtr.pointee = try await bundle.value.cbPtr.pointee()
                    sema.signal()
                }
                sema.wait()

            }
        }
    }
    return t.take()!
}
