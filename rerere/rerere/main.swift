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
import rerere_c
import Foundation
import Yams
import ArgumentParser
import XCTest
import System

// TODO: ~ is broken for r2m
// TODO: !wrong doesn't act as expected when halfway through a k2rm
// TODO: don't let you mu more than once

func data(of path: String) throws -> Data {
    return try Data(contentsOf: URL(fileURLWithPath: path))
}

@discardableResult
func time<T>(count: Int, block: () -> T) -> T {
    let a = CFAbsoluteTimeGetCurrent()
    var t: T?
    for _ in 0..<count {
		t = block()
		blackBox(t)
    }
    let b = CFAbsoluteTimeGetCurrent()
    print((b - a) / Double(count))
    return t!
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
func d2s(_ d: Data) -> String {
	String(data: d, encoding: .utf8)!
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
    let yamlData = try! data(of: "\(basePath)/extra-\(stem).yaml")
    let extra = try! YAMLDecoder().decode([T].self, from: yamlData,
                                          userInfo: [CodingUserInfoKey(rawValue: "relaxed")!: true])
    return base + extra
}

func loadFlashcardYAML(basePath: String) -> [Flashcard] {
    let yamlData = try! data(of: "\(basePath)/flashcards.yaml")
    return try! YAMLDecoder().decode([Flashcard].self, from: yamlData)
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
    nonisolated(unsafe) var output: Data? = nil
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
    var path = FilePath(#filePath).removingLastComponent()
    print(">>", path)
    while !(FileManager.default.fileExists(atPath: path.pushing("kanji.json").string)) {
        path.push("..")
        if path.length > 512 {
            fatalError("failed to find wk directory")
        }
    }

    return try! URL(fileURLWithPath: path.string).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath!
}

class Subete {
    nonisolated(unsafe) static var instance: Subete!
    var allWords: ItemList<Word>! = nil
    var allKanji: ItemList<Kanji>! = nil
    var allConfusion: ItemList<Confusion>! = nil
    var allFlashcards: ItemList<Flashcard>! = nil
    var allItems: [Item]! = nil
    var srs: SRS? = nil
    var studyMaterials: [Int: StudyMaterial]! = nil

    var retired: [ItemKind: Set<String>]!
    var replace: [ItemKind: [String: String]]!
    
    var lastAppendedTest: Test?
    
    let basePath = getWkDir()

    var nextItemID = 0

    init() {
        Subete.instance = self

        let retiredInfo: RetiredYaml = try! YAMLDecoder().decode(RetiredYaml.self, from: data(of: "\(basePath)/retired.yaml"))
        retired = retiredInfo.retired.mapValues { Set($0) }
        replace = retiredInfo.replace

        print("loading json")
        self.studyMaterials = loadStudyMaterials(basePath: basePath)
        self.allWords = ItemList(loadJSONAndExtraYAML(basePath: basePath, stem: "vocabulary", class: Word.self))
        self.allKanji = ItemList(loadJSONAndExtraYAML(basePath: basePath, stem: "kanji", class: Kanji.self))
        self.allFlashcards = ItemList(loadFlashcardYAML(basePath: basePath))
        print("loading confusion")
        let allKanjiConfusion = loadConfusion(path: basePath + "/confusion.txt", isWord: false)
        let allWordConfusion = loadConfusion(path: basePath + "/confusion-vocab.txt", isWord: true)
        self.allConfusion = ItemList(allKanjiConfusion + allWordConfusion)
        self.allItems = self.allWords.items + self.allKanji.items + self.allConfusion.items
        print("loading srs")
		self.srs = time(count: 2000) { self.createSRSFromLog() }
        print("done loading")

    }
    func allByKind(_ kind: ItemKind) -> ItemListProtocol {
        switch kind {
        case .word: return self.allWords
        case .kanji: return self.allKanji
        case .confusion: return self.allConfusion
        case .flashcard: return self.allFlashcards
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
	
func initWithRawValueData<T: CodingKeyRepresentable>(data: Data, type: T.Type) -> T? {
	static let map: [Data: T] = {
		var m: [Data: T] = [:]
		return m
	}()
	return map[data]
}

enum ItemKind: String, ExpressibleByArgument, Codable, CodingKeyRepresentable, InitWithRawValueData {
    case word, kanji, confusion, flashcard
}

class Item: Hashable, Equatable, Comparable {
    let name: String
    let birthday: Date?
    let id: Int

    // ItemInitializer is a workaround for convenience inits not interacting
    // well with subclassing
    typealias ItemInitializer = (name: String, birthday: Date?)
    init(_ initializer: ItemInitializer) {
        self.name = initializer.name
        self.birthday = initializer.birthday
        self.id = Subete.instance.nextItemID
        Subete.instance.nextItemID = self.id + 1
    }
    static func initializer(name: String, from dec: any Decoder) throws -> ItemInitializer {
        enum K: CodingKey { case birth }
        let container = try dec.container(keyedBy: K.self)
        // I can't delegate to the other init because that requires being a
        // convenience init, yet convenience inits are inherited so they can't
        // be called from the subclass??
        return (name: name, birthday: try container.decodeIfPresent(Date.self, forKey: .birth))
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

    // this is separate in case I want to make Question more than just
    // (Item, TestKind) in the future
    var myQuestions: [Question] {
        return availableTests.map { Question(item: self, testKind: $0) }
    }

    func meaningAlternatives(meaning: String) -> [Item] {
        let normalizedMeaning = normalizeMeaningTrimmed(trim(meaning))
        /*
        var levenshtein = Levenshtein()
        return Subete.instance.allByKind(Self.kind).vagueItems.filter { (other: Item) -> Bool in
            return other != self && (other as! NormalItem).meaningMatches(normalizedInput: normalizedMeaning, levenshtein: &levenshtein)
        }
        */
        let ret = Subete.instance.allByKind(Self.kind).findByMeaning(normalizedMeaning).filter { $0 != self }
        return ret
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
    while !dec.isAtEnd {
        // hack
        ret.append(try callback(dec.superDecoder()))
    }
    return ret
}

// without alternatives, without normalization, just return qual
func evaluateMeaningAnswerInner(normalizedInput: String, meanings: [Ing], levenshtein: inout Levenshtein) -> Int {
    var bestQual: Int = 0
    for meaning in meanings {
        let text = meaning.text
        let okDist = Int(round(0.4 * Double(text.count)))
        let thisQual: Int
        if normalizedInput == text {
            thisQual = 2
        } else if levenshtein.distance(between: normalizedInput, and: text) <= okDist {
            thisQual = 1
        } else {
            continue
        }
        bestQual = max(bestQual, thisQual)
    }
    return bestQual
}

// TODO: CLI class
func cliIngs(ings: [Ing], colorful: Bool, tildify: (String) -> String) -> String {
    var prev: Ing? = nil
    var out: String = ""
    for ing in (ings.sorted { $0.type < $1.type }) {
        if ing.type != .whitelist && ing.type != .blacklist {
            let separator = prev == nil ? "" :
                            prev!.type == ing.type ? ", " :
                            " >> "
            var colored = ing.text
            if colorful { colored = (ing.type == .primary ? ANSI.red : ANSI.dred)(colored) }
            colored = tildify(colored)
            out += separator + colored
        }
        prev = ing
    }
    return out
}

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
        var dataDec: any Decoder
        let wkId: Int?
        if topC.contains(.data) {
            wkId = try topC.decode(Int.self, forKey: .id)
            dataDec = try topC.superDecoder(forKey: .data)
        } else {
            if !relaxed { fatalError("expected 'data'") }
            dataDec = dec
            wkId = nil
        }
        let dataC = try dataDec.container(keyedBy: K.self)

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
        if let wkId, let material = Subete.instance.studyMaterials[wkId] {
            meanings += material.meaningSynonyms.map { Ing(synonymWithText: $0) }
        }
        self.meanings = meanings
        super.init(try Item.initializer(name: self.character, from: dataDec))
    }
    func readingAlternatives(reading: String) -> [Item] {
        let normalizedReading = normalizeReadingTrimmed(trim(reading))
        return Subete.instance.allByKind(Self.kind).findByReading(normalizedReading).filter { $0 != self }
    }
    func meaningMatches(normalizedInput: String, levenshtein: inout Levenshtein) -> Bool {
        return evaluateMeaningAnswerInner(normalizedInput: normalizedInput,
                                          meanings: self.meanings,
                                          levenshtein: &levenshtein) > 0
    }
    func similarMeaning() -> [Item] {
        var set: Set<Item> = []
        for meaning in self.meanings {
            set.formUnion(Subete.instance.allByKind(Self.kind).findByMeaning(meaning.text))
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
            set.formUnion(Subete.instance.allByKind(Self.kind).findByReading(reading.text))
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
        let qual = evaluateMeaningAnswerInner(normalizedInput: normalizedInput,
                                              meanings: self.meanings,
                                              levenshtein: &levenshtein)
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
    func cliReadings(colorful: Bool) -> String {
        return cliIngs(ings: self.readings, colorful: colorful, tildify: self.tildify)
    }
    func cliMeanings(colorful: Bool) -> String {
        // yes, ignore colorful for now
        return cliIngs(ings: self.meanings, colorful: false, tildify: self.tildify)
    }
    override func cliPrint(colorful: Bool) {
        print("\(self.cliName) \(self.cliReadings(colorful: colorful)) \(self.cliMeanings(colorful: colorful))")
    }
    func tildify(_ prompt: String) -> String {
        if self.character.starts(with: "〜") {
            return "〜" + prompt
            // why the heck is there starts(with:) but not ends(with:)
        } else if self.character.hasSuffix("〜") {
            return "\(prompt)〜"
        } else {
            return prompt
        }
    }
    override var availableTests: [TestKind] { return [.characterToRM, .meaningToReading, .readingToMeaning] }
    var cliName: String {
        fatalError("must override cliName on \(self)")
    }
}
final class Word : NormalItem, CustomStringConvertible {
    var description: String {
        return "<Word \(self.character)>"
    }
    override class var kind: ItemKind { return .word }
    override var cliName: String { return String(self.name) }
}
final class Kanji : NormalItem, CustomStringConvertible {
    var description: String {
        return "<Kanji \(self.character)>"
    }
    override class var kind: ItemKind { return .kanji }
    override var cliName: String { return ANSI.purple(String(self.name) + " /k") }
}
final class Confusion: Item, CustomStringConvertible {
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
        super.init((name: name, birthday: birthday))
    }
    var description: String {
        return "<Confusion \(self.items)>"
    }
    override class var kind: ItemKind { return .confusion }
    override var availableTests: [TestKind] { return [.confusion] }
}
final class Flashcard: Item, CustomStringConvertible, Decodable {
    let front: String
    var backs: [Ing]
    init(from dec: any Decoder) throws {
        enum K: CodingKey { case front, backs }
        let container = try dec.container(keyedBy: K.self)
        self.front = try container.decode(String.self, forKey: .front)
        self.backs = try decodeArray(container.nestedUnkeyedContainer(forKey: .backs)) {
            try Ing(from: $0, isMeaning: true, relaxed: true)
        }
        super.init(try Item.initializer(name: self.front, from: dec))
    }
    var description: String {
        return "<Flashcard \(self.front)>"
    }
    func cliPrompt(colorful: Bool) -> String {
        return "\(front) /f"
    }
    override func cliPrint(colorful: Bool) {
        print("\(self.front) \(self.cliBacks(colorful: colorful))")
    }
    func evaluateBackAnswer(input: String, allowAlternatives: Bool) -> (outcome: TestOutcome, qual: Int, alternatives: [Item]) {
        let normalizedInput = normalizeMeaningTrimmed(trim(input))
        var levenshtein = Levenshtein()
        let qual = evaluateMeaningAnswerInner(normalizedInput: normalizedInput,
                                              meanings: self.backs,
                                              levenshtein: &levenshtein)
        let outcome: TestOutcome = qual > 0 ? .right : .wrong
        let alternatives = meaningAlternatives(meaning: normalizedInput)
        return (outcome, qual, alternatives)
    }
    func cliBacks(colorful: Bool) -> String {
        return cliIngs(ings: self.backs, colorful: colorful, tildify: { $0 })
    }
    override class var kind: ItemKind { return .flashcard }
    override var availableTests: [TestKind] { return [.flashcard] }
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
    let byReading: [String: [X]]?
    let byMeaning: [String: [X]]?
    init(_ items: [X]) {
        self.items = items
        var byName: [String: X] = [:]
        var byReading: [String: [X]]? = nil
        var byMeaning: [String: [X]]? = nil
        if X.self is NormalItem.Type {
            byReading = [:]
            byMeaning = [:]
        } else if X.self is Flashcard.Type {
            byMeaning = [:]
        }
        for item in items {
            if byName[item.name] != nil {
                fatalError("duplicate \(X.self) item named \(item.name)")
            }
            byName[item.name] = item
            if let normalItem = item as? NormalItem {
                for reading in normalItem.readings {
                    byReading![reading.text] = (byReading![reading.text] ?? []) + [item]
                }
                for meaning in normalItem.meanings {
                    byMeaning![meaning.text] = (byMeaning![meaning.text] ?? []) + [item]
                }
            } else if let flashcard = item as? Flashcard {
                for back in flashcard.backs {
                    byMeaning![back.text] = (byMeaning![back.text] ?? []) + [item]
                }
            }
        }

        let kind: ItemKind = X.kind
        for (old, new) in Subete.instance.replace[kind] ?? [:] {
            byName[old] = byName[new]!
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
        return self.byReading![reading] ?? []
    }
    func findByMeaning(_ meaning: String) -> [Item] {
        return self.byMeaning![meaning] ?? []
    }
    var vagueItems: [Item] {
        return self.items
    }
    var questions: [Question] {
        return items.flatMap { $0.myQuestions }
    }
}

enum TestKind: String, ExpressibleByArgument, Codable, CodingKeyRepresentable {
    case meaningToReading = "m2r"
    case readingToMeaning = "r2m"
    case characterToRM = "c2"
    case confusion = "kc"
    case flashcard = "fc"
}

enum TestOutcome: String {
    case right
    case wrong
    case mu
}

extension Data {
    func splut(separator: Int, includingSpaces: Bool = false) -> [Data] {
        var res: [Data] = []
        let start = self.startIndex
        let end = self.endIndex
        var i = start
        var lastStart = i
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
                res.append(self[lastStart..<lastEnd])
                if i == end { return res }
                lastStart = i + 1
            }
            i += 1
        }
        return res
    }
}
func parseInt(data: Data) -> Int? {
	var i = data.startIndex
	let end = data.endIndex
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

struct RetiredYaml: Decodable {
    let retired: [ItemKind: [String]]
    let replace: [ItemKind: [String: String]]
}
struct TestResult {
    let question: Question
    let date: Date?
    let outcome: TestOutcome
    func getRecordLine() -> String {
        let components: [String] = [
            String(Int(Date().timeIntervalSince1970)),
            self.question.testKind.rawValue,
            type(of: self.question.item).kind.rawValue,
            self.question.item.name,
            self.outcome.rawValue
        ]
        return components.joined(separator: ":")
    }

    static func parse(line: Data) throws -> TestResult? {
        var components: [Data] = line.splut(separator: 58 /* ':' */, includingSpaces: true)
        var date: Date? = nil
        var i = 0
        if components.count > 4 {
            date = Date(timeIntervalSince1970: Double(try unwrapOrThrow(parseInt(data: components[0]),
				err: MyError("invalid timestamp \(d2s(components[0]))"))))
            
        }
        ensure(components.count >= i + 4)
        if components.count > i + 4 {
            warn("extra components")
        }
        
        // TODO: rawValue with substring?
        let itemKind = try unwrapOrThrow(initWithRawValueData(components[i+1], type: ItemKind.self),
                                     err: MyError("invalid item kind \(d2s(components[i+1]))"))
        let name = components[i+2]
        if Subete.instance.retiredByData[itemKind]?.contains(name) == .some(true) {
            return nil
        }

        let question = Question(
            item: try unwrapOrThrow(Subete.instance.allByKind(itemKind).findByName(data: name),
                                err: MyError("no such item kind \(d2s(components[i+1])) name \(d2s(name))")),
			testKind: try unwrapOrThrow(initWithRawValueData(components[i], type: TestKind.self),
                                    err: MyError("invalid test kind \(d2s(components[i]))"))
        )
        return TestResult(
            question: question,
            date: date,
            outcome: try unwrapOrThrow(TestOutcome(rawValue: String(components[i+3])),
                                   err: MyError("invalid outcome kind \(d2s(components[i+3]))"))
        )
    }
    static func readAllFromLog() throws -> [TestResult] {
        let data = try Subete.instance.openLogTxt(write: false) { (fh: FileHandle) in fh.readDataToEndOfFile() }
        return data.split(separator: 10 /*"\n"*/).compactMap {
            do {
                return try TestResult.parse(line: $0)
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
        case .flashcard:
            try self.doCLIFlashcard(item: item as! Flashcard)
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
            cliPrintAlternatives(alternatives, label: "kana")
            item.cliPrintSimilarMeaning()
        
            if outcome == .right { break }
        }
    }
    func doCLIReadingToMeaning(item: NormalItem) throws {
        var prompt = item.cliReadings(colorful: false)
        if item is Kanji {
            prompt += " /k"
        }
        while true {
            let k: String = try cliRead(prompt: prompt, kana: false)
            let (outcome, qual, alternatives) = item.evaluateMeaningAnswer(input: k, allowAlternatives: true)
            let srsUpdate = try self.maybeMarkResult(outcome: outcome, final: true)
            print(cliLabel(outcome: outcome, qual: qual, srsUpdate: srsUpdate))
            item.cliPrint(colorful: true)
            cliPrintAlternatives(alternatives, label: "meaning")
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
                        cliPrintAlternatives(alternatives, label: "meaning")
                    }
                } else {
                    (outcome, qual, alternatives) = item.evaluateReadingAnswer(input: k, allowAlternatives: false)
                    let srsUpdate = try self.maybeMarkResult(outcome: outcome, final: final && modeIdx == 1)
                    print(cliLabel(outcome: outcome, qual: qual, srsUpdate: srsUpdate))
                    print(item.cliReadings(colorful: true))
                    if outcome == .wrong { // See above
                        cliPrintAlternatives(alternatives, label: "kana")
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
    func doCLIFlashcard(item: Flashcard) throws {
        let prompt = item.cliPrompt(colorful: false)
        while true {
            let k: String = try cliRead(prompt: prompt, kana: false)
            let (outcome, qual, alternatives) = item.evaluateBackAnswer(input: k, allowAlternatives: true)
            let srsUpdate = try self.maybeMarkResult(outcome: outcome, final: true)
            print(cliLabel(outcome: outcome, qual: qual, srsUpdate: srsUpdate))
            item.cliPrint(colorful: true)
            cliPrintAlternatives(alternatives, label: "answer")
            if outcome == .right {
                break
            }
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
    let item = Item((name: "test", birthday: nil))
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
        try container.encode(type(of: item).kind, forKey: .kind)
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

struct BenchSTSCommand: ParsableCommand {
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

struct BenchStartupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bench-startup")
    func run() {
        let _ = Subete()
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
            subcommands: [ForecastCommand.self, TestOneCommand.self, BenchStartupCommand.self, BenchSTSCommand.self])

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
Rerere.main()
