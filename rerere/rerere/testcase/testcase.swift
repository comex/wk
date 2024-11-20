// TODO: right after mu should probably not count
// TODO: mark items (newborns) as needing intensive SRS
/*
TODO
got 53 SRS items
...but limiting to 50
[0 | 74]
*/
// TODO the test ended when I did !wrong at the beginning of the last item, then solved it
// TODO FIX BANGS ON CONFUSION
// TODO why didn't I get a reading match for 挟む
import Foundation
import System
// TODO: ~ is broken for r2m
// TODO: !wrong doesn't act as expected when halfway through a k2rm
// TODO: don't let you mu more than once
func data(of path: String) throws -> Data {
    return try Data(contentsOf: URL(fileURLWithPath: path))
}
func time<T>(count: Int, block: () -> T) {
    let a = CFAbsoluteTimeGetCurrent()
    for _ in 0..<count {
        blackBox(block())
    }
    let b = CFAbsoluteTimeGetCurrent()
    print((b - a) / Double(count))
}
func blackBox<T>(_ t: T) {
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
func commaSplitNoTrim(_ s: String) -> [String] {
    return s.split(separator: ",").map { String($0) }
}
func ensure(_ condition: Bool, _ message: @autoclosure () -> String = String(), file: StaticString = #file, line: UInt = #line) {
    if !condition {
        fatalError(message(), file: file, line: line)
    }
}
func unwrapOrThrow<T>(_ t: T?, err: @autoclosure () -> Error) throws -> T {
    guard let t = t else { throw err() }
    return t
}
func loadJSONAndExtraYAML<T>(basePath: String, stem: String, class: T.Type) -> [T]
    where T: DecodableWithConfiguration, T.DecodingConfiguration == Relaxed, T: Decodable
{
    let jsonData = try! data(of: "\(basePath)/\(stem).json")
    let base = try! JSONDecoder().decode([T].self, from: jsonData, configuration: Relaxed(relaxed: false))
    return base
}
let startupDate: Date = Date()
let myDateFormatter: DateFormatter = DateFormatter()
myDateFormatter.locale = Locale(identifier: "en_US_POSIX")
myDateFormatter.dateFormat = "yyyy-MM-dd"
#if false
func runAndGetOutput(_ args: [String]) throws -> String {
    return try unwrapOrThrow(String(decoding: output!, as: UTF8.self), err: MyError("invalid utf8 in output"))
}
#endif
func runAndGetOutput(_ args: [String]) throws -> String {
    let pipe = Pipe()
    let stdoutFd = pipe.fileHandleForWriting.fileDescriptor
    let myArgs: [UnsafeMutablePointer<Int8>?] = args.map {
        strdup($0)
    } + [nil]
    var pid: pid_t = 0
    var fileActions: posix_spawn_file_actions_t? = nil
    posix_spawn_file_actions_init(&fileActions)
    posix_spawn_file_actions_adddup2(&fileActions, stdoutFd, 1)
    let res = posix_spawn(&pid, myArgs[0], &fileActions, nil, myArgs, environ)
    for arg in myArgs { free(arg) }
    if res == -1 {
        throw MyError("runAndGetOutput(\(args)): posix_spawn failed: \(strerror(errno)!)")
    }
    let queue = DispatchQueue(label: "runAndGetOutput")
    nonisolated(unsafe) var output: Data? = nil
    var st: Int32 = 0
    let waited = waitpid(pid, &st, 0)
    if waited != pid {
        throw MyError("runAndGetOutput(\(args)): waitpid() failed: \(strerror(errno)!)")
    }
    queue.sync {}
    return try unwrapOrThrow(String(decoding: output!, as: UTF8.self), err: MyError("invalid utf8 in output"))
}
struct StudyMaterial {
    let meaningSynonyms: [String]
}
func loadStudyMaterials(basePath: String) -> [Int: StudyMaterial] {
    struct StudyMaterialsJSONEntry: Decodable {
        struct Data: Decodable {
            let subject_id: Int
            let meaning_synonyms: [String]
        }
        let data: Data
    }
    let entries = try! JSONDecoder().decode([StudyMaterialsJSONEntry].self, from: data(of: "\(basePath)/study_materials.json"))
    var ret: [Int: StudyMaterial] = [:]
    for entry in entries {
        let subjectId = entry.data.subject_id
        let meaningSynonyms = entry.data.meaning_synonyms
        ensure(ret[subjectId] == nil)
        ret[subjectId] = StudyMaterial(meaningSynonyms: meaningSynonyms)
    }
    return ret
}
func getWkDir() -> String {
    var path = FilePath(Bundle.main.executablePath!).removingLastComponent()
    while !(FileManager.default.fileExists(atPath: path.pushing("kanji.json").string)) {
    }
    return try! URL(fileURLWithPath: path.string).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath!
}
enum ItemKind: String, Codable, CodingKeyRepresentable {
    case word, kanji, confusion
}
class Item: Hashable, Equatable, Comparable {
    let name: String
    let birthday: Date?
    let id: Int
    init(name: String, birthday: Date?) {
        self.name = name
        self.birthday = birthday
        self.id = 9
    }
    convenience init(name: String, from dec: any Decoder) throws {
        enum K: CodingKey { case birth }
        let container = try dec.container(keyedBy: K.self)
        self.init(name: name,
                  birthday: try container.decodeIfPresent(Date.self, forKey: .birth))
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.name)
    }
    static func == (lhs: Item, rhs: Item) -> Bool {
        return lhs === rhs
    }
    static func < (lhs: Item, rhs: Item) -> Bool {
        return lhs.id < rhs.id
    }
    // trying to turn this into a protocol has issues
    class var kind: ItemKind {
        fatalError("must override kind on \(self)")
    }
    func cliPrint(colorful: Bool) {
        fatalError("must override cliPrint on \(self)")
    }
    var availableTests: [TestKind] {
        fatalError("must override availableTests on \(self)")
    }
}
enum IngType: Comparable {
    case primary, secondary, whitelist, blacklist, synonym
}
struct Ing {
    let text: String
    let type: IngType
    let acceptedAnswerWK: Bool
    var acceptedAnswerForMe: Bool {
        // it's fiiiiine
        return true
    }
    init(from dec: any Decoder, isMeaning: Bool, relaxed: Bool) throws {
        enum K: CodingKey { case reading, meaning, primary, accepted_answer }
        let c: KeyedDecodingContainer<K>
        do {
            c = try dec.container(keyedBy: K.self)
        } catch DecodingError.typeMismatch {
            if !relaxed { fatalError("expected dictionary") }
            let text = try dec.singleValueContainer().decode(String.self)
            self.text = text
            self.type = .primary
            self.acceptedAnswerWK = true
            return
        }
        if isMeaning {
            self.text = try c.decode(String.self, forKey: .meaning).lowercased()
        } else {
            self.text = try c.decode(String.self, forKey: .reading)
        }
        self.type = try c.decode(Bool.self, forKey: .primary) ? .primary : .secondary
        self.acceptedAnswerWK = try c.decode(Bool.self, forKey: .accepted_answer)
    }
    init(auxiliaryMeaningFrom dec: any Decoder) throws {
        enum K: CodingKey { case meaning, type }
        let c = try dec.container(keyedBy: K.self)
        self.text = try c.decode(String.self, forKey: .meaning).lowercased()
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "whitelist":
            self.type = .whitelist
            self.acceptedAnswerWK = true
        case "blacklist":
            self.type = .blacklist
            self.acceptedAnswerWK = false
        default:
            fatalError("unknown auxiliary meaning type \(type)")
        }
    }
    init(synonymWithText text: String) {
        self.text = text
        self.type = .synonym
        self.acceptedAnswerWK = true
    }
}
func decodeArray<T>(_ dec: any UnkeyedDecodingContainer, _ callback: (Decoder) throws -> T) throws -> [T] {
    var dec = dec
    var ret: [T] = []
    return ret
}
// without alternatives, without normalization, just return qual
// TODO: CLI class
func cliPrintAlternatives(_ items: [Item], label: String) {
    if items.isEmpty { return }
    let s = "Entered \(label) matches"
    if items.count > 8 {
        print(" (\(s) \(items.count) items)")
        return
    } else {
        print(" \(s):")
        for item in items {
            item.cliPrint(colorful: false)
        }
    }
}
struct Relaxed { let relaxed: Bool }
class NormalItem: Item, DecodableWithConfiguration, Decodable {
    let meanings: [Ing]
    let readings: [Ing]
    let character: String
    typealias DecodingConfiguration = Relaxed
    required convenience init(from dec: any Decoder) throws {
        try self.init(from: dec, configuration: Relaxed(relaxed:
            dec.userInfo[CodingUserInfoKey(rawValue: "relaxed")!] as! Bool))
    }
    required init(from dec: any Decoder, configuration: Relaxed) throws {
        let relaxed = configuration.relaxed
        enum K: CodingKey { case data, id, characters, readings, meanings, auxiliary_meanings }
        let topC = try dec.container(keyedBy: K.self)
        var dataC: KeyedDecodingContainer<K>
        let wkId: Int?
        if topC.contains(.data) {
            wkId = try topC.decode(Int.self, forKey: .id)
            dataC = try topC.nestedContainer(keyedBy: K.self, forKey: .data)
        } else {
            if !relaxed { fatalError("expected 'data'") }
            dataC = topC
            wkId = nil
        }
        self.character = trim(try dataC.decode(String.self, forKey: .characters))
        self.readings = try decodeArray(dataC.nestedUnkeyedContainer(forKey: .readings)) {
            try Ing(from: $0, isMeaning: false, relaxed: relaxed)
        }
        var meanings = try decodeArray(dataC.nestedUnkeyedContainer(forKey: .meanings)) {
            try Ing(from: $0, isMeaning: true, relaxed: relaxed)
        }
        if dataC.contains(.auxiliary_meanings) {
            meanings += try decodeArray(dataC.nestedUnkeyedContainer(forKey: .auxiliary_meanings)) {
                try Ing(auxiliaryMeaningFrom: $0)
            }
        }
        self.meanings = meanings
        try super.init(name: self.character, from: try dataC.superDecoder())
    }
}
enum TestKind: String, Codable {
    case meaningToReading = "m2r"
    case readingToMeaning = "r2m"
    case characterToRM = "c2"
    case confusion = "kc"
}
enum TestOutcome: String {
    case right
    case wrong
    case mu
}
extension String {
    func splut(separator: UTF8.CodeUnit, includingSpaces: Bool = false, map: (String) -> String) -> [String] {
        var res: [String] = []
        let utf = self.utf8
        let start = utf.startIndex
        let end = utf.endIndex
        var i = start
        var lastStart = i
        while true {
        }
        return res
    }
}
enum RandomMode: String, CaseIterable, Codable {
    case all
    case confusion
}
func runOrExit(_ f: () throws -> Void) {
    do {
        try f()
    } catch let es as ExitStatusError {
        exit(Int32(es.exitStatus))
    } catch let e {
        try! { throw e }()
    }
}
//print("   :xsamdfa: b  :  c:   ".splut(separator: 58, includingSpaces: true, map: { $0 }))
