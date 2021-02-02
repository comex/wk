// TODO FIX BANGS ON CONFUSION
// TODO why didn't I get a reading match for 挟む
// TODO mu overwrites a later wrong?
import Foundation
import Yams

// TODO(fixed?): ~ is broken
// TODO: !wrong doesn't act as expected when halfway through a k2rm
// TODO: don't let you mu more than once
// TODO: reading alternatives for words

func time<T>(block: () -> T) {
	let a = CFAbsoluteTimeGetCurrent()
	let _ = block()
	let b = CFAbsoluteTimeGetCurrent()
	print(b - a)
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
        return s
    }
    let end = a.lastIndex(where: { !isSpace($0) })!
    if start == a.startIndex && end == a.endIndex {
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
func commaJoin(_ ss: [String]) -> String {
    return ss.joined(separator: ", ")
}
func ensure(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = String(), file: StaticString = #file, line: UInt = #line) {
    if !condition() {
        fatalError(message(), file: file, line: line)
    }
}
func unwrapOrThrow<T>(_ t: T?, err: @autoclosure () -> Error) throws -> T {
    guard let t = t else { throw err() }
    return t
}
func loadJSON(path: String) -> Any {
    return try! JSONSerialization.jsonObject(
        with: try! Data(contentsOf: URL(fileURLWithPath: path)),
        options: JSONSerialization.ReadingOptions())
}
func loadYAML(path: String) -> Any {
    return try! Yams.load(yaml: try! String(contentsOf: URL(fileURLWithPath: path)))!
}
func loadJSONAndExtraYAML(basePath: String, stem: String) -> [NSDictionary] {
    let base = loadJSON(path: "\(basePath)/\(stem).json") as! [NSDictionary]
    let extra = loadYAML(path: "\(basePath)/extra-\(stem).yaml") as! [NSDictionary]
    return base + extra
}

#if false
func runAndGetOutput(_ args: [String]) throws -> String {
    // This is broken because it does something weird with the signal mask
    let p = Process()
    let pipe = Pipe()
    p.arguments = Array(args[1...])
    p.executableURL = URL(fileURLWithPath: args[0])
    //p.standardOutput = pipe
    p.standardOutput = FileHandle.standardOutput
    p.standardError = FileHandle.standardError
    p.standardInput = FileHandle.standardInput
    //p.startsNewProcessGroup = false
    try p.run()
    let queue = DispatchQueue(label: "runAndGetOutput")
    var output: Data? = nil
    /*queue.async {
        output = pipe.fileHandleForReading.readDataToEndOfFile()
    }*/
    p.waitUntilExit()
    if p.terminationReason != .exit {
        throw MyError("bad termination")
    }
    queue.sync {}
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
    var output: Data? = nil
    pipe.fileHandleForWriting.closeFile()
    queue.async {
        output = pipe.fileHandleForReading.readDataToEndOfFile()
    }

    
    var st: Int32 = 0
    let waited = waitpid(pid, &st, 0)
    if waited != pid {
        throw MyError("runAndGetOutput(\(args)): waitpid() failed: \(strerror(errno)!)")
    }
    let wstatus = st & 0o177
    let exitStatus = (st >> 8) & 0xff

    if wstatus != 0 {
        throw MyError("runAndGetOutput(\(args)): exited with signal \(exitStatus)")
    }
    if exitStatus != 0 {
        throw ExitStatusError(exitStatus: Int(exitStatus))
    }
    
    queue.sync {}
    return try unwrapOrThrow(String(decoding: output!, as: UTF8.self), err: MyError("invalid utf8 in output"))


}
class Subete {
    static var instance: Subete!
    var allWords: ItemList<Word>! = nil
    var allKanji: ItemList<Kanji>! = nil
    var allItems: [Item]! = nil
    var allConfusion: ItemList<Confusion>! = nil
    var srs: SRS? = nil
    
    var lastAppendedTest: Test?
    
    let basePath = "/Users/comex/c/wk/"

    var nextItemID = 0

    init() {
        Subete.instance = self
        print("loading json")
        self.allWords = ItemList(loadJSONAndExtraYAML(basePath: basePath, stem: "vocabulary").map { Word(json: $0) })
        self.allKanji = ItemList(loadJSONAndExtraYAML(basePath: basePath, stem: "kanji").map { Kanji(json: $0) })
        print("loading confusion")
        let allKanjiConfusion = loadConfusion(path: basePath + "confusion.txt", isWord: false)
        let allWordConfusion = loadConfusion(path: basePath + "confusion-vocab.txt", isWord: true)
        self.allConfusion = ItemList(allKanjiConfusion + allWordConfusion)
        self.allItems = self.allWords.items + self.allKanji.items + self.allConfusion.items
        print("done loading")

    }
    func allByKind(_ kind: ItemKind) -> ItemListProtocol {
        switch kind {
        case .word: return self.allWords
        case .kanji: return self.allKanji
        case .confusion: return self.allConfusion
        }
    }
    func loadConfusion(path: String, isWord: Bool) -> [Confusion] {
        let text = try! String(contentsOfFile: path, encoding: .utf8)
        return text.split(separator: "\n").map {
            Confusion(line: String($0), isWord: isWord)
        }
    }
    func openLogTxt<R>(write: Bool, cb: (FileHandle) throws -> R) throws -> R {
        // todo: clowd!
        let url = URL(fileURLWithPath: basePath + "log.txt")
        let fh: FileHandle
        if write {
            fh = try FileHandle(forUpdating: url)
        } else {
            fh = try FileHandle(forReadingFrom: url)
        }
        let flockRet = flock(fh.fileDescriptor, (write ? LOCK_EX : LOCK_SH) | LOCK_NB)
        if flockRet != 0 {
            throw MyError("failed to flock log.txt")
        }
        let ret = try cb(fh)
        flock(fh.fileDescriptor, LOCK_UN)
        fh.closeFile()
        return ret
    }
    func createSRSFromLog() {
        let results = try! TestResult.readAllFromLog()
        let srs = SRS()
        for result in results { srs.update(result) }
        self.srs = srs
    }
    func handleBang(_ input: String, curTest: Test) {
        switch input {
        case "!right":
            handleChangeLast(outcome: .right, curTest: curTest)
        case "!wrong":
            handleChangeLast(outcome: .wrong, curTest: curTest)
        case "!mu":
            handleChangeLast(outcome: .mu, curTest: curTest)
        default:
            print("?bang? \(input)")
        }
    }
    func handleChangeLast(outcome: TestOutcome, curTest: Test) {
        let test: Test
        var outcome: TestOutcome? = outcome
        if curTest.didCliRead {
            print("changing this test")
            test = curTest
            if outcome == .right { outcome = nil }
        } else {
            print("changing last test")
            guard let t = self.lastAppendedTest else {
                print("no last")
                return
            }
            test = t
        }
        try! test.markResult(outcome: outcome)
    }
}

enum ItemKind: String {
    case word, kanji, confusion
}
class Item: Hashable, Equatable, Comparable {
    let name: String
    let id: Int
    init(name: String) {
        self.name = name
        self.id = Subete.instance.nextItemID
        Subete.instance.nextItemID = self.id + 1
    }
    var kind: ItemKind { fatalError("?") }
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.name)
    }
    static func == (lhs: Item, rhs: Item) -> Bool {
        return lhs === rhs
    }
    static func < (lhs: Item, rhs: Item) -> Bool {
        return lhs.id < rhs.id
    }
    func cliPrint(colorful: Bool) {
        fatalError("?")
    }
    var availableTests: [TestKind] {
        fatalError("TODO")
    }

}
func normalizeMeaning(_ meaning: String) -> String {
    return trim(meaning)
}
func normalizeReading(_ input: String) -> String {
    // TODO katakana to hiragana
    var reading: String = trim(input)
    if reading.contains("-") {
        reading = String(reading.replacingOccurrences(of: "-", with: "ー"))
    }
    return reading
}

