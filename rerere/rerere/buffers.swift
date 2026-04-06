import Foundation
import Synchronization
import os

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

final class Box<T: ~Copyable> {
    let value: T
    init(value: consuming T) { self.value = value }
}

struct TotallySendable<T: ~Copyable>: ~Copyable, @unchecked Sendable {
    let value: T
}

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

func mutexTake<T>(_ mtx: borrowing Mutex<T?>) -> T? {
    mtx.withLock { $0.take() }
}

private struct CoordinateAsyncState<R: Sendable> {
    var errorList: [any Error] = []
    var successVal: R? = nil
}
func coordinateAsync<R: Sendable>(url urlOrig: URL, filePresenter: (any NSFilePresenter & Sendable)?, write: Bool, idForDebugging id: Int? = nil, cb: @Sendable (URL) async throws -> R) async throws -> R {
    // NSFileCoordinator has no way to go async within a coordination block!
    // There is only a version that asyncly waits to _start_ the block.
    // So we need a dedicated thread.
    let id = id ?? Int.random(in: 0..<1000000)
    let logger: Logger = Logger()
    return try await withoutActuallyEscaping(cb) { cb2 in
        let maybeCB2 = Mutex(Optional.some(cb2))
        return try await withCheckedThrowingContinuation { (cc: CheckedContinuation<R, any Error>) -> Void in
            logger.info("%%\(id) about to detach")
            return Thread.detachNewThread {
                logger.info("%%\(id) did detach")
                let coordinator = NSFileCoordinator(filePresenter: filePresenter)

                let state: Mutex<CoordinateAsyncState<R>> = .init(.init())
                let accessor: (URL) -> Void = { (url) in
                    logger.info("%%\(id) accessor start")
                    blockOnLikeYoureNotSupposedTo { @Sendable () async -> Void in
                        logger.info("%%\(id) inside blockOnLikeYoureNotSupposedTo")
                        do {
                            let cb2 = mutexTake(maybeCB2)!
                            let res = try await cb2(url)
                            state.withLock {
                                ensure($0.successVal == nil)
                                $0.successVal = res
                            }
                        } catch let e {
                            state.withLock { $0.errorList.append(e) }
                        }
                    }
                    logger.info("%%\(id) accessor end")
                }
                var errOut: NSError? = nil
                if write {
                    logger.info("%%\(id) coordinating to write")
                    coordinator.coordinate(writingItemAt: urlOrig, options: [.forMerging], error: &errOut, byAccessor: accessor)
                } else {
                    logger.info("%%\(id) coordinating to read")
                    coordinator.coordinate(readingItemAt: urlOrig, options: [], error: &errOut, byAccessor: accessor)
                }
                logger.info("%%\(id) coordinator.coordinate end")

                let _ = mutexTake(maybeCB2)
                state.withLock { (state) in
                    if let errOut { state.errorList.append(errOut) }
                    if let e = state.errorList.first {
                        print("errorList: \(state.errorList)")
                        cc.resume(throwing: e)
                    } else if let r = state.successVal {
                        cc.resume(returning: r)
                    } else {
                        cc.resume(throwing: MyError("no error but the block was not called"))
                    }
                }
            }
        }
    }
}


func warn(_ s: String) {
    print(s)
}
struct MyError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
struct ExitStatusError: Error {
    let exitStatus: Int
}
#if false
func trim<S: StringProtocol>(_ s: S) -> String {
    // this goes to foundation
    return s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
}
#endif
@inline(__always)
func isSpace(_ c: UTF8.CodeUnit) -> Bool {
    return c == 32 || c == 10
}
func trim(_ s: String) -> String {
    let a = s.utf8
    guard let start = a.firstIndex(where: { !isSpace($0) }) else {
        return ""
    }
    let end = a.lastIndex(where: { !isSpace($0) })!
    if start == a.startIndex && a.index(after: end) == a.endIndex {
        return s
    } else {
        return String(a[start...end])!
    }
}
func trim(_ s: Substring) -> String {
    return trim(String(s))
}
func d2s(_ d: Data) -> String {
    String(data: d, encoding: .utf8)!
}
func d2s(_ ud: UnsafeData) -> String {
    ud.ubp.withMemoryRebound(to: UInt8.self) { String(bytes: $0, encoding: .utf8)! }
}
func commaSplitNoTrim(_ s: String) -> [String] {
    return s.split(separator: ",").map { String($0) }
}
func ensure(
    _ condition: Bool, _ message: @autoclosure () -> String = String(), file: StaticString = #file,
    line: UInt = #line
) {
    if !condition {
        fatalError(message(), file: file, line: line)
    }
}
func unwrapOrThrow<T>(_ t: T?, err: @autoclosure () -> Error) throws -> T {
    guard let t = t else { throw err() }
    return t
}
