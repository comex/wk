// TODO FIX BANGS ON CONFUSION
// TODO why didn't I get a reading match for 挟む
// TODO mu overwrites a later wrong?
import Foundation
import Yams
import ArgumentParser

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
func loadJSONAndExtraYAML<T: JSONInit>(basePath: String, stem: String, class: T.Type) -> [T] {
    let base = (loadJSON(path: "\(basePath)/\(stem).json") as! [NSDictionary]).map { T(json: $0, relaxed: false) }
    let extra = (loadYAML(path: "\(basePath)/extra-\(stem).yaml") as! [NSDictionary]).map { T(json: $0, relaxed: true) }
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
        self.allWords = ItemList(loadJSONAndExtraYAML(basePath: basePath, stem: "vocabulary", class: Word.self))
        self.allKanji = ItemList(loadJSONAndExtraYAML(basePath: basePath, stem: "kanji", class: Kanji.self))
        print("loading confusion")
        let allKanjiConfusion = loadConfusion(path: basePath + "confusion.txt", isWord: false)
        let allWordConfusion = loadConfusion(path: basePath + "confusion-vocab.txt", isWord: true)
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
    func createSRSFromLog() -> SRS {
        let results = try! TestResult.readAllFromLog()
        let srs = SRS()
        let srsEpoch = Date(timeIntervalSince1970: 1611966197)
		for result in results {
			guard let date = result.date else { continue }
			if date < srsEpoch { continue }
			
			let _ = srs.update(forResult: result)
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
    case primary, secondary, whitelist
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
        if let d = json["data"] {
            data = d as! NSDictionary
        } else {
            if !relaxed { fatalError("expected 'data'") }
            data = json
        }

        //self.json = json
        self.character = trim(data["characters"] as! String)
        self.readings = (data["readings"] as! [Any]).map { Ing(readingWithJSON: $0, relaxed: relaxed) }
        var meanings = (data["meanings"] as! [Any]).map { Ing(meaningWithJSON: $0, relaxed: relaxed) }
        if let auxiliaryMeanings = json["auxiliary_meanings"] {
            meanings += (auxiliaryMeanings as! [Any]).map { Ing(auxiliaryMeaningWithJSON: $0) }
        }
        self.meanings = meanings
        super.init(name: self.character)
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

    func evaluateReadingAnswer(input: String, withAlternatives: Bool) -> (outcome: TestOutcome, qual: Int, alternatives: [Item]) {
        // TODO this sucks
        let normalizedInput = normalizeReadingTrimmed(trim(input))
        let qual = evaluateReadingAnswerInner(normalizedInput: normalizedInput)
        var outcome: TestOutcome = qual > 0 ? .right : .wrong
        let alternatives = withAlternatives ? readingAlternatives(reading: normalizedInput) : []
        if outcome == .wrong && alternatives.contains(where: { (alternative: Item) in
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
    func evaluateMeaningAnswer(input: String, withAlternatives: Bool) -> (outcome: TestOutcome, qual: Int, alternatives: [Item]) {
        let normalizedInput = normalizeMeaningTrimmed(trim(input))
        var levenshtein = Levenshtein()
        let qual = evaluateMeaningAnswerInner(normalizedInput: normalizedInput, levenshtein: &levenshtein)
        var outcome: TestOutcome = qual > 0 ? .right : .wrong
        let alternatives = withAlternatives ? meaningAlternatives(meaning: normalizedInput) : []
        if outcome == .wrong && alternatives.contains(where: { (alternative: Item) in
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
                                " >> ";
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
    var cliName: String { fatalError("lol") } // TODO
    override var availableTests: [TestKind] { return [.characterToRM, .meaningToReading, .readingToMeaning] }
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
            try self.doCLICharacterToRM(item: self.item as! NormalItem, final: true)
        case .confusion:
            try self.doCLIConfusion(item: self.item as! Confusion)
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
            let (outcome, qual, alternatives) = item.evaluateReadingAnswer(input: k, withAlternatives: true)
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
            let (outcome, qual, alternatives) = item.evaluateMeaningAnswer(input: k, withAlternatives: true)
			let srsUpdate = try self.maybeMarkResult(outcome: outcome, final: true)
            print(cliLabel(outcome: outcome, qual: qual, srsUpdate: srsUpdate))
            item.cliPrint(colorful: true)
            item.cliPrintAlternatives(alternatives, isReading: false)
            if outcome != .right {
                item.cliPrintSameReadingIfFew()
            } else {
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
                    (outcome, qual, alternatives) = item.evaluateMeaningAnswer(input: k, withAlternatives: false)
					let srsUpdate = try self.maybeMarkResult(outcome: outcome, final: final && modeIdx == 1)
                    print(cliLabel(outcome: outcome, qual: qual, srsUpdate: srsUpdate))
                    print(item.cliMeanings(colorful: true))
                    item.cliPrintMeaningAlternatives(alternatives)
                } else {
                    (outcome, qual, _) = item.evaluateReadingAnswer(input: k, withAlternatives: false)
					let srsUpdate = try self.maybeMarkResult(outcome: outcome, final: final && modeIdx == 1)
                    print(cliLabel(outcome: outcome, qual: qual, srsUpdate: srsUpdate))
                    print(item.cliReadings(colorful: true))
                }
                
               
                if outcome == .right { break }
            }
        }
    }
    func doCLIConfusion(item: Confusion) throws {
		let items = item.items.shuffled()
        for (i, subitem) in items.enumerated() {
            try doCLICharacterToRM(item: subitem as! NormalItem, final: i == items.count - 1 )
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
	func maybeMarkResult(outcome: TestOutcome, final: Bool) throws -> SRSUpdate {
		if self.result == nil && (outcome == .wrong || final) {
			return try self.markResult(outcome: outcome)
		} else {
			return .noChangeOther
		}
	}
    func markResult(outcome: TestOutcome?) throws -> SRSUpdate {
        if self.result != nil {
            try self.removeFromLog()
            Subete.instance.srs?.revert(forItem: self.item)
        }
        if let outcome = outcome {
            self.result = TestResult(testKind: self.testKind, item: self.item, date: Date(), outcome: outcome)
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
			//print("updating \(String(describing: info0)) for result \(result)")
			self.updateIfStale(date: date)
			
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
    private var itemInfo: [Item: ItemInfo] = [:]
    private var backup: (Item, ItemInfo?)? = nil
    func update(forResult result: TestResult) -> SRSUpdate {
        var info = self.info(item: result.item)
        self.backup = (result.item, info)
        let srsUpdate = info.update(forResult: result)
        itemInfo[result.item] = info
        return srsUpdate
    }
    func updateStales(date: Date) {
		for (item, var info) in itemInfo {
			info.updateIfStale(date: date)
			itemInfo[item] = info
		}
	}
    func revert(forItem item: Item) {
        let backup = self.backup!
        ensure(backup.0 == item)
        self.itemInfo[backup.0] = backup.1
        self.backup = nil
    }
    func info(item: Item) -> ItemInfo {
		if let info = self.itemInfo[item] {
		    return info
		}
		if item is Confusion && false {
		    // XXX this is totally wrong
		    return .active((lastSeen: Date(timeIntervalSince1970: 0), points: 0, urgentRetest: false))
		} else {
		    return .burned
		}
	}
}

func testSRS() {
	let item = Item(name: "test")
	var info: SRS.ItemInfo = .burned
	let _ = info.update(
	    forResult: TestResult(testKind: .confusion,
							  item: item,
							  date: Date(timeIntervalSince1970: 0),
							  outcome: .wrong))
	for i in 0... {
		let srsUpdate = info.update(
			forResult: TestResult(testKind: .confusion,
								  item: item,
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
    init(items: [(T, Double)]) {
		for (item, weight) in items {
			self.add(item, weight: weight)
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

enum RandomMode: String, CaseIterable, ExpressibleByArgument {
    case all
    case confusion
}

struct Rerere: ParsableCommand {
    @Option() var minItems: Int?
    @Option() var maxItems: Int?
    @Option() var minRandomItemsFraction: Double = 0.33
    @Option() var randomMode: RandomMode = .all

    func validate() throws {
        guard minRandomItemsFraction >= 0 && minRandomItemsFraction <= 1 else {
            throw ValidationError("min-random-items-fraction should be in [0,1]")
        }
        guard minItems == nil || maxItems == nil || minItems! < maxItems! else {
            throw ValidationError("min-items should < max-items")
        }
    }

    func run() {
        let _ = Subete()
        //testSRS(); return
        //print(Subete.instance.allByKind(.word).findByMeaning(String(normalizeMeaning("to narrow"))))
        //return
        let defaultMinItems = 50
        let defaultMaxItems = 75
        let minItems: Int, maxItems: Int
        switch (self.minItems, self.maxItems) {
            case (nil, nil):
                (minItems, maxItems) = (defaultMinItems, defaultMaxItems)
            case (.some(let _minItems), nil):
                (minItems, maxItems) = (_minItems, max(defaultMaxItems, _minItems))
            case (nil, .some(let _maxItems)):
                (minItems, maxItems) = (min(defaultMinItems, _maxItems), _maxItems)
            case (.some(let _minItems), .some(let _maxItems)):
                (minItems, maxItems) = (_minItems, _maxItems)
        }
        
        var remainingItems: Set<Item> = Set()

	    let srs = Subete.instance.srs!
	    let now = Date()
	    var srsItems: [(nextTestDate: Date, item: Item)] = Subete.instance.allItems.compactMap { (item) in
		    guard let nextTestDate = srs.info(item: item).nextTestDate else { return nil }
		    return nextTestDate <= now ? (nextTestDate: nextTestDate, item: item) : nil
	    }
	    print("got \(srsItems.count) SRS items")

	    let numRandomItems: Int
	    let numSRSItems: Int
	    if self.minRandomItemsFraction >= 1.0 {
	        numRandomItems = minItems
	        numSRSItems = 0
	    } else {
	        var numItemsX: Double = Double(srsItems.count) / (1.0 - self.minRandomItemsFraction)
	        numItemsX = max(numItemsX, Double(minItems))
	        numItemsX = min(numItemsX, Double(maxItems))
	        let numItems = Int(numItemsX)
	        numSRSItems = min(srsItems.count, Int(numItemsX * (1.0 - self.minRandomItemsFraction)))
	        numRandomItems = numItems - numSRSItems
	    }

	    if numSRSItems < srsItems.count {
		    srsItems.sort { $0.nextTestDate > $1.nextTestDate}
		    srsItems = Array(srsItems[0..<numSRSItems])
		    print("...but limiting to \(numSRSItems)")
	    }

	    for (_, item) in srsItems { remainingItems.insert(item) }

        do {
		    var availRandomItems: [(Item, Double)] = []
		    switch self.randomMode {
			    case .all:
				    availRandomItems += (Subete.instance.allWords.items + Subete.instance.allKanji.items).map { ($0, 1.0) }
				    availRandomItems += Subete.instance.allConfusion.items.map { ($0, 10.0) }
			    case .confusion:
				    availRandomItems += Subete.instance.allConfusion.items.map { ($0, 1.0) }
		    }
		    var lottery: WeightedList<Item> = WeightedList(items: availRandomItems)
		    var count = 0
		    while count < numRandomItems && !lottery.isEmpty {
			    remainingItems.insert(lottery.takeRandomElement()!)
			    count += 1
		    }
	    }

        var numDone = 0
        do {
            while let item = remainingItems.randomElement() {
                let testKind = item.availableTests.randomElement()!
                let test = Test(kind: testKind, item: item)
                print("[\(numDone) | \(remainingItems.count)]")
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
}
Levenshtein.test()
//print("   :xsamdfa: b  :  c:   ".splut(separator: 58, includingSpaces: true, map: { $0 }))
Rerere.main()