class NormalItem: Item {
    let meanings: [String]
    let readings: [String]
    let importantReadings: [String]
    let unimportantReadings: [String]
    let character: String
    let json: NSDictionary
    
    init(json: NSDictionary, readings: [String], importantReadings: [String], unimportantReadings: [String]) {
        self.json = json
        self.character = trim(json["character"] as! String)
        self.meanings = commaSplitNoTrim(json["meaning"] as! String).map { normalizeMeaning($0) }
        self.readings = readings
        self.importantReadings = importantReadings
        self.unimportantReadings = unimportantReadings
        super.init(name: self.character)
    }
    func readingAlternatives(reading: String) -> [Item] {
        let normalizedReading = String(normalizeReading(String(reading)))
        return Subete.instance.allByKind(self.kind).findByReading(normalizedReading).filter { $0 != self }
    }
    func meaningMatches(normalizedInput: String, levenshtein: inout Levenshtein) -> Bool {
        return self.evaluateMeaningAnswerInner(normalizedInput: normalizedInput, levenshtein: &levenshtein) > 0
    }
    func meaningAlternatives(meaning: String) -> [Item] {
        let normalizedMeaning = String(normalizeMeaning(String(meaning)))
        /*
        var levenshtein = Levenshtein()
        return Subete.instance.allByKind(self.kind).vagueItems.filter { (other: Item) -> Bool in
            return other != self && (other as! NormalItem).meaningMatches(normalizedInput: normalizedMeaning, levenshtein: &levenshtein)
        }
        */
        return Subete.instance.allByKind(self.kind).findByMeaning(normalizedMeaning).filter { $0 != self }
    }
    func cliPrintAlternatives(_ items: [Item], isReading: Bool) {
        if items.isEmpty { return }
        let s = "Entered \(isReading ? "kana" : "meaning") matches"
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
    func cliPrintMeaningAlternatives(_ items: [Item]) {
        if items.isEmpty { return }
        print(" Entered meaning matches:")
        for item in items {
            item.cliPrint(colorful: false)
        }
    }
    func similarMeaning() -> [Item] {
        var set: Set<Item> = []
        for meaning in self.meanings {
            set.formUnion(Subete.instance.allByKind(self.kind).findByMeaning(String(meaning)))
        }
        set.remove(self)
        return Array(set).sorted()
    }
    func cliPrintSimilarMeaning() {
        let items = similarMeaning()
        if items.isEmpty { return }
        print(" Similar meaning:")
        for item in items {
            item.cliPrint(colorful: false)
        }
    }
    func sameReading() -> [Item] {
        var set: Set<Item> = []
        for reading in self.readings {
            set.formUnion(Subete.instance.allByKind(self.kind).findByReading(String(reading)))
        }
        set.remove(self)
        return Array(set).sorted()
    }
    func cliPrintSameReadingIfFew() {
        let items = sameReading()
        if items.isEmpty { return }
        if items.count > 6 { return }
        print(" Same reading:")
        for item in items {
            item.cliPrint(colorful: false)
        }
    }

    // without alternatives, without normalization, just return qual
    func evaluateMeaningAnswerInner(normalizedInput: String, levenshtein: inout Levenshtein) -> Int {
        var bestQual = 0
        for meaning in self.meanings {
            let okDist = Int(round(0.4 * Double(meaning.count)))
            if normalizedInput == meaning {
                bestQual = max(bestQual, 2)
			} else if levenshtein.distance(between: normalizedInput, and: String(meaning)) <= okDist {
                bestQual = max(bestQual, 1)
            }
        }
        return bestQual
    }
    func evaluateReadingAnswerInner(normalizedInput reading: String) -> Int {
        if self.importantReadings.contains(String(reading)) {
            return 2
        } else if self.unimportantReadings.contains(String(reading)) {
            return 1
        } else {
            return 0
        }
    }
    func evaluateReadingAnswer(input: String, withAlternatives: Bool) -> (outcome: TestOutcome, qual: Int, alternatives: [Item]) {
        // TODO this sucks
        let normalizedInput = String(normalizeReading(String(input)))
        let qual = evaluateReadingAnswerInner(normalizedInput: normalizedInput)
        var outcome: TestOutcome = qual > 0 ? .right : .wrong
        let alternatives = withAlternatives ? readingAlternatives(reading: normalizedInput) : []
        if outcome == .wrong && alternatives.contains(where: { (alternative: Item) in
            (alternative as! NormalItem).meanings.contains(where: { (meaning: String) in
                self.meanings.contains(meaning)
            })
        }) {
            outcome = .mu
        }
        return (outcome, qual, alternatives)

    }
    func evaluateMeaningAnswer(input: String, withAlternatives: Bool) -> (outcome: TestOutcome, qual: Int, alternatives: [Item]) {
        let normalizedInput = String(normalizeMeaning(String(input)))
        var levenshtein = Levenshtein()
        let qual = evaluateMeaningAnswerInner(normalizedInput: normalizedInput, levenshtein: &levenshtein)
        var outcome: TestOutcome = qual > 0 ? .right : .wrong
        let alternatives = withAlternatives ? meaningAlternatives(meaning: normalizedInput) : []
        if outcome == .wrong && alternatives.contains(where: { (alternative: Item) in
            (alternative as! NormalItem).readings.contains(where: { (reading: String) in
                self.readings.contains(reading)
            })
        }) {
            outcome = .mu
        }
        return (outcome, qual, alternatives)
    }
    func cliReadings(colorful: Bool) -> String {
        let x = commaJoin(self.importantReadings)
        var out = colorful ? ANSI.red(x) : x
        if !self.unimportantReadings.isEmpty {
            let y = commaJoin(self.unimportantReadings)
            out += " >> " + (colorful ? ANSI.dred(y) : y)
        }
        return out
    }
    func cliMeanings(colorful: Bool) -> String {
        return commaJoin(self.meanings)
    }
    override func cliPrint(colorful: Bool) {
        print("\(self.cliName) \(self.cliReadings(colorful: colorful)) \(self.cliMeanings(colorful: colorful))")
    }
    func tildify(_ prompt: String) -> String {
        if self.character.starts(with: "〜") {
            return "(〜) " + prompt
        } else {
            return prompt
        }
    }
    var cliName: String { fatalError("lol") } // TODO
    override var availableTests: [TestKind] { return [.characterToRM, .meaningToReading, .readingToMeaning] }
}
class Word : NormalItem, CustomStringConvertible {
    init(json: NSDictionary) {
        let readings = commaSplitNoTrim(json["kana"] as! String).map(normalizeReading)
        super.init(json: json, readings: readings, importantReadings: readings, unimportantReadings: [])
    }
    var description: String {
        return "<Word \(self.character)>"
    }
    override var kind: ItemKind { return .word }
    override var cliName: String { return String(self.name) }
}
class Kanji : NormalItem, CustomStringConvertible {
    init(json: NSDictionary) {
        var readings: [String] = []
        var importantReadings: [String] = []
        var unimportantReadings: [String] = []
        let importantKind = json["important_reading"] as! String
        for kind in ["kunyomi", "nanori", "onyomi"] {
            if let obj = json[kind], !(obj is NSNull) && !(obj as? NSString == "None") {
                let theseReadings = commaSplitNoTrim(obj as! String).map(normalizeReading)
                readings += theseReadings
                if kind == importantKind {
                    importantReadings += theseReadings
                } else {
                    unimportantReadings += theseReadings
                }
            }
        }
        ensure(!readings.isEmpty)
        ensure(!importantReadings.isEmpty)
        super.init(json: json, readings: readings, importantReadings: importantReadings, unimportantReadings: unimportantReadings)
    }
    var description: String {
        return "<Kanji \(self.character)>"
    }
    override var kind: ItemKind { return .kanji }
    override var cliName: String { return ANSI.purple(String(self.name) + " /k") }
}
class Confusion: Item, CustomStringConvertible {
    let characters: [String]
    let items: [Item]
    let isWord: Bool
    init(line: String, isWord: Bool) {
        let allXs: ItemListProtocol
        if isWord {
            self.characters = line.split(separator: "/").map { trim($0) }
            allXs = Subete.instance.allWords
        } else {
            self.characters = trim(line).map { String($0) }
            allXs = Subete.instance.allKanji
        }
        self.items = self.characters.map {
			let item = allXs.findByName($0)
            if item == nil { fatalError("invalid item '\($0)' in confusion") }
            return item!
        }
        self.isWord = isWord
        super.init(name: self.characters[0])
    }
    var description: String {
        return "<Confusion \(self.items)>"
    }
    override var kind: ItemKind { return .confusion }
    override var availableTests: [TestKind] { return [.confusion] }
}

protocol ItemListProtocol {
    func findByName(_ name: String) -> Item?
    func findByReading(_ reading: String) -> [Item]
    func findByMeaning(_ meaning: String) -> [Item]
    var vagueItems: [Item] { get }
}
class ItemList<X: Item>: CustomStringConvertible, ItemListProtocol {
    let items: [X]
    let byName: [String: X]
    let byReading: [String: [X]]
    let byMeaning: [String: [X]]
    init(_ items: [X]) {
        self.items = items
        var byName: [String: X] = [:]
        var byReading: [String: [X]] = [:]
        var byMeaning: [String: [X]] = [:]
        for item in items {
            if byName[item.name] != nil {
                fatalError("duplicate \(X.self) item named \(item.name)")
            }
            byName[item.name] = item
            if let normalItem = item as? NormalItem {
                for reading in normalItem.readings {
                    byReading[reading] = (byReading[reading] ?? []) + [item]
                }
                for meaning in normalItem.meanings {
                    byMeaning[meaning] = (byMeaning[meaning] ?? []) + [item]
                }
            }
        }
        self.byName = byName
        self.byReading = byReading
        self.byMeaning = byMeaning
    }
    var description: String {
        return "ItemList[\(self.items)]"
    }
    func findByName(_ name: String) -> Item? {
        return self.byName[name]
    }
    func findByReading(_ reading: String) -> [Item] {
        return self.byReading[reading] ?? []
    }
    func findByMeaning(_ meaning: String) -> [Item] {
        return self.byMeaning[meaning] ?? []
    }
    var vagueItems: [Item] {
        return self.items
    }
}

enum TestKind: String {
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

struct TestResult {
    let testKind: TestKind
    let item: Item
    let date: Date?
    let outcome: TestOutcome
    func getRecordLine() -> String {
        let components: [String] = [
            String(Int(Date().timeIntervalSince1970)),
            self.testKind.rawValue,
            self.item.kind.rawValue,
            self.item.name,
            self.outcome.rawValue
        ]
        return components.joined(separator: ":")
    }
    static let retiredInfo: NSDictionary = loadYAML(path: "\(Subete.instance.basePath)/retired.yaml") as! NSDictionary
    static let retired: Set<String> = Set(retiredInfo["retired"] as! [String])
    static let replace: [String: String] = retiredInfo["replace"] as! [String: String]
	static func parse(line: String) throws -> TestResult? {
        var components: [String] = trim(line).split(separator: ":").map { String($0) }
        var date: Date? = nil
        if components.count > 4 {
            
            let rawDate = components.remove(at: 0)
            
            date = Date(timeIntervalSince1970: try unwrapOrThrow(Double(rawDate),
                                                                    err: MyError("invalid timestamp \(rawDate)")))
            
        }
        ensure(components.count >= 4)
        if components.count > 4 {
            warn("extra components")
        }
        
        // TODO: rawValue with substring?
        let itemKind = try unwrapOrThrow(ItemKind(rawValue: String(components[1])),
                                     err: MyError("invalid item kind \(components[1])"))
        var name = String(components[2])
        if retired.contains(name) {
			return nil
		} else if let newName = replace[name] {
			name = newName
		}

        return TestResult(
            testKind: try unwrapOrThrow(TestKind(rawValue: String(components[0])),
                                    err: MyError("invalid test kind \(components[0])")),
            item: try unwrapOrThrow(Subete.instance.allByKind(itemKind).findByName(name),
                                err: MyError("no such item kind \(components[1]) name \(name)")),
            date: date,
            outcome: try unwrapOrThrow(TestOutcome(rawValue: String(components[3])),
                                   err: MyError("invalid outcome kind \(components[3])"))
        )
    }
    static func readAllFromLog() throws -> [TestResult] {
        let data = try Subete.instance.openLogTxt(write: false) { (fh: FileHandle) in fh.readDataToEndOfFile() }
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n").compactMap {
			do {
				return try TestResult.parse(line: String($0))
			} catch let e {
				warn("error parsing log line: \(e)")
				return nil
			}
		}
    }
}

struct ANSI {
    static func color(_ code: String, _ s: String) -> String {
        return "\u{1b}[\(code)m\(s)\u{1b}[0m"
    }
    static func red(_ s: String) -> String { return color("31;1", s) }
    static func dred(_ s: String) -> String { return color("31", s) }
    static func green(_ s: String) -> String { return color("32;1", s) }
    static func blue(_ s: String) -> String { return color("34;1", s) }
    static func purple(_ s: String) -> String { return color("35;1", s) }
    static func yback(_ s: String) -> String { return color("43", s) }
    static func rback(_ s: String) -> String { return color("41", s) }
    static func cback(_ s: String) -> String { return color("106", s) }
}
class Test {
    let testKind: TestKind
    let item: Item
    var result: TestResult? = nil
    var appendedStuff: Data? = nil
    var didCliRead: Bool = false
    init(kind: TestKind, item: Item) {
        self.testKind = kind
        self.item = item
    }

