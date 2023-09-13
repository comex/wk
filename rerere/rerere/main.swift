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
import rerere_c
import Foundation
import Yams
import ArgumentParser
import XCTest

// TODO: ~ is broken for r2m
// TODO: !wrong doesn't act as expected when halfway through a k2rm
// TODO: don't let you mu more than once

func time<T>(count: Int, block: () -> T) {
    let a = CFAbsoluteTimeGetCurrent()
    for _ in 0..<count {
        blackBox(block())
    }
    let b = CFAbsoluteTimeGetCurrent()
    print((b - a) / Double(count))
}
func blackBox<T>(_ t: T) {
    withUnsafePointer(to: t) { (ptr) in
        blackBoxImpl(ptr)
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
func loadJSON(path: String) -> Any {
    return try! JSONSerialization.jsonObject(
        with: try! Data(contentsOf: URL(fileURLWithPath: path)),
        options: JSONSerialization.ReadingOptions())
}
func loadYAML(path: String) -> Any {
    return try! Yams.load(yaml: try! String(contentsOf: URL(fileURLWithPath: path)))!
}
func loadJSONAndExtraYAML<T: JSONInit>(basePath: String, stem: String, class: T.Type) -> [T] {
    let base = (loadJSON(path: "\(basePath)/\(stem).json") as! [NSDictionary]).map { T(json: $0, relaxed: false) }
    let extra = (loadYAML(path: "\(basePath)/extra-\(stem).yaml") as! [NSDictionary]).map { T(json: $0, relaxed: true) }
    return base + extra
}

let startupDate: Date = Date()
let myDateFormatter: DateFormatter = DateFormatter()
myDateFormatter.locale = Locale(identifier: "en_US_POSIX")
myDateFormatter.dateFormat = "yyyy-MM-dd"

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

struct StudyMaterial {
    let meaningSynonyms: [String]
}
func loadStudyMaterials(basePath: String) -> [Int: StudyMaterial] {
    let json = loadJSON(path: "\(basePath)/study_materials.json") as! [NSDictionary]
    var ret: [Int: StudyMaterial] = [:]
    for dict in json {
        let data = dict["data"] as! NSDictionary
        let subjectId = data["subject_id"] as! Int
        let meaningSynonyms = data["meaning_synonyms"] as! [String]
        ensure(ret[subjectId] == nil)
        ret[subjectId] = StudyMaterial(meaningSynonyms: meaningSynonyms)
    }
    return ret
}

class Subete {
    static var instance: Subete!
    var allWords: ItemList<Word>! = nil
    var allKanji: ItemList<Kanji>! = nil
    var allItems: [Item]! = nil
    var allConfusion: ItemList<Confusion>! = nil
    var srs: SRS? = nil
    var studyMaterials: [Int: StudyMaterial]! = nil
    
    var lastAppendedTest: Test?
    
    let basePath = "/Users/comex/c/wk"

    var nextItemID = 0

    init() {
        Subete.instance = self
        print("loading json")
        self.studyMaterials = loadStudyMaterials(basePath: basePath)
        self.allWords = ItemList(loadJSONAndExtraYAML(basePath: basePath, stem: "vocabulary", class: Word.self))
        self.allKanji = ItemList(loadJSONAndExtraYAML(basePath: basePath, stem: "kanji", class: Kanji.self))
        print("loading confusion")
        let allKanjiConfusion = loadConfusion(path: basePath + "/confusion.txt", isWord: false)
        let allWordConfusion = loadConfusion(path: basePath + "/confusion-vocab.txt", isWord: true)
        self.allConfusion = ItemList(allKanjiConfusion + allWordConfusion)
        self.allItems = self.allWords.items + self.allKanji.items + self.allConfusion.items
        print("loading srs")
        self.srs = self.createSRSFromLog()
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
        let url = URL(fileURLWithPath: basePath + "/log.txt")
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
    func createSRSFromLog() -> SRS {
        let results = try! TestResult.readAllFromLog()
        let srs = SRS()
        let srsEpoch = Date(timeIntervalSince1970: 1611966197)
        for result in results {
            guard let date = result.date else { continue }
            if date < srsEpoch { continue }
            let _ = srs.update(forResult: result)
        }
        for question in self.allQuestions {
            let _ = srs.info(question: question) // allow items with no results to stale
        }
        srs.updateStales(date: Date())
        return srs
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
        let srsUpdate = try! test.markResult(outcome: outcome)
        if !srsUpdate.isNoChangeOther {
            print(srsUpdate.cliLabel)
        }
    }
    var allQuestions: [Question] {
        return allItems.flatMap { $0.myQuestions }
    }
}

enum ItemKind: String, ExpressibleByArgument, Codable {
    case word, kanji, confusion
}

class Item: Hashable, Equatable, Comparable {
    let name: String
    let birthday: Date?
    let id: Int
    init(name: String, birthday: Date?) {
        self.name = name
        self.birthday = birthday
        self.id = Subete.instance.nextItemID
        Subete.instance.nextItemID = self.id + 1
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
    var kind: ItemKind {
        fatalError("must override kind on \(self)")
    }
    func cliPrint(colorful: Bool) {
        fatalError("must override cliPrint on \(self)")
    }
    var availableTests: [TestKind] {
        fatalError("must override availableTests on \(self)")
    }

    // this is separate in case I want to make Question more than just
    // (Item, TestKind) in the future
    var myQuestions: [Question] {
        return availableTests.map { Question(item: self, testKind: $0) }
    }
}


struct Question: Codable, Hashable, Equatable {
    let item: Item
    let testKind: TestKind

    struct CodedQuestion: Codable {
        let item: ItemRef
        let testKind: TestKind
    }

    init(item: Item, testKind: TestKind) {
        self.item = item
        self.testKind = testKind
    }
    init(from decoder: Decoder) throws {
        let cq = try CodedQuestion(from: decoder)
        item = cq.item.item
        testKind = cq.testKind
    }
    func encode(to encoder: Encoder) throws {
        let cq = CodedQuestion(item: ItemRef(item), testKind: testKind)
        try cq.encode(to: encoder)
    }
}

func normalizeMeaningTrimmed(_ meaning: String) -> String {
    return meaning
}
func normalizeReadingTrimmed(_ input: String) -> String {
    // TODO katakana to hiragana
    var reading: String = input //trim(input)
    if reading.contains("-") {
        reading = String(reading.replacingOccurrences(of: "-", with: "ー"))
    }
    return reading
}

enum IngType: Comparable {
    case primary, secondary, whitelist, synonym
}

struct Ing {
    let text: String
    let type: IngType
    let acceptedAnswerWK: Bool

    var acceptedAnswerForMe: Bool {
        // it's fiiiiine
        return true
    }

    init(readingWithJSON json: Any, relaxed: Bool) {
        if let text = json as? String, relaxed {
            self.text = text
            self.type = .primary
            self.acceptedAnswerWK = true
        } else {
            let json = json as! NSDictionary
            self.text = json["reading"] as! String
            self.type = json["primary"] as! Bool ? .primary : .secondary
            self.acceptedAnswerWK = json["accepted_answer"] as! Bool
        }
    }
    init(meaningWithJSON json: Any, relaxed: Bool) {
        if let text = json as? String, relaxed {
            self.text = text
            self.type = .primary
            self.acceptedAnswerWK = true
        } else {
            let json = json as! NSDictionary
            self.text = (json["meaning"] as! String).lowercased()
            self.type = json["primary"] as! Bool ? .primary : .secondary
            self.acceptedAnswerWK = json["accepted_answer"] as! Bool
        }
    }
    init(auxiliaryMeaningWithJSON json: Any) {
        let json = json as! NSDictionary
        self.text = json["meaning"] as! String
        let type = json["type"] as! String
        switch type {
        case "whitelist":
            self.type = .whitelist
            self.acceptedAnswerWK = true
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

protocol JSONInit {
    init(json: NSDictionary, relaxed: Bool)
}

class NormalItem: Item, JSONInit {
    let meanings: [Ing]
    let readings: [Ing]
    let character: String
    //let json: NSDictionary
    
    required init(json: NSDictionary, relaxed: Bool) {
        let data: NSDictionary
        let id: Int?
        if let d = json["data"] {
            data = d as! NSDictionary
            id = (json["id"] as! Int)
        } else {
            if !relaxed { fatalError("expected 'data'") }
            data = json
            id = nil
        }

        //self.json = json
        self.character = trim(data["characters"] as! String)
        self.readings = (data["readings"] as! [Any]).map { Ing(readingWithJSON: $0, relaxed: relaxed) }
        var meanings = (data["meanings"] as! [Any]).map { Ing(meaningWithJSON: $0, relaxed: relaxed) }
        if let auxiliaryMeanings = json["auxiliary_meanings"] {
            meanings += (auxiliaryMeanings as! [Any]).map { Ing(auxiliaryMeaningWithJSON: $0) }
        }
        if let id, let material = Subete.instance.studyMaterials[id] {
            meanings += material.meaningSynonyms.map { Ing(synonymWithText: $0) }
        }
        self.meanings = meanings
        super.init(name: self.character,
            birthday: data["birth"].map { $0 as! Date })
    }
    func readingAlternatives(reading: String) -> [Item] {
        let normalizedReading = normalizeReadingTrimmed(trim(reading))
        return Subete.instance.allByKind(self.kind).findByReading(normalizedReading).filter { $0 != self }
    }
    func meaningMatches(normalizedInput: String, levenshtein: inout Levenshtein) -> Bool {
        return self.evaluateMeaningAnswerInner(normalizedInput: normalizedInput, levenshtein: &levenshtein) > 0
    }
    func meaningAlternatives(meaning: String) -> [Item] {
        let normalizedMeaning = normalizeMeaningTrimmed(trim(meaning))
        /*
        var levenshtein = Levenshtein()
        return Subete.instance.allByKind(self.kind).vagueItems.filter { (other: Item) -> Bool in
            return other != self && (other as! NormalItem).meaningMatches(normalizedInput: normalizedMeaning, levenshtein: &levenshtein)
        }
        */
        let ret = Subete.instance.allByKind(self.kind).findByMeaning(normalizedMeaning).filter { $0 != self }
        return ret
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
    func similarMeaning() -> [Item] {
        var set: Set<Item> = []
        for meaning in self.meanings {
            set.formUnion(Subete.instance.allByKind(self.kind).findByMeaning(meaning.text))
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
            set.formUnion(Subete.instance.allByKind(self.kind).findByReading(reading.text))
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
        var bestQual: Int = 0
        for meaning in self.meanings {
            let okDist = Int(round(0.4 * Double(meaning.text.count)))
            let thisQual: Int
            if normalizedInput == meaning.text {
                thisQual = 2
            } else if levenshtein.distance(between: normalizedInput, and: meaning.text) <= okDist {
                thisQual = 1
            } else {
                continue
            }
            bestQual = max(bestQual, thisQual)
        }
        return bestQual
    }
    func evaluateReadingAnswerInner(normalizedInput: String) -> Int {
        var bestQual: Int = 0
        for reading in self.readings {
            if reading.text == normalizedInput {
                let thisQual = reading.type == .primary ? 2 : 1
                bestQual = max(bestQual, thisQual)
            }
        }
        return bestQual
    }

    func evaluateReadingAnswer(input: String, allowAlternatives: Bool) -> (outcome: TestOutcome, qual: Int, alternatives: [Item]) {
        // TODO this sucks
        let normalizedInput = normalizeReadingTrimmed(trim(input))
        let qual = evaluateReadingAnswerInner(normalizedInput: normalizedInput)
        var outcome: TestOutcome = qual > 0 ? .right : .wrong
        let alternatives = readingAlternatives(reading: normalizedInput)
        if outcome == .wrong && allowAlternatives && alternatives.contains(where: { (alternative: Item) in
            (alternative as! NormalItem).meanings.contains(where: { (meaning: Ing) in
                meaning.acceptedAnswerForMe && self.meanings.contains(where: { (meaning2: Ing) in
                    meaning2.acceptedAnswerForMe && meaning.text == meaning2.text
                })
            })
        }) {
            outcome = .mu
        }
        return (outcome, qual, alternatives)

    }
    func evaluateMeaningAnswer(input: String, allowAlternatives: Bool) -> (outcome: TestOutcome, qual: Int, alternatives: [Item]) {
        let normalizedInput = normalizeMeaningTrimmed(trim(input))
        var levenshtein = Levenshtein()
        let qual = evaluateMeaningAnswerInner(normalizedInput: normalizedInput, levenshtein: &levenshtein)
        var outcome: TestOutcome = qual > 0 ? .right : .wrong
        let alternatives = meaningAlternatives(meaning: normalizedInput)
        if outcome == .wrong && allowAlternatives && alternatives.contains(where: { (alternative: Item) in
            (alternative as! NormalItem).readings.contains(where: { (reading: Ing) in
                reading.acceptedAnswerForMe && self.readings.contains(where: { (reading2: Ing) in
                    reading2.acceptedAnswerForMe && reading.text == reading2.text
                })
            })
        }) {
            outcome = .mu
        }
        return (outcome, qual, alternatives)
    }
    func cliIngs(ings: [Ing], colorful: Bool) -> String {
        var prev: Ing? = nil
        var out: String = ""
        for ing in (ings.sorted { $0.type < $1.type }) {
            if ing.type != .whitelist {
                let separator = prev == nil ? "" :
                                prev!.type == ing.type ? ", " :
                                " >> "
                var colored = ing.text
                if colorful { colored = (ing.type == .primary ? ANSI.red : ANSI.dred)(colored) }
                out += separator + colored
            }
            prev = ing
        }
        return out
    }
    func cliReadings(colorful: Bool) -> String {
        return self.cliIngs(ings: self.readings, colorful: colorful)
    }
    func cliMeanings(colorful: Bool) -> String {
        return self.cliIngs(ings: self.meanings, colorful: false) // yes, ignore colorful for now
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
    override var availableTests: [TestKind] { return [.characterToRM, .meaningToReading, .readingToMeaning] }
    var cliName: String {
        fatalError("must override cliName on \(self)")
    }
}
class Word : NormalItem, CustomStringConvertible {
    var description: String {
        return "<Word \(self.character)>"
    }
    override var kind: ItemKind { return .word }
    override var cliName: String { return String(self.name) }
}
class Kanji : NormalItem, CustomStringConvertible {
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
        let bits = trim(line).split(separator: " ")
        if bits.count > 3 { fatalError("too many spaces in '\(line)'") }
        var bitsIdx = 0
        var nameOpt: String?
        if bits.count == 3 {
            let name = String(bits[0])
            if !name.starts(with: "@") {
                fatalError("explicit name should start with @ in '\(line)'")
            }
            nameOpt = name
            bitsIdx = 1
        }
        let spec = bits[bitsIdx]
        let characters: [String]
        if isWord {
            characters = spec.split(separator: "/").map { trim($0) }
            allXs = Subete.instance.allWords
        } else {
            characters = spec.map { String($0) }
            allXs = Subete.instance.allKanji
        }
        var birthday: Date? = nil
        if bits.count > bitsIdx + 1 {
            birthday = myDateFormatter.date(from: String(bits[bitsIdx + 1]))
        }
        self.items = characters.map {
            let item = allXs.findByName($0)
            if item == nil { fatalError("invalid item '\($0)' in confusion") }
            return item!
        }
        self.isWord = isWord
        let name = nameOpt ?? characters[0]
        self.characters = characters
        super.init(name: name, birthday: birthday)
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
                    byReading[reading.text] = (byReading[reading.text] ?? []) + [item]
                }
                for meaning in normalItem.meanings {
                    byMeaning[meaning.text] = (byMeaning[meaning.text] ?? []) + [item]
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
    var questions: [Question] {
        return items.flatMap { $0.myQuestions }
    }
}

enum TestKind: String, ExpressibleByArgument, Codable {
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
            if i == end || utf[i] == separator {
                var lastEnd = i
                if includingSpaces {
                    while true {
                        if lastEnd == lastStart { break }
                        let prev = utf.index(before: lastEnd)
                        if !isSpace(utf[prev]) { break }
                        lastEnd = prev
                    }
                    if i != end {
                        while true {
                            let next = utf.index(after: i)
                            if next == end { break }
                            if !isSpace(utf[next]) { break }
                            i = next
                        }
                    }
                }
                res.append(map(String(utf[lastStart..<lastEnd])!))
                if i == end { return res }
                lastStart = utf.index(after: i)
            }
            i = utf.index(after: i)
        }
        return res
    }
    
}
struct TestResult {
    let question: Question
    let date: Date?
    let outcome: TestOutcome
    func getRecordLine() -> String {
        let components: [String] = [
            String(Int(Date().timeIntervalSince1970)),
            self.question.testKind.rawValue,
            self.question.item.kind.rawValue,
            self.question.item.name,
            self.outcome.rawValue
        ]
        return components.joined(separator: ":")
    }
    static let retiredInfo: NSDictionary = loadYAML(path: "\(Subete.instance.basePath)/retired.yaml") as! NSDictionary
    static let retired: [ItemKind: Set<String>] = Dictionary(uniqueKeysWithValues:
        (retiredInfo["retired"] as! [String: [String]]).map {
            (ItemKind(rawValue: $0.key)!, Set($0.value))
        })
    static let replace: [ItemKind: [String: String]] = Dictionary(uniqueKeysWithValues:
        (retiredInfo["replace"] as! [String: [String: String]]).map {
            (ItemKind(rawValue: $0.key)!, $0.value)
        })
    static func parse(line: String) throws -> TestResult? {
        var components: [String] = line.splut(separator: 58 /* ':' */, includingSpaces: true, map: { $0 })
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
        if retired[itemKind]?.contains(name) == .some(true) {
            return nil
        } else if let newName = replace[itemKind]?[name] {
            name = newName
        }

        let question = Question(
            item: try unwrapOrThrow(Subete.instance.allByKind(itemKind).findByName(name),
                                err: MyError("no such item kind \(components[1]) name \(name)")),
            testKind: try unwrapOrThrow(TestKind(rawValue: String(components[0])),
                                    err: MyError("invalid test kind \(components[0])"))
        )
        return TestResult(
            question: question,
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
    let question: Question
    let testSession: TestSession
    var result: TestResult? = nil
    var appendedStuff: Data? = nil
    var didCliRead: Bool = false
    init(question: Question, testSession: TestSession) {
        self.question = question
        self.testSession = testSession
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
        let item = self.question.item
        switch self.question.testKind {
        case .meaningToReading:
            try self.doCLIMeaningToReading(item: item as! NormalItem)
        case .readingToMeaning:
            try self.doCLIReadingToMeaning(item: item as! NormalItem)
        case .characterToRM:
            try self.doCLICharacterToRM(item: item as! NormalItem, final: true)
        case .confusion:
            try self.doCLIConfusion(item: item as! Confusion)
        }
        if self.result == nil { fatalError("should have marked result") }
    }
    func cliLabel(outcome: TestOutcome, qual: Int, srsUpdate: SRSUpdate) -> String {
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
        return back(text) + srsUpdate.cliLabel
    }

    func doCLIMeaningToReading(item: NormalItem) throws {
        var prompt = item.cliMeanings(colorful: false)
        prompt = item.tildify(prompt)
        if item is Kanji {
            prompt = ANSI.purple(prompt) + " /k"
        }
        while true {
            let k = try cliRead(prompt: prompt, kana: true)
            let (outcome, qual, alternatives) = item.evaluateReadingAnswer(input: k, allowAlternatives: true)
            let srsUpdate = try self.maybeMarkResult(outcome: outcome, final: true)
            var out: String = cliLabel(outcome: outcome, qual: qual, srsUpdate: srsUpdate)
            out += " " + item.cliName + " " + item.cliReadings(colorful: false)
            print(out)
            item.cliPrintAlternatives(alternatives, isReading: true)
            item.cliPrintSimilarMeaning()
        
            if outcome == .right { break }
        }
    }
    func doCLIReadingToMeaning(item: NormalItem) throws {
        var prompt = item.cliReadings(colorful: false)
        prompt = item.tildify(prompt)
        if item is Kanji {
            prompt += " /k"
        }
        while true {
            let k: String = try cliRead(prompt: prompt, kana: false)
            let (outcome, qual, alternatives) = item.evaluateMeaningAnswer(input: k, allowAlternatives: true)
            let srsUpdate = try self.maybeMarkResult(outcome: outcome, final: true)
            print(cliLabel(outcome: outcome, qual: qual, srsUpdate: srsUpdate))
            item.cliPrint(colorful: true)
            item.cliPrintAlternatives(alternatives, isReading: false)
            //if outcome != .right {
                item.cliPrintSameReadingIfFew()
            //}
            if outcome == .right {
                break
            }
        }
    }
    func doCLICharacterToRM(item: NormalItem, final: Bool) throws {
        let prompt = item.cliName
        enum Mode { case reading, meaning }
        for (modeIdx, mode) in [Mode.reading, Mode.meaning].shuffled().enumerated() {
            while true {
                let k: String = try cliRead(prompt: prompt, kana: mode == .reading)
                let outcome: TestOutcome
                let qual: Int
                let alternatives: [Item]
                if mode == .meaning {
                    (outcome, qual, alternatives) = item.evaluateMeaningAnswer(input: k, allowAlternatives: false)
                    let srsUpdate = try self.maybeMarkResult(outcome: outcome, final: final && modeIdx == 1)
                    print(cliLabel(outcome: outcome, qual: qual, srsUpdate: srsUpdate))
                    print(item.cliMeanings(colorful: true))
                    // Only print alternatives if wrong, to avoid spoilers both
                    // for later in the c2 and later in a confusion this might
                    // be part of
                    if outcome == .wrong {
                        item.cliPrintAlternatives(alternatives, isReading: false)
                    }
                } else {
                    (outcome, qual, alternatives) = item.evaluateReadingAnswer(input: k, allowAlternatives: false)
                    let srsUpdate = try self.maybeMarkResult(outcome: outcome, final: final && modeIdx == 1)
                    print(cliLabel(outcome: outcome, qual: qual, srsUpdate: srsUpdate))
                    print(item.cliReadings(colorful: true))
                    if outcome == .wrong { // See above
                        item.cliPrintAlternatives(alternatives, isReading: true)
                    }
                }
                if outcome == .right { break }
            }
        }
    }
    func doCLIConfusion(item: Confusion) throws {
        let items = item.items.shuffled()
        for (i, subitem) in items.enumerated() {
            try doCLICharacterToRM(item: subitem as! NormalItem, final: i == items.count - 1)
        }
    }
    static let readingPrompt: String = ANSI.red("reading> ")
    static let meaningPrompt: String = ANSI.blue("meaning> ")

    func cliRead(prompt: String, kana: Bool) throws -> String {
        self.testSession.save()
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
    func maybeMarkResult(outcome: TestOutcome, final: Bool) throws -> SRSUpdate {
        if outcome == .wrong || (self.result == nil && final) {
            return try self.markResult(outcome: outcome)
        } else {
            return .noChangeOther
        }
    }
    func markResult(outcome: TestOutcome?) throws -> SRSUpdate {
        self.testSession.setQuestionCompleteness(question: self.question, complete: outcome == .some(.right))

        if self.result != nil {
            try self.removeFromLog()
            Subete.instance.srs?.revert(forQuestion: self.question)
        }
        if let outcome = outcome {
            self.result = TestResult(question: self.question, date: Date(), outcome: outcome)
            try self.addToLog()
            return Subete.instance.srs!.update(forResult: self.result!)
        } else {
            self.result = nil
            return .noChangeOther
        }
    }
}

enum SRSUpdate {
    case nextDays(Double)
    case burned
    case lockedOut
    case noChangeOther
    case anachronism // ignore update before birthday (which I can use to force an item to be re-tested)
    
    var isNoChangeOther: Bool {
        if case .noChangeOther = self {
            return true
        } else {
            return false
        }
    }
    var cliLabel: String {
        switch self {
            case .nextDays(let days):
                return String(format: " +%.1fd", days)
            case .burned:
                return " 🔥"
            case .lockedOut:
                return " ⟳"
            case .noChangeOther:
                return ""
            case .anachronism:
                return " [anachronism]"
        }
    }
}

class SRS {
    enum ItemInfo {
        case active((lastSeen: Date, points: Double, urgentRetest: Bool))
        case burned

        var nextTestDays: Double? {
            switch self {
                case .active(let info):
                    if info.urgentRetest || info.points == 0 {
                        return 0.5
                    } else {
                        return pow(2.5, log2(info.points + 0.5))
                    }
                case .burned:
                    return nil
            }
        }
        var nextTestDate: Date? {
            //print("points=\(self.points) nextTestDays=\(self.nextTestDays)")
            switch self {
                case let .active(info):
                    return info.lastSeen + self.nextTestDays! * 60 * 60 * 24
                case .burned:
                    return nil
            }
        }
        var timePastDue: TimeInterval? {
            guard let next = self.nextTestDate else { return nil }
            let now = Date()
            return now >= next ? now.timeIntervalSince(next) : nil
        }
        mutating func updateIfStale(date: Date) {
            if case let .active(info) = self {
                if date.timeIntervalSince(info.lastSeen) > 60 * 60 * 24 * 60 {
                    //print("staling \(self)")
                    self = .burned
                }
            }
        }
        mutating func update(forResult result: TestResult) -> SRSUpdate {
            let date = result.date ?? Date(timeIntervalSince1970: 0)

            if let birthday = result.question.item.birthday, date < birthday {
                return .anachronism
            }
            self.updateIfStale(date: date)
            //print("updating \(String(describing: self)) for result \(result) at date \(date) birthday=\(String(describing: result.question.item.birthday))")
            
            switch self {
                case .active(var info):
                    let sinceLast = date.timeIntervalSince(info.lastSeen)
                    info.lastSeen = date
                    //print("sinceLast=\(sinceLast)")
                    var update: SRSUpdate? = nil
                    if sinceLast < 60*60*6 {
                        update = .lockedOut
                    } else {
                        switch result.outcome {
                        case .mu:
                            update = .noChangeOther
                        case .right:
                            info.points += max(sinceLast / (60*60*24), 1.0)
                            info.urgentRetest = false
                            if info.points >= 60 {
                                update = .burned
                            }
                        case .wrong:
                            info.points /= 2
                            info.urgentRetest = true
                        }
                    }
                    //print("outcome=\(result.outcome) newInfo.points = \(newInfo.points)")
                    self = .active(info)
                    return update ?? .nextDays(self.nextTestDays!)
                case .burned:
                    if result.outcome == .wrong {
                        self = .active((lastSeen: date, points: 0, urgentRetest: false))
                        return .nextDays(self.nextTestDays!)
                    }
                    return .noChangeOther
            }
        }

    }
    private var itemInfo: [Question: ItemInfo] = [:]
    private var backup: (Question, ItemInfo?)? = nil
    func update(forResult result: TestResult) -> SRSUpdate {
        var info = self.info(question: result.question)
        self.backup = (result.question, info)
        let srsUpdate = info.update(forResult: result)
        itemInfo[result.question] = info
        return srsUpdate
    }
    func updateStales(date: Date) {
        for (item, var info) in itemInfo {
            info.updateIfStale(date: date)
            itemInfo[item] = info
        }
    }
    func revert(forQuestion question: Question) {
        let backup = self.backup!
        ensure(backup.0 == question)
        self.itemInfo[backup.0] = backup.1
        self.backup = nil
    }
    func info(question: Question) -> ItemInfo {
        if let info = self.itemInfo[question] {
            return info
        }
        let info = self.defaultInfo(question: question)
        self.itemInfo[question] = info
        return info
    }
    private func defaultInfo(question: Question) -> ItemInfo {
        if let birthday = question.item.birthday {
            return .active((lastSeen: min(birthday, startupDate), points: 0, urgentRetest: false))
        } else {
            return .burned
        }
    }
}

func testSRS() {
    let item = Item(name: "test", birthday: nil)
    let question = Question(item: item, testKind: .confusion)
    var info: SRS.ItemInfo = .burned
    let _ = info.update(
        forResult: TestResult(question: question,
                              date: Date(timeIntervalSince1970: 0),
                              outcome: .wrong))
    for i in 0... {
        let srsUpdate = info.update(
            forResult: TestResult(question: question,
                                  date: info.nextTestDate,
                                  outcome: .right))
        print("\(i). \(info)\(srsUpdate.cliLabel)")
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
    init(_ values: [(T, Double)]) {
        for (value, weight) in values {
            self.add(value, weight: weight)
        }
    }

    var totalWeight: Double {
        return entries.last?.cumulativeWeight ?? 0
    }
    var isEmpty: Bool { return entries.isEmpty }
    
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

enum RandomMode: String, CaseIterable, ExpressibleByArgument, Codable {
    case all
    case confusion
}

struct ForecastCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forecast")
    func run() {
        let _ = Subete()
        let srs = Subete.instance.srs!
        let now = Date()
        let srsItems: [(nextTestDate: Date, question: Question)] = Subete.instance.allQuestions.compactMap { (question) in
            guard let nextTestDate = srs.info(question: question).nextTestDate else { return nil }
            return (nextTestDate: nextTestDate, question: question)
        }
        let maxDays = 20
        let secondsPerDay: Double = 60 * 60 * 24
        let byDay: [(key: Int, value: [(nextTestDate: Date, question: Question)])] =
            Dictionary(grouping: srsItems, by: { (val: (nextTestDate: Date, question: Question)) -> Int in
                min(maxDays, max(0, Int(ceil(val.nextTestDate.timeIntervalSince(now) / secondsPerDay))))
            }).sorted { $0.key < $1.key }
        var total = 0
        for (days, items) in byDay {
            let keyStr = days == maxDays ? "later" : String(days)
            print("\(keyStr): \(items.count)")
            total += items.count
        }
        print(" * total: \(total)")
    }
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

struct TestOneCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-one")
    @Argument()
    var testKind: TestKind
    @Argument()
    var itemKind: ItemKind
    @Argument()
    var name: String
    func run() {
        runOrExit { try runImpl() }
    }
    func runImpl() throws {
        let _ = Subete()
        let item = try unwrapOrThrow(Subete.instance.allByKind(itemKind).findByName(name),
                                     err: MyError("no such item kind \(itemKind) name \(name)"))
        let question = Question(item: item, testKind: testKind)
        let testSession = TestSession(base: SerializableTestSession(
            pulledCompleteQuestions: IndexableSet([question]),
            randomMode: .all
        ))
        let test = Test(question: question, testSession: testSession)
        try test.cliGo()
    }
}

struct ItemRef: Codable, Hashable, Equatable {
    let item: Item
    enum CodingKeys: String, CodingKey {
        case kind
        case name
    }

    init(_ item: Item) {
        self.item = item
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ItemKind.self, forKey: .kind)
        let name = try container.decode(String.self, forKey: .name)
        item = try unwrapOrThrow(Subete.instance.allByKind(kind).findByName(name),
                                 err: MyError("no such item kind \(kind) name \(name)"))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(item.kind, forKey: .kind)
        try container.encode(item.name, forKey: .name)
    }
}

struct IndexableSet<Element>: Codable, Sequence where Element: Hashable & Equatable & Codable {
    typealias Iterator = Array<Element>.Iterator
    typealias Element = Element
    var values: [Element]
    var valueToIndex: [Element: Int]
    init() {
        self.values = []
        self.valueToIndex = [:]
    }
    init<S>(_ sequence: S) where S : Sequence, S.Element == Element {
        self.init()
        for value in sequence {
            self.update(with: value)
        }
    }
    init(from decoder: Decoder) throws {
        self.values = try Array(from: decoder)
        self.valueToIndex = [:]
        for (i, value) in self.values.enumerated() {
            if let _ = self.valueToIndex[value] {
                throw MyError("duplicate element \(value)")
            }
            self.valueToIndex[value] = i
        }
    }
    func encode(to encoder: Encoder) throws {
        try self.values.encode(to: encoder)
    }
    func makeIterator() -> Self.Iterator {
        return self.values.makeIterator()
    }
    @discardableResult mutating func update(with newMember: Element) -> Element? {
        if let index = self.valueToIndex[newMember] {
            let old = self.values[index]
            self.values[index] = newMember
            return old
        } else {
            let index = self.values.count
            self.values.append(newMember)
            self.valueToIndex[newMember] = index
            return nil
        }
    }
    @discardableResult mutating func remove(_ member: Element) -> Element? {
        if let index = self.valueToIndex[member] {
            let old = self.values[index]
            self.valueToIndex[old] = nil
            let lastIndex = self.values.count - 1
            let last = self.values.removeLast()
            if lastIndex != index {
                self.values[index] = last
                self.valueToIndex[last] = index
            }
            return old
        } else {
            return nil
        }
    }
    var count: Int {
        self.values.count
    }
    subscript(index: Int) -> Element {
        get {
            return self.values[index]
        }
    }
}

struct SerializableTestSession: Codable {
    var pulledIncompleteQuestions: IndexableSet<Question> = IndexableSet()
    var pulledCompleteQuestions: IndexableSet<Question> = IndexableSet()
    var numCompletedQuestions: Int = 0 // first n elements of pulledQuestions are completed
    var numUnpulledRandomQuestions: Int = 0
    var numDone: Int = 0
    let randomMode: RandomMode

    func serialize() -> Data {
        return try! JSONEncoder().encode(self)
    }
    static func deserialize(_ data: Data) throws -> SerializableTestSession {
        return try JSONDecoder().decode(SerializableTestSession.self, from: data)
    }
}

struct BenchSTS: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bench-sts")
    @Flag() var deser: Bool = false
    func run() {
        let _ = Subete()
        let sts = SerializableTestSession(
            pulledIncompleteQuestions: IndexableSet(Subete.instance.allQuestions[..<500]),
            randomMode: .all
        )
        if self.deser {
            let serialized: Data = sts.serialize()
            time(count: 1000) {
                return try! SerializableTestSession.deserialize(serialized)
            }
        } else {
            time(count: 1000) {
                return sts.serialize()
            }
        }
    }
}


class TestSession {
    var base: SerializableTestSession
    var lottery: WeightedList<Question>
    var pulledQuestionToIndex: [Question: Int] = [:]
    var saveURL: URL? = nil
    init(base: SerializableTestSession, saveURL: URL? = nil) {
        self.base = base
        self.saveURL = saveURL
        self.lottery = TestSession.makeLottery(randomMode: base.randomMode,
                                               excluding: Set(base.pulledCompleteQuestions).union(Set(base.pulledIncompleteQuestions)))
    }
    convenience init(fromSaveURL url: URL) throws {
        let data = try Data(contentsOf: url)
        self.init(
            base: try SerializableTestSession.deserialize(data),
            saveURL: url
        )
    }
    static func makeLottery(randomMode: RandomMode, excluding excl: Set<Question>) -> WeightedList<Question> {
        var availRandomQuestions: [(question: Question, weight: Double)] = []
        switch randomMode {
            case .all:
                availRandomQuestions += (Subete.instance.allWords.questions + Subete.instance.allKanji.questions).map {
                    (question: $0, weight: 1.0)
                }
                availRandomQuestions += Subete.instance.allConfusion.questions.map {
                    (question: $0, weight: 10.0)
                }
            case .confusion:
                availRandomQuestions += Subete.instance.allConfusion.questions.map {
                    (question: $0, weight: 1.0)
                }
        }
        let filteredRandomQuestions = availRandomQuestions.filter { !excl.contains($0.question) }
        return WeightedList(filteredRandomQuestions)
    }

    func randomQuestion() -> Question? {
        let numPulled = self.base.pulledIncompleteQuestions.count,
            numUnpulled = self.base.numUnpulledRandomQuestions
        if numPulled + numUnpulled == 0 {
            return nil
        }
        let rawIndex = Int.random(in: 0..<(numPulled + numUnpulled))
        if rawIndex < numPulled {
            return self.base.pulledIncompleteQuestions[rawIndex]
        } else {
            let question = self.lottery.takeRandomElement()!
            self.base.numUnpulledRandomQuestions -= 1
            self.base.pulledIncompleteQuestions.update(with: question)
            return question
        }
    }

    func numRemainingQuestions() -> Int {
        self.base.pulledIncompleteQuestions.count + self.base.numUnpulledRandomQuestions
    }
    func numCompleteQuestions() -> Int {
        self.base.pulledCompleteQuestions.count
    }


    func setQuestionCompleteness(question: Question, complete: Bool) {
        if complete {
            self.base.pulledIncompleteQuestions.remove(question)
            self.base.pulledCompleteQuestions.update(with: question)
        } else {
            self.base.pulledCompleteQuestions.remove(question)
            self.base.pulledIncompleteQuestions.update(with: question)
        }
    }

    func cliGoOne() throws -> Bool {
        guard let question = self.randomQuestion() else {
            return false
        }
        print("[\(self.base.numDone) | \(self.numRemainingQuestions())]")
        //let testKind = item.availableTests.randomElement()!
        let test = Test(question: question, testSession: self)
        try test.cliGo()
        self.base.numDone += 1
        return true
    }

    func save() {
        guard let saveURL = self.saveURL else { return }
        do {
            try self.base.serialize().write(to: saveURL)
        } catch let e {
            print("!Failed to save! \(e)")
        }
    }
    func trashSave() {
        guard let saveURL = self.saveURL else { return }
        do {
            try FileManager.default.trashItem(at: saveURL, resultingItemURL: nil)
        } catch let e {
            print("!Failed to trash save! \(e)")
        }
    }
}

struct Rerere: ParsableCommand {
    @Option() var minQuestions: Int?
    @Option() var maxQuestions: Int?
    @Option() var minRandomQuestionsFraction: Double = 0.33
    @Option() var randomMode: RandomMode = .all

    static let configuration = CommandConfiguration(
            //abstract: "Randomness utilities.",
            subcommands: [ForecastCommand.self, TestOneCommand.self, BenchSTS.self])

    func validate() throws {
        guard minRandomQuestionsFraction >= 0 && minRandomQuestionsFraction <= 1 else {
            throw ValidationError("min-random-questions-fraction should be in [0,1]")
        }
        guard minQuestions == nil || maxQuestions == nil || minQuestions! < maxQuestions! else {
            throw ValidationError("min-questions should < max-questions")
        }
    }
    func resolveMinMax() -> (minQuestions: Int, maxQuestions: Int) {
        let defaultMinQuestions = 50
        let defaultMaxQuestions = 75
        switch (self.minQuestions, self.maxQuestions) {
            case (nil, nil):
                return (minQuestions: defaultMinQuestions, maxQuestions: defaultMaxQuestions)
            case (.some(let _minQuestions), nil):
                return (minQuestions: _minQuestions, maxQuestions: max(defaultMaxQuestions, _minQuestions))
            case (nil, .some(let _maxQuestions)):
                return (minQuestions: min(defaultMinQuestions, _maxQuestions), maxQuestions: _maxQuestions)
            case (.some(let _minQuestions), .some(let _maxQuestions)):
                return (minQuestions: _minQuestions, maxQuestions: _maxQuestions)
        }
    }
    func gatherSRSQuestions() -> [(nextTestDate: Date, question: Question)] {
        let now = Date()
        let srs = Subete.instance.srs!
        return Subete.instance.allQuestions.compactMap { (question) in
            guard let nextTestDate = srs.info(question: question).nextTestDate else { return nil }
            return nextTestDate <= now ? (nextTestDate: nextTestDate, question: question) : nil
        }
    }
    func calcQuestionSplit(minQuestions: Int, maxQuestions: Int, availSRSQuestions: Int) -> (numSRSQuestions: Int, numRandomQuestions: Int) {
        if self.minRandomQuestionsFraction >= 1.0 {
            return (numSRSQuestions: 0, numRandomQuestions: minQuestions)
        } else {
            var numQuestionsX: Double = Double(availSRSQuestions) / (1.0 - self.minRandomQuestionsFraction)
            numQuestionsX = max(numQuestionsX, Double(minQuestions))
            numQuestionsX = min(numQuestionsX, Double(maxQuestions))
            let numQuestions = Int(numQuestionsX)
            let numSRSQuestions = min(availSRSQuestions, Int(numQuestionsX * (1.0 - self.minRandomQuestionsFraction)))
            return (
                numSRSQuestions: numSRSQuestions,
                numRandomQuestions: numQuestions - numSRSQuestions
            )
        }
    }
    func makeSerializableSession() -> SerializableTestSession {
        let (minQuestions, maxQuestions) = resolveMinMax()
        var srsQuestions = gatherSRSQuestions()
        let (numSRSQuestions, numRandomQuestions) = calcQuestionSplit(minQuestions: minQuestions, maxQuestions: maxQuestions, availSRSQuestions: srsQuestions.count)
        print("got \(srsQuestions.count) SRS questions")
        if numSRSQuestions < srsQuestions.count {
            print("...but limiting to \(numSRSQuestions)")
            srsQuestions.sort { $0.nextTestDate > $1.nextTestDate}
            srsQuestions = Array(srsQuestions[0..<numSRSQuestions])
        }
        return SerializableTestSession(
            pulledIncompleteQuestions: IndexableSet(srsQuestions.map { $0.question }),
            numUnpulledRandomQuestions: numRandomQuestions,
            randomMode: randomMode
        )
    }

    func run() throws {
        let _ = Subete()
        let path = "\(Subete.instance.basePath)/sess.json"
        let url = URL(fileURLWithPath: path)
        let sess: TestSession
        do {
            sess = try TestSession(fromSaveURL: url)
            print("Loaded existing session \(path)")
        } catch let e as NSError where e.domain == NSCocoaErrorDomain &&
                                       e.code == NSFileReadNoSuchFileError {
            print("Starting new session \(path)")
            let ser = makeSerializableSession()
            sess = TestSession(base: ser, saveURL: url)
        }
        runOrExit {
            sess.save()
            while try sess.cliGoOne() {}
            sess.trashSave()
        }
    }
}
Levenshtein.test()
//print("   :xsamdfa: b  :  c:   ".splut(separator: 58, includingSpaces: true, map: { $0 }))
Rerere.main()
