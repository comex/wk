import Foundation
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
func trim(_ s: String) -> String {
    return s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
}
func commaSplit(_ s: String) -> [String] {
    return s.components(separatedBy: ",").map(trim)
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
    var myArgs: [UnsafeMutablePointer<Int8>?] = args.map {
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
    let allWords: ItemList<Word>
    let allKanji: ItemList<Kanji>
    var allItems: [Item]! = nil
    var allConfusion: ItemList<Confusion>! = nil
    var srs: SRS? = nil
    
    var lastAppendedTest: Test?
    
    let basePath = "/Users/comex/c/wk/"

    init() {
        print("loading json")
        self.allWords = ItemList((loadJSON(path: basePath + "vocabulary.json") as! NSArray).map { Word(json: $0 as! NSDictionary) })
        self.allKanji = ItemList((loadJSON(path: basePath + "kanji.json") as! NSArray).map { Kanji(json: $0 as! NSDictionary) })
        Subete.instance = self
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
    func handleBang(_ input: String) {
        switch input {
        case "!right":
            handleChangeLast(outcome: .right)
        case "!wrong":
            handleChangeLast(outcome: .wrong)
        case "!mu":
            handleChangeLast(outcome: .mu)
        default:
            print("?bang? \(input)")
        }
    }
    func handleChangeLast(outcome: TestOutcome) {
        guard let test = self.lastAppendedTest else {
            print("no last")
            return
        }
        try! test.markResult(outcome: outcome)
    }
}

enum ItemKind: String {
    case word, kanji, confusion
}
class Item: Hashable, Equatable {
    let name: String
    init(name: String) {
        self.name = name
    }
    var kind: ItemKind { fatalError("?") }
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.name)
    }
    static func == (lhs: Item, rhs: Item) -> Bool {
        return lhs === rhs
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
    var reading = trim(input)
    reading = reading.replacingOccurrences(of: "-", with: "ー")
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
        self.meanings = commaSplit(json["meaning"] as! String).map(normalizeMeaning)
        self.readings = readings
        self.importantReadings = importantReadings
        self.unimportantReadings = unimportantReadings
        super.init(name: self.character)
    }
    func readingAlternatives(input: String) -> [Item] {
        return Subete.instance.allByKind(self.kind).findByReading(input).filter { $0 != self }
        
    }
    func cliPrintReadingAlternatives(input: String) {
        let items = readingAlternatives(input: input)
        if items.isEmpty { return }
        print(" Entered kana matches:")
        for item in items {
            item.cliPrint(colorful: false)
        }
    }
    func meaningMatches(normalizedInput: String) -> Bool {
        return self.evaluateMeaningAnswerInner(normalizedInput: normalizedInput) > 0
    }
    func meaningAlternatives(input: String) -> [Item] {
        let normalizedInput = normalizeMeaning(input)
        return Subete.instance.allByKind(self.kind).vagueItems.filter { (other: Item) -> Bool in
            return other != self && (other as! NormalItem).meaningMatches(normalizedInput: normalizedInput)
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
        return Subete.instance.allByKind(self.kind).vagueItems.filter { (other: Item) -> Bool in
            return other != self && self.meanings.contains { (other as! NormalItem).meaningMatches(normalizedInput: $0) }
        }

    }
    func cliPrintSimilarMeaning() {
        let items = similarMeaning()
        if items.isEmpty { return }
        print(" Similar meaning:")
        for item in items {
            item.cliPrint(colorful: false)
        }
    }

    // without alternatives, without normalization, just return qual
    func evaluateMeaningAnswerInner(normalizedInput: String) -> Int {
        return self.meanings.lazy.map { (meaning: String) -> Int in
            // TODO
            return meaning == normalizedInput ? 1 : 0
        }.max() ?? 0
    }
    func evaluateReadingAnswer(input: String) -> (outcome: TestOutcome, qual: Int) {
        let reading = normalizeReading(input)
        //print("\(self.importantReadings) <-> \([reading])")
        if self.importantReadings.contains(reading) {
            return (.right, 2)
        } else if self.unimportantReadings.contains(reading) {
            return (.right, 1)
        } else {
            return (.wrong, 0)
        }
    }
    func evaluateMeaningAnswer(input: String, withAlternatives: Bool) -> (outcome: TestOutcome, qual: Int, alternatives: [Item]) {
        let normalizedInput = normalizeMeaning(input)
        let qual = evaluateMeaningAnswerInner(normalizedInput: normalizedInput)
        var outcome: TestOutcome = qual > 0 ? .right : .wrong
        let alternatives = withAlternatives ? meaningAlternatives(input: normalizedInput) : []
        if outcome == .wrong && !alternatives.isEmpty {
            outcome = .mu
        }
        return (qual > 0 ? .right : .wrong, qual, alternatives)
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
        print("\(self.ansiName) \(self.cliReadings(colorful: colorful)) \(self.cliMeanings(colorful: colorful))")
    }
    var ansiName: String { fatalError("lol") } // TODO
    override var availableTests: [TestKind] { return [.characterToRM, .meaningToReading, .readingToMeaning] }
}
class Word : NormalItem, CustomStringConvertible {
    init(json: NSDictionary) {
        let readings = commaSplit(json["kana"] as! String).map(normalizeReading)
        super.init(json: json, readings: readings, importantReadings: readings, unimportantReadings: [])
    }
    var description: String {
        return "<Word \(self.character)>"
    }
    override var kind: ItemKind { return .word }
    override var ansiName: String { return self.name }

}
class Kanji : NormalItem, CustomStringConvertible {
    init(json: NSDictionary) {
        var readings: [String] = []
        var importantReadings: [String] = []
        var unimportantReadings: [String] = []
        let importantKind = json["important_reading"] as! String
        for kind in ["kunyomi", "nanori", "onyomi"] {
            if let obj = json[kind], !(obj is NSNull) && !(obj as? NSString == "None") {
                let theseReadings = commaSplit(obj as! String).map(normalizeReading)
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
    override var ansiName: String { return ANSI.purple(self.name) + " /k" }
    
}
class Confusion: Item, CustomStringConvertible {
    let characters: [String]
    let items: [Item]
    init(line: String, isWord: Bool) {
        let allXs: ItemListProtocol
        if isWord {
            self.characters = line.split(separator: "/").map { trim(String($0)) }
            allXs = Subete.instance.allWords
        } else {
            self.characters = trim(line).map { String($0) }
            allXs = Subete.instance.allKanji
        }
        self.items = self.characters.map { allXs.findByName($0)! }
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
    var vagueItems: [Item] { get }
}
class ItemList<X: Item>: CustomStringConvertible, ItemListProtocol {
    let items: [X]
    let byName: [String: X]
    let byReading: [String: [X]]
    init(_ items: [X]) {
        self.items = items
        var byName: [String: X] = [:]
        var byReading: [String: [X]] = [:]
        for item in items {
            ensure(byName[item.name] == nil)
            byName[item.name] = item
            if let normalItem = item as? NormalItem {
                for reading in normalItem.readings {
                    byReading[reading] = (byReading[reading] ?? []) + [item]
                }
            }
        }
        self.byName = byName
        self.byReading = byReading
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
    static let retired: Set<String> = ["毒言", "札", "農", "先年"]
    static let replace: [String: String] = ["取決め": "取り決め"]
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
        
        let itemKind = try unwrapOrThrow(ItemKind(rawValue: components[1]),
                                     err: MyError("invalid item kind \(components[1])"))
        var name = String(components[2])
        if retired.contains(name) {
            return nil
        } else if let newName = replace[name] {
            name = newName
        }
        return TestResult(
            testKind: try unwrapOrThrow(TestKind(rawValue: components[0]),
                                    err: MyError("invalid test kind \(components[0])")),
            item: try unwrapOrThrow(Subete.instance.allByKind(itemKind).findByName(name),
                                err: MyError("no such item kind \(components[1]) name \(name)")),
            date: date,
            outcome: try unwrapOrThrow(TestOutcome(rawValue: components[3]),
                                   err: MyError("invalid outcome kind \(components[3])"))
        )
    }
    static func readAllFromLog() throws -> [TestResult] {
        let data = try Subete.instance.openLogTxt(write: false) { (fh: FileHandle) in fh.readDataToEndOfFile() }
        let text = String(decoding: data, as: UTF8.self)
        return try text.split(separator: "\n").compactMap { try TestResult.parse(line: String($0)) }
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
}
class Test {
    let testKind: TestKind
    let item: Item
    var result: TestResult? = nil
    var appendedStuff: Data? = nil
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
            try self.doConfusion(item: self.item as! Confusion)
        }
        if self.result == nil {
            try! self.markResult(outcome: .right)
        }
    }
    var wasWrong: Bool {
        return self.result?.outcome == .wrong
    }
    static let NOPE = ANSI.rback("NOPE")
    func maybeYEP() -> String {
        return self.wasWrong ? ANSI.rback("YEP") : ANSI.yback("YEP")
    }
    func cliLabelForQual(_ qual: Int) -> String {
        return [Test.NOPE, maybeYEP() + "?", maybeYEP()][qual]
    }

    func doCLIMeaningToReading(item: NormalItem) throws {
        var prompt = commaJoin(item.meanings)
        if item.character.starts(with: "〜") {
            prompt = "(〜) " + prompt
        }
        if item is Kanji {
            prompt = ANSI.purple(prompt) + " /k"
        }
        while true {
            let k = try cliRead(prompt: prompt, kana: true)
            let (outcome, qual) = item.evaluateReadingAnswer(input: k)
            var out: String = cliLabelForQual(qual)
            out += " " + item.cliReadings(colorful: false)
            print(out)
            item.cliPrintReadingAlternatives(input: k)
            item.cliPrintSimilarMeaning()
        
            if outcome == .right {
                break
            } else if self.result == nil {
                try! self.markResult(outcome: outcome)
            }
        }
    }
    func doCLIReadingToMeaning(item: NormalItem) throws {
        var prompt = commaJoin(item.readings)
        if item is Kanji {
            prompt += " /k"
        }
        while true {
            let k: String = try cliRead(prompt: prompt, kana: false)
            let (outcome, qual, alternatives) = item.evaluateMeaningAnswer(input: k, withAlternatives: true)
            print(cliLabelForQual(qual))
            item.cliPrint(colorful: true)
            item.cliPrintMeaningAlternatives(alternatives)
            if outcome == .right {
                break
            } else if self.result == nil {
                try! self.markResult(outcome: outcome)
            }
        }
    }
    func doCLICharacterToRM(item: NormalItem) throws {
        let prompt = item.character
        
        enum Mode { case reading, meaning }
        for mode in [Mode.reading, Mode.meaning].shuffled() {
            while true {
                let k: String = try cliRead(prompt: prompt, kana: mode == .reading)
                let outcome: TestOutcome
                let qual: Int
                if mode == .meaning {
                    (outcome, qual, _) = item.evaluateMeaningAnswer(input: k, withAlternatives: false)
                    print(cliLabelForQual(qual))
                    print(item.cliMeanings(colorful: true))
                } else {
                    (outcome, qual) = item.evaluateReadingAnswer(input: k)
                    print(cliLabelForQual(qual))
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
    func doConfusion(item: Confusion) throws {
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
                Subete.instance.handleBang(output)
                continue
            }
            // TODO: Python checks for doublewidth here
            return output
        }
    }

    func markResult(outcome: TestOutcome) throws {
        if self.result != nil {
            try self.removeFromLog()
            Subete.instance.srs?.revert(forItem: self.item)
        }
        self.result = TestResult(testKind: self.testKind, item: self.item, date: Date(), outcome: outcome)
        try self.addToLog()
        Subete.instance.srs?.update(self.result!)
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

func main() {
    let subete = Subete()
    subete.createSRSFromLog()
    var remainingItems: Set<Item> = Set(Subete.instance.allItems.shuffled()[..<50])
    var numDone = 0
    do {
        while let item = remainingItems.randomElement() {
            let testKind = item.availableTests.randomElement()!
            let test = Test(kind: testKind, item: item)
            print("[\(numDone)]")
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
main()