    func removeFromLog() throws {
        let toRemove = self.appendedStuff!
        try Subete.instance.openLogTxt(write: true) { (fh: FileHandle) throws in
            let welp = MyError("log.txt did not end with what we just appended to it")
            let len = fh.seekToEndOfFile()
            if len < toRemove.count {
                print("len=\(len) toRemove.count=\(toRemove.count)")
                throw welp
            }
            let truncOffset = len - UInt64(toRemove.count)
            fh.seek(toFileOffset: truncOffset)
            let actualData = fh.readDataToEndOfFile()
            if actualData != toRemove {
                print(actualData)
                print(toRemove)
                throw welp
            }
            fh.truncateFile(atOffset: truncOffset)
            Subete.instance.lastAppendedTest = nil
            self.appendedStuff = nil
        }
    }
    func addToLog() throws {
        let toAppend = Data((self.result!.getRecordLine() + "\n").utf8)
        try Subete.instance.openLogTxt(write: true) { (fh: FileHandle) throws in
            fh.seekToEndOfFile()
            fh.write(toAppend)
            Subete.instance.lastAppendedTest = self
            self.appendedStuff = toAppend
        }
    }
    func cliGo() throws {
        switch self.testKind {
        case .meaningToReading:
            try self.doCLIMeaningToReading(item: self.item as! NormalItem)
        case .readingToMeaning:
            try self.doCLIReadingToMeaning(item: self.item as! NormalItem)
        case .characterToRM:
            try self.doCLICharacterToRM(item: self.item as! NormalItem)
        case .confusion:
            try self.doCLIConfusion(item: self.item as! Confusion)
        }
        if self.result == nil {
            try! self.markResult(outcome: .right)
        }
    }
    func cliLabel(outcome: TestOutcome, qual: Int) -> String {
        let text: String
        var back: (String) -> String
        switch outcome {
        case .wrong:
            (text, back) = ("NOPE", ANSI.rback)
        case .mu:
            (text, back) = ("MU", ANSI.cback)
        case .right:
            (text, back) = ("YEP" + (qual == 1 ? "?" : ""), ANSI.yback)
        }
        // THIS SUCKS
        if self.result?.outcome == .wrong {
            back = ANSI.rback
        } else if self.result?.outcome == .mu {
            back = ANSI.cback
        }
        return back(text)
    }

