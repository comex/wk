import Foundation
func warn(_ s: String) {
    print(s)
}
struct MyError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
func trim(_ s: String) -> String {
    return s.trimmingCharacters(in: CharacterSet.whitespaces)
}
func commaSplit(_ s: String) -> [String] {
    return s.components(separatedBy: ",").map(trim)
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


class Subete {
    static var instance: Subete!
    let allWords: ItemList<Word>
    let allKanji: ItemList<Kanji>
    var allItems: [Item]! = nil
    var allConfusion: ItemList<Confusion>! = nil
    
    var lastAppendedTest: Test?
    
    let basePath = "/Users/comex/c/wk/"

    init() {
        self.allWords = ItemList((loadJSON(path: basePath + "vocabulary.json") as! NSArray).map { Word(json: $0 as! NSDictionary) })
        self.allKanji = ItemList((loadJSON(path: basePath + "kanji.json") as! NSArray).map { Kanji(json: $0 as! NSDictionary) })
        Subete.instance = self
        let allKanjiConfusion = loadConfusion(path: basePath + "confusion.txt", isWord: false)
        let allWordConfusion = loadConfusion(path: basePath + "confusion-vocab.txt", isWord: true)
        self.allConfusion = ItemList(allKanjiConfusion + allWordConfusion)
        self.allItems = self.allWords.items + self.allKanji.items + self.allConfusion.items

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
        self.meanings = commaSplit(json["meaning"] as! String)
        self.readings = readings
        self.importantReadings = importantReadings
        self.unimportantReadings = unimportantReadings
        super.init(name: self.character)
    }
    func readingAlternatives(input: String) -> [Item] {
        
    }
    func cliPrintReadingAlternatives(input: String) {
        
    }
    func cliPrintSimilarMeaning() {
        
    }
    func readingAnswerQuality(input: String) -> Int {
        return 0
    }
    
}
class Word : NormalItem, CustomStringConvertible {
    init(json: NSDictionary) {
        let readings = commaSplit(json["kana"] as! String)
        super.init(json: json, readings: readings, importantReadings: readings, unimportantReadings: [])
    }
    var description: String {
        return "<Word \(self.character)>"
    }
    override var kind: ItemKind { return .word }

}
class Kanji : NormalItem, CustomStringConvertible {
    init(json: NSDictionary) {
        var readings: [String] = []
        var importantReadings: [String] = []
        var unimportantReadings: [String] = []
        let importantKind = json["important_reading"] as! String
        for kind in ["kunyomi", "nanori", "onyomi"] {
            if let obj = json[kind], !(obj is NSNull) && !(obj as? NSString == "None") {
                let theseReadings = commaSplit(obj as! String)
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
}

protocol ItemListProtocol {
    func findByName(_ name: String) -> Item?
    func findByReading(_ reading: String) -> [Item]
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
            if len > toRemove.count { throw welp }
            let truncOffset = len - UInt64(toRemove.count)
            fh.seek(toFileOffset: truncOffset)
            let actualData = fh.readDataToEndOfFile()
            if actualData != toRemove { throw welp }
            fh.truncateFile(atOffset: truncOffset)
            Subete.instance.lastAppendedTest = nil
            self.appendedStuff = nil
        }
    }
    func addToLog() throws {
        let toAppend = Data(("\n" + self.result!.getRecordLine()).utf8)
        try Subete.instance.openLogTxt(write: true) { (fh: FileHandle) throws in
            fh.seekToEndOfFile()
            fh.write(toAppend)
            Subete.instance.lastAppendedTest = self
            self.appendedStuff = toAppend
        }
    }
    
    func doCLIMeaningToReading() {
        let item = self.item as! NormalItem
        var prompt = item.meanings.joined(separator: ", ")
        if item.character.starts(with: "〜") {
            prompt = "(〜) " + prompt
        }
        if item is Kanji {
            prompt = ANSI.purple(prompt) + " /k"
        }
        while true {
            let k = try! cliReadKana(prompt: prompt)
            let qual = item.readingAnswerQuality(k)
            var out: String = "?" //[NOPE, maybeYEP, + "?", maybeYEP][qual]
            out += " " + ANSI.red(item.importantReadings.joined(separator: ", "))
            if !item.unimportantReadings.isEmpty {
                out += " >> " + ANSI.dred(item.unimportantReadings.joined(separator: ", "))
            }
            print(out)
            item.cliPrintReadingAlternatives(input: k)
            item.cliPrintSimilarMeaning()
            try! self.markResult(outcome: qual > 0 ? .right : .wrong)
            
            if qual > 0 {
                break
            }
            
            
        }
    }
    func cliReadKana(prompt: String) throws -> String {
        while true {
            print(prompt)
            let args = ["/Users/comex/c/wk/read_kana.zsh", prompt]
            let cl = NSConditionLock(condition: 0)
            
            try Process.run(URL(fileURLWithPath: args[0]), arguments: args) { (_: Process) -> Void in
                cl.lock(whenCondition: 0)
                cl.unlock(withCondition: 1)
            }
            cl.lock(whenCondition: 1)
            
            

        }
    }
    func markResult(outcome: TestOutcome) throws {
        if self.result != nil {
            try self.removeFromLog()
        }
        self.result = TestResult(testKind: self.testKind, item: self.item, date: Date(), outcome: outcome)
        try self.addToLog()
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

let _ = Subete()
let results = try! TestResult.readAllFromLog()
let srs = SRS()
for result in results { srs.update(result) }
