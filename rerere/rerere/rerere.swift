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
import XCTest
import System
import Synchronization

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
func d2s(_ ud: UnsafeData) -> String {
    ud.ubp.withMemoryRebound(to: UInt8.self) { String(bytes: $0, encoding: .utf8)! }
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
let myDateFormatter: DateFormatter = {
    let mdf = DateFormatter()
    mdf.locale = Locale(identifier: "en_US_POSIX")
    mdf.dateFormat = "yyyy-MM-dd"
    return mdf
}()

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
    while !(FileManager.default.fileExists(atPath: path.pushing("kanji.json").string)) {
        path.push("..")
        if path.length > 512 {
            fatalError("failed to find wk directory")
        }
    }

    return try! URL(fileURLWithPath: path.string).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath!
}

final actor LogTxtManager {
    var lastAppend: (test: Test, appendedData: Data)? = nil

    func removeFromLog(test: Test) throws {
        if self.lastAppend?.test !== test {
            throw MyError("removeFromLog out of order")
        }
        let toRemove = self.lastAppend!.appendedData
        try self.openLogTxt(write: true) { (fh: FileHandle) throws in
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
            self.lastAppend = nil
        }
    }

    func addToLog(test: Test) throws {
        let toAppend = Data((test.result!.getRecordLine() + "\n").utf8)
        try self.openLogTxt(write: true) { (fh: FileHandle) throws in
            fh.seekToEndOfFile()
            fh.write(toAppend)
            self.lastAppend = (test: test, appendedData: toAppend)
        }
    }

    func openLogTxt<R>(write: Bool, cb: (FileHandle) throws -> R) throws -> R {
        // todo: clowd!
        let url = URL(fileURLWithPath: Subete.instance.basePath + "/log.txt")
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

struct Subete: Sendable, ~Copyable {
    nonisolated(unsafe) static var instance: Subete!
    let allWords: ItemList<Word>
    let allKanji: ItemList<Kanji>
    let allConfusion: ItemList<Confusion>
    let allFlashcards: ItemList<Flashcard>
    let allItems: [Item]
    let studyMaterials: [Int: StudyMaterial]

    let retired: [ItemKind: Set<String>]
    let replace: [ItemKind: [String: String]]

    let basePath = getWkDir()

    let nextItemID: Mutex<Int> = Mutex(0)

    let srs: Mutex<SRS>
    let logTxtManager: LogTxtManager = LogTxtManager()

    static func initialize() {
        Subete.instance = Subete()
    }
    init() {
        let retiredInfo: RetiredYaml = try! YAMLDecoder().decode(RetiredYaml.self, from: data(of: "\(basePath)/retired.yaml"))
        retired = retiredInfo.retired.mapValues { Set($0) }
        replace = retiredInfo.replace

        print("loading json...", terminator: "")
        self.studyMaterials = loadStudyMaterials(basePath: basePath)
        self.allWords = ItemList(loadJSONAndExtraYAML(basePath: basePath, stem: "vocabulary", class: Word.self))
        self.allKanji = ItemList(loadJSONAndExtraYAML(basePath: basePath, stem: "kanji", class: Kanji.self))
        self.allFlashcards = ItemList(loadFlashcardYAML(basePath: basePath))
        print("done")
        print("loading confusion...", terminator: "")
        let allKanjiConfusion = loadConfusion(path: basePath + "/confusion.txt", isWord: false)
        let allWordConfusion = loadConfusion(path: basePath + "/confusion-vocab.txt", isWord: true)
        self.allConfusion = ItemList(allKanjiConfusion + allWordConfusion)
        self.allItems = self.allWords.items + self.allKanji.items + self.allConfusion.items
        print("done")
        self.srs = Mutex(await createSRS())
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
    func createSRS() async -> SRS {
        print("loading srs...", terminator: "")
        let results = try! TestResult.readAllFromLog(manager: self.logTxtManager)
        let srs = SRS()
        let srsEpoch = 1611966197
        for result in results {
            guard let date = result.date else { continue }
            if date < srsEpoch { continue }
            let _ = srs.update(forResult: result)
        }
        for question in self.allQuestions {
            let _ = srs.info(question: question) // allow items with no results to stale
        }
        srs.updateStales(date: Int(Date().timeIntervalSince1970))
        print(" done")
        return srs
    }
    var allQuestions: [Question] {
        return allItems.flatMap { $0.myQuestions }
    }
}

enum ItemKind: String, Codable, CodingKeyRepresentable, CaseIterable {
    case word, kanji, confusion, flashcard
}

struct DataToEnumCache<T>
    where T: CaseIterable & RawRepresentable,
          T.RawValue == String
{
    let map: [MaybeOwnedData: T]
    init() {
        self.map = Dictionary(uniqueKeysWithValues: T.allCases.map { (t: T) -> (MaybeOwnedData, T) in
            (MaybeOwnedData.owned(Data(t.rawValue.utf8)), t)
        })
    }
    subscript(d: UnsafeData) -> T? {
        self.map[.unowned(d)]
    }
}

// NOTE: for some crazy reason Swift does not allow class hierarchies to be
// non-unchecked Sendable, nor actors.  So use unchecked.  The safety invariant
// is that all the properties are immutable.
class Item: Hashable, Equatable, Comparable, @unchecked Sendable {
    let name: String
    let birthday: Date?
    let id: Int

    // ItemInitializer is a workaround for convenience inits not interacting
    // well with subclassing
    typealias ItemInitializer = (name: String, birthday: Date?)
    init(_ initializer: ItemInitializer) {
        self.name = initializer.name
        self.birthday = initializer.birthday
        self.id = Subete.instance.nextItemID.withLock {
            let myId = $0
            $0 = myId + 1
            return myId
        }
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


struct Relaxed { let relaxed: Bool }
class NormalItem: Item, DecodableWithConfiguration, Decodable, @unchecked Sendable {
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
    func sameReading() -> [Item] {
        var set: Set<Item> = []
        for reading in self.readings {
            set.formUnion(Subete.instance.allByKind(Self.kind).findByReading(reading.text))
        }
        set.remove(self)
        return Array(set).sorted()
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
}
final class Word : NormalItem, CustomStringConvertible, @unchecked Sendable {
    var description: String {
        return "<Word \(self.character)>"
    }
    override class var kind: ItemKind { return .word }
}
final class Kanji : NormalItem, CustomStringConvertible, @unchecked Sendable {
    var description: String {
        return "<Kanji \(self.character)>"
    }
    override class var kind: ItemKind { return .kanji }
}
final class Confusion: Item, CustomStringConvertible, @unchecked Sendable {
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
final class Flashcard: Item, CustomStringConvertible, Decodable, @unchecked Sendable {
    let front: String
    let backs: [Ing]
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
    override class var kind: ItemKind { return .flashcard }
    override var availableTests: [TestKind] { return [.flashcard] }
}

protocol ItemListProtocol {
    func findByName(_ name: String) -> Item?
    func findByReading(_ reading: String) -> [Item]
    func findByMeaning(_ meaning: String) -> [Item]
    var names: [String] { get }
    var vagueItems: [Item] { get }
}
final class ItemList<X: Item>: CustomStringConvertible, ItemListProtocol, Sendable {
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
    var names: [String] {
        return Array(self.byName.keys)
    }
    var vagueItems: [Item] {
        return self.items
    }
    var questions: [Question] {
        return items.flatMap { $0.myQuestions }
    }
}

enum TestKind: String, Codable, CodingKeyRepresentable, CaseIterable {
    case meaningToReading = "m2r"
    case readingToMeaning = "r2m"
    case characterToRM = "c2"
    case confusion = "kc"
    case flashcard = "fc"
}

enum TestOutcome: String, CaseIterable {
    case right
    case wrong
    case mu
}


struct RetiredYaml: Decodable {
    let retired: [ItemKind: [String]]
    let replace: [ItemKind: [String: String]]
}

struct TestResultParser : ~Copyable {
    let itemKindDataToEnumCache: DataToEnumCache<ItemKind> = DataToEnumCache()
    let testKindDataToEnumCache: DataToEnumCache<TestKind> = DataToEnumCache()
    let testOutcomeDataToEnumCache: DataToEnumCache<TestOutcome> = DataToEnumCache()
    let retiredByName: [ItemKind: Set<MaybeOwnedData>] = Subete.instance.retired.mapValues { (stringList) in
        Set(stringList.map { MaybeOwnedData.owned(Data($0.utf8)) })
    }
    let itemsByName: [ItemKind: [MaybeOwnedData: Item]] = Dictionary(uniqueKeysWithValues: ItemKind.allCases.map { (itemKind) in
        let itemList = Subete.instance.allByKind(itemKind)
        return (itemKind, Dictionary(uniqueKeysWithValues: itemList.names.map {
            (MaybeOwnedData.owned(Data($0.utf8)), itemList.findByName($0)!)
        }))
    })
    let splutBuffer: StableArray<UnsafeData> = StableArray(repeating: UnsafeData(), count: 8)
}

struct TestResult {
    let question: Question
    let date: Int?
    let outcome: TestOutcome
    func getRecordLine() -> String {
        let components: [String] = [
            String(self.date!),
            self.question.testKind.rawValue,
            type(of: self.question.item).kind.rawValue,
            self.question.item.name,
            self.outcome.rawValue
        ]
        return components.joined(separator: ":")
    }

    static func parse(line: Data, parser: inout TestResultParser) throws -> TestResult? {
        try UnsafeData.withData(line) { (unsafeLine: UnsafeData) -> TestResult? in
            let components = parser.splutBuffer.buf
            let componentsCount = unsafeLine.split(separator: 58 /* ':' */, into: components, includingSpaces: true)
            var date: Int? = nil
            var i = 0
            if componentsCount > 4 {
                date = try unwrapOrThrow(parseNonnegativeInt(data: components[0]),
                    err: MyError("invalid timestamp \(d2s(parser.splutBuffer[0]))"))
                i = 1
            }
            ensure(componentsCount >= i + 4)
            if componentsCount > i + 4 {
                warn("extra components")
            }
            
            let testKindData = components[i]
            let itemKindData = components[i+1]
            let nameData = components[i+2]
            let outcomeData = components[i+3]
            
            // TODO: rawValue with substring?
            let itemKind = try unwrapOrThrow(parser.itemKindDataToEnumCache[itemKindData],
                                         err: MyError("invalid item kind \(d2s(itemKindData))"))
            guard let item = parser.itemsByName[itemKind]?[.unowned(nameData)] else {
                if parser.retiredByName[itemKind]?.contains(.unowned(nameData)) == .some(true) {
                    return nil
                }
                throw MyError("no such item kind \(d2s(itemKindData)) name \(d2s(nameData))")
            }

            let question = Question(
                item: item,
                testKind: try unwrapOrThrow(parser.testKindDataToEnumCache[testKindData],
                                        err: MyError("invalid test kind \(d2s(testKindData))"))
            )
            return TestResult(
                question: question,
                date: date,
                outcome: try unwrapOrThrow(parser.testOutcomeDataToEnumCache[outcomeData],
                                       err: MyError("invalid outcome kind \(d2s(outcomeData))"))
            )
        }
    }
    static func readAllFromLog(manager: LogTxtManager) async throws -> [TestResult] {
        let data = try await manager.openLogTxt(write: false) { (fh: FileHandle) in fh.readDataToEndOfFile() }
        var parser = TestResultParser()
        return data.split(separator: 10 /*"\n"*/).compactMap {
            do {
                return try TestResult.parse(line: $0, parser: &parser)
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
    static func dpurple(_ s: String) -> String { return color("35", s) }
    static func yback(_ s: String) -> String { return color("43", s) }
    static func rback(_ s: String) -> String { return color("41", s) }
    static func cback(_ s: String) -> String { return color("106", s) }
}

enum TestState {
    case done
    case prompt(Prompt)
    case shuffle(substates: [TestState], substateIdx: Int)

    var curPrompt: Prompt? {
        switch self {
        case .done:
            return nil
        case .prompt(let prompt):
            return prompt
        case .shuffle(let substates, let substateIdx):
            return substates[substateIdx].curPrompt
        }
    }

    var nextState: TestState {
        switch self {
        case .done:
            fatalError("nextPrompt when already done")
        case .prompt(_):
            return .done
        case .shuffle(var substates, let substateIdx):
            substates[substateIdx] = substates[substateIdx].nextState
            if !substates[substateIdx].isDone {
                return .shuffle(substates: substates, substateIdx: substateIdx)
            } else if substateIdx + 1 == substates.count {
                return .done
            } else {
                return .shuffle(substates: substates, substateIdx: substateIdx + 1)
            }
        }
    }

    var isDone: Bool {
        switch self {
        case .done: return true
        default: return false
        }
    }
}

final class Test: Sendable {
    let question: Question
    let testSession: TestSession
    var result: TestResult? = nil
    var state: TestState

    init(question: Question, testSession: TestSession) {
        self.question = question
        self.testSession = testSession
        self.state = Test.initialState(item: question.item, testKind: question.testKind)
    }

    func maybeMarkResult(outcome: TestOutcome, final: Bool) throws -> SRSUpdate {
        let ret: SRSUpdate
        if outcome == .wrong || (self.result == nil && final) {
            ret = try self.markResult(outcome: outcome)
        } else {
            ret = .noChangeOther
        }
        return ret
    }
    func markResult(outcome: TestOutcome?) throws -> SRSUpdate {
        self.testSession.setQuestionCompleteness(question: self.question, complete: outcome == .some(.right))

        if self.result != nil {
            try self.removeFromLog()
            Subete.instance.srs?.revert(forQuestion: self.question)
        }
        if let outcome = outcome {
            self.result = TestResult(question: self.question, date: Int(Date().timeIntervalSince1970), outcome: outcome)
            try self.addToLog()
            return Subete.instance.srs.update(forResult: self.result!)
        } else {
            self.result = nil
            return .noChangeOther
        }
    }

    static func initialState(item: Item, testKind: TestKind) -> TestState {
        switch testKind {
        case .meaningToReading:
            return .prompt(Prompt(item: item, output: .meaning, expectedInput: .reading))
        case .readingToMeaning:
            return .prompt(Prompt(item: item, output: .reading, expectedInput: .meaning))
        case .characterToRM:
            return .shuffle(
                substates: [
                    .prompt(Prompt(item: item, output: .character, expectedInput: .meaning)),
                    .prompt(Prompt(item: item, output: .character, expectedInput: .reading)),
                ].shuffled(),
                substateIdx: 0
            )
        case .confusion:
            return .shuffle(
                substates: (item as! Confusion).items.map {
                    initialState(item: $0, testKind: .characterToRM)
                }.shuffled(),
                substateIdx: 0
            )
        case .flashcard:
            return .prompt(Prompt(item: item, output: .flashcardFront, expectedInput: .flashcardBack))
        }
    }

    // TODO: this function kind of sucks
    // and passing `final` is an abstraction violation
    func handlePromptResponse(prompt: Prompt, input: String, final: Bool) throws -> ResponseAcknowledgement {
        let outcome: TestOutcome
        let qual: Int
        var alternativesSections: [AlternativesSection]
        let allowAlternatives: Bool // accept alternatives as answer?
        switch self.question.testKind {
        case .meaningToReading, .readingToMeaning, .flashcard:
            allowAlternatives = true
        case .characterToRM, .confusion:
            allowAlternatives = false
        }
        let alternativeItems: [Item]
        switch prompt.expectedInput {
        case .meaning:
            (outcome, qual, alternativeItems) = (prompt.item as! NormalItem).evaluateMeaningAnswer(input: input, allowAlternatives: allowAlternatives)
            alternativesSections = [AlternativesSection(kind: .meaningAlternatives, items: alternativeItems)]
        case .reading:
            (outcome, qual, alternativeItems) = (prompt.item as! NormalItem).evaluateReadingAnswer(input: input, allowAlternatives: allowAlternatives)
            alternativesSections = [AlternativesSection(kind: .readingAlternatives, items: alternativeItems)]
        case .flashcardBack:
            (outcome, qual, alternativeItems) = (prompt.item as! Flashcard).evaluateBackAnswer(input: input, allowAlternatives: allowAlternatives)
            alternativesSections = [AlternativesSection(kind: .meaningAlternatives, items: alternativeItems)]
        }

        let srsUpdate = try self.maybeMarkResult(outcome: outcome, final: final)

        switch self.question.testKind {
        case .meaningToReading, .flashcard:
            alternativesSections.append(AlternativesSection(kind: .similarMeaning, items: (prompt.item as! NormalItem).similarMeaning()))
        case .readingToMeaning:
            alternativesSections.append(AlternativesSection(kind: .sameReading, items: (prompt.item as! NormalItem).sameReading()))
        case .characterToRM, .confusion:
            // Only print alternatives if wrong, to avoid spoilers both
            // for later in the c2 and later in a confusion this might
            // be part of
            if outcome != .wrong {
                alternativesSections = []
            }
        }

        return ResponseAcknowledgement(
            question: self.question,
            prompt: prompt,
            outcome: outcome,
            existingOutcome: self.result?.outcome,
            qual: qual,
            alternativesSections: alternativesSections,
            srsUpdate: srsUpdate
        )
    }

}

enum PromptOutput {
    case meaning
    case reading
    case flashcardFront
    case character
}

enum PromptExpectedInput {
    case meaning
    case reading
    case flashcardBack
}


struct Prompt {
    let item: Item
    let output: PromptOutput
    let expectedInput: PromptExpectedInput
}

struct AlternativesSection {
    enum Kind {
        case meaningAlternatives
        case readingAlternatives
        case sameReading
        case similarMeaning
    }
    let kind: Kind
    let items: [Item]
}

struct ResponseAcknowledgement {
    let question: Question
    let prompt: Prompt
    let outcome: TestOutcome
    let existingOutcome: TestOutcome?
    let qual: Int
    let alternativesSections: [AlternativesSection]
    let srsUpdate: SRSUpdate
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

final class SRS {
    enum ItemInfo {
        case active((lastSeen: Int, points: Double, urgentRetest: Bool))
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
        var nextTestDate: Int? {
            //print("points=\(self.points) nextTestDays=\(self.nextTestDays)")
            switch self {
                case let .active(info):
                    return info.lastSeen + Int(self.nextTestDays! * 60 * 60 * 24)
                case .burned:
                    return nil
            }
        }
        var timePastDue: Int? {
            guard let next = self.nextTestDate else { return nil }
            let now = Int(Date().timeIntervalSince1970)
            return now >= next ? (now - next) : nil
        }
        mutating func updateIfStale(date: Int) {
            if case let .active(info) = self {
                if (date - info.lastSeen) > 60 * 60 * 24 * 60 {
                    //print("staling \(self)")
                    self = .burned
                }
            }
        }
        mutating func update(forResult result: TestResult) -> SRSUpdate {
            let date = result.date ?? 0

            if let birthday = result.question.item.birthday, TimeInterval(date) < birthday.timeIntervalSince1970 {
                return .anachronism
            }
            self.updateIfStale(date: date)
            //print("updating \(String(describing: self)) for result \(result) at date \(date) birthday=\(String(describing: result.question.item.birthday))")
            
            switch self {
                case .active(var info):
                    let sinceLast = date - info.lastSeen
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
                            info.points += max(Double(sinceLast) / (60*60*24), 1.0)
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
    func updateStales(date: Int) {
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
            return .active((lastSeen: Int(min(birthday, startupDate).timeIntervalSince1970), points: 0, urgentRetest: false))
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
                              date: 0,
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