    func doCLIMeaningToReading(item: NormalItem) throws {
        var prompt = commaJoin(item.meanings)
        prompt = item.tildify(prompt)
        if item is Kanji {
            prompt = ANSI.purple(prompt) + " /k"
        }
        while true {
            let k = try cliRead(prompt: prompt, kana: true)
            let (outcome, qual, alternatives) = item.evaluateReadingAnswer(input: k, withAlternatives: true)
            var out: String = cliLabel(outcome: outcome, qual: qual)
            out += " " + item.cliName + " " + item.cliReadings(colorful: false)
            print(out)
            item.cliPrintAlternatives(alternatives, isReading: true)
            item.cliPrintSimilarMeaning()
        
            if outcome == .right {
                break
            } else if self.result == nil {
                try! self.markResult(outcome: outcome)
            }
        }
    }
    func doCLIReadingToMeaning(item: NormalItem) throws {
        //var prompt = commaJoin(item.readings)
        var prompt = item.cliReadings(colorful: false)
        prompt = item.tildify(prompt)
        if item is Kanji {
            prompt += " /k"
        }
        while true {
            let k: String = try cliRead(prompt: prompt, kana: false)
            let (outcome, qual, alternatives) = item.evaluateMeaningAnswer(input: k, withAlternatives: true)
            print(cliLabel(outcome: outcome, qual: qual))
            item.cliPrint(colorful: true)
            item.cliPrintAlternatives(alternatives, isReading: false)
            if outcome != .right {
                item.cliPrintSameReadingIfFew()
            }
            if outcome == .right {
                break
            } else if self.result == nil {
                try! self.markResult(outcome: outcome)
            }
        }
    }
    func doCLICharacterToRM(item: NormalItem) throws {
        let prompt = item.cliName
        
        enum Mode { case reading, meaning }
        for mode in [Mode.reading, Mode.meaning].shuffled() {
            while true {
                let k: String = try cliRead(prompt: prompt, kana: mode == .reading)
                let outcome: TestOutcome
                let qual: Int
                let alternatives: [Item]
                if mode == .meaning {
                    (outcome, qual, alternatives) = item.evaluateMeaningAnswer(input: k, withAlternatives: false)
                    print(cliLabel(outcome: outcome, qual: qual))
                    print(item.cliMeanings(colorful: true))
                    item.cliPrintMeaningAlternatives(alternatives)
                } else {
                    (outcome, qual, _) = item.evaluateReadingAnswer(input: k, withAlternatives: false)
                    print(cliLabel(outcome: outcome, qual: qual))
                    print(item.cliReadings(colorful: true))
                }
                
               
                if outcome == .right {
                    break
                } else if self.result == nil {
                    try! self.markResult(outcome: outcome)
                }
            }
        }
    }
    func doCLIConfusion(item: Confusion) throws {
        for subitem in item.items.shuffled() {
            try doCLICharacterToRM(item: subitem as! NormalItem)
        }
    }
    static let readingPrompt: String = ANSI.red("reading> ")
    static let meaningPrompt: String = ANSI.blue("meaning> ")

    func cliRead(prompt: String, kana: Bool) throws -> String {
        while true {
            print(prompt)
            let args: [String]
            if kana {
                args = [Subete.instance.basePath + "/read-kana.zsh", Test.readingPrompt]
            } else {
                args = [Subete.instance.basePath + "/read-english.zsh", Test.meaningPrompt]
            }
            let output = trim(try runAndGetOutput(args))
            
            if output == "" {
                continue
            }
            if output.starts(with: "!") {
                Subete.instance.handleBang(output, curTest: self)
                continue
            }
            // TODO: Python checks for doublewidth here
            self.didCliRead = true
            return output
        }
    }

    func markResult(outcome: TestOutcome?) throws {
        if self.result != nil {
            try self.removeFromLog()
            Subete.instance.srs?.revert(forItem: self.item)
        }
        if let outcome = outcome {
            self.result = TestResult(testKind: self.testKind, item: self.item, date: Date(), outcome: outcome)
            try self.addToLog()
            Subete.instance.srs?.update(self.result!)
        } else {
            self.result = nil
        }
    }
}

class SRS {
    struct ItemInfo {
        var points: Int = 0
        var lastSeen: Date? = nil
        var level: Int {
            return 0 // XXX
        }
        var nextTestDate: Date {
            guard let lastSeen = self.lastSeen else {
                return Date()
            }
            let interval: TimeInterval
            switch self.level {
            case 0:
                interval = 60*60*12
            default:
                fatalError("?")
            }
            return lastSeen + interval
        }
    }
    var itemInfo: [Item: ItemInfo] = [:]
    var backup: (Item, ItemInfo)? = nil
    func update(_ result: TestResult) {
        var info = itemInfo[result.item] ?? ItemInfo()
        self.backup = (result.item, info)
        var pointsToAward = 1
        if let lastSeen = info.lastSeen, let date = result.date {
            let interval = date.timeIntervalSince(lastSeen)
            // TODO copy from some sources
            if interval >= 60*60*24 {
                pointsToAward = 2
            }
        }
        info.points += pointsToAward
        info.lastSeen = result.date
        itemInfo[result.item] = info
    }
    func revert(forItem item: Item) {
        let backup = self.backup!
        ensure(backup.0 == item)
        self.itemInfo[backup.0] = backup.1
        self.backup = nil
    }
}


struct WeightedList<T> {
    struct Entry {
        let value: T
        let weight: Double
        var cumulativeWeight: Double
        var taken: Bool
    }
    var entries: [Entry] = []
    var totalUntakenWeight: Double = 0

    init() {}

    var totalWeight: Double {
        return entries.last?.cumulativeWeight ?? 0
    }
    var isEmpty: Bool { return entries.isEmpty }
    
    mutating func addAll(_ values: [T], weight: Double) {
        for value in values {
            add(value, weight: weight)
        }
    }
    mutating func add(_ value: T, weight: Double) {
        entries.append(Entry(value: value, weight: weight, cumulativeWeight: totalWeight + weight, taken: false))
        totalUntakenWeight += weight
    }
    func indexOfRandomElement() -> Int {
        let target = Double.random(in: 0.0 ..< totalWeight)
        var lo: Int = 0
        var hi: Int = entries.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let cw = entries[mid].cumulativeWeight
            if target < cw - entries[mid].weight {
                hi = mid - 1
            } else if target >= cw {
                lo = mid + 1
            } else {
                return mid
            }
        }
        fatalError("binary search failed, target=\(target) totalWeight=\(totalWeight)")
    }
    mutating func reindex() {
        var cw: Double = 0
        for i in 0..<entries.count {
            cw += entries[i].weight
            entries[i].taken = false
            entries[i].cumulativeWeight = cw
        }
        totalUntakenWeight = cw
    }

    mutating func takeRandomElement() -> T? {
        if isEmpty { return nil }
        var i: Int = -1
		while true {
            i = indexOfRandomElement()
            if !entries[i].taken { break }
        }
        entries[i].taken = true
        totalUntakenWeight -= entries[i].weight

        if totalUntakenWeight < totalWeight / 2 {
            reindex()
        }
        return entries[i].value
    }
}

func main() {
    let _ = Subete()
    while true {
		time { Subete.instance.createSRSFromLog() }
	}
    return
    //print(Subete.instance.allByKind(.word).findByMeaning(String(normalizeMeaning("to narrow"))))
    //return
    let argv = CommandLine.arguments
    if argv.count > 2 {
        fatalError("too many CLI arguments")
    }
    let mode = argv.count > 1 ? argv[1] : "all"
    var items: WeightedList<Item> = WeightedList()
    //print("w \(Subete.instance.allItems.count) \(Subete.instance.allConfusion.items.count)")
    switch mode {
        case "all":
            items.addAll(Subete.instance.allItems, weight: 1.0)
            items.addAll(Subete.instance.allConfusion.items, weight: 10.0)
        case "confusion":
            items.addAll(Subete.instance.allConfusion.items, weight: 1.0)
        default:
            fatalError("unknown mode \(mode)")
    }

    //let items: [Item] 
    //let items: [Item] = Subete.instance.allConfusion.items.filter { $0.isWord }
    var remainingItems: Set<Item> = Set()
    while remainingItems.count < 50 && !items.isEmpty {
        remainingItems.insert(items.takeRandomElement()!)
    }
    var numDone = 0
    do {
        while let item = remainingItems.randomElement() {
            let testKind = item.availableTests.randomElement()!
            let test = Test(kind: testKind, item: item)
            print("[\(numDone)]") // TODO remainingItems
            try test.cliGo()
            numDone += 1
            if test.result!.outcome == .right {
                remainingItems.remove(item)
            }
            
        }
    } catch is ExitStatusError {
        return
    } catch let e {
        try! { throw e }() // TODO
    }
}
Levenshtein.test()
main()
