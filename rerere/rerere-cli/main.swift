import Foundation
import ArgumentParser

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
    while true {
        let waited = waitpid(pid, &st, 0)
        if waited == -1 && errno == EINTR {
            // for debugger's sake
            continue
        }
        if waited != pid {
            throw MyError("runAndGetOutput(\(args)): waitpid() failed: \(strerror(errno)!)")
        }
        break
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

struct CLI {
    func formatIngs(_ ings: [Ing], colorful: Bool, isMeaning: Bool, tildify: (String) -> String) -> String {
        var prev: Ing? = nil
        var out: String = ""
        for ing in (ings.sorted { $0.type < $1.type }) {
            if ing.type != .whitelist && ing.type != .blacklist {
                let separator = prev == nil ? "" :
                                prev!.type == ing.type ? ", " :
                                " >> "
                var colored = ing.text
                if colorful {
                    let primaryColor: (String) -> String
                    let otherColor: (String) -> String
                    if isMeaning {
                        (primaryColor, otherColor) = (ANSI.purple, ANSI.dpurple)
                    } else {
                        (primaryColor, otherColor) = (ANSI.red, ANSI.dred)
                    }
                    colored = (ing.type == .primary ? primaryColor : otherColor)(colored)
                }
                colored = tildify(colored)
                out += separator + colored
            }
            prev = ing
        }
        return out
    }

    func formatItemName(_ item: Item) -> String {
        if item is Kanji {
            return ANSI.purple(item.name) + formatKindSuffix(item: item)
        } else if item is Flashcard {
            return item.name + formatKindSuffix(item: item)
        } else {
            return item.name + formatKindSuffix(item: item)
        }
    }
    func formatItemReadings(_ normal: NormalItem, colorful: Bool) -> String {
        return formatIngs(normal.readings, colorful: colorful, isMeaning: false, tildify: normal.tildify)
    }
    func formatItemMeanings(_ normal: NormalItem, colorful: Bool) -> String {
        return formatIngs(normal.meanings, colorful: colorful, isMeaning: true, tildify: normal.tildify)
    }
    func formatItemBacks(_ fc: Flashcard, colorful: Bool) -> String {
        return formatIngs(fc.backs, colorful: colorful, isMeaning: true, tildify: { $0 })
    }

    func formatItemFull(_ item: Item, colorful: Bool) -> String {
        let name = formatItemName(item)
        if let normal = item as? NormalItem {
            let readings = formatItemReadings(normal, colorful: colorful)
            let meanings = formatItemMeanings(normal, colorful: colorful)
            return "\(name) \(readings) \(meanings)"
        }
        if let fc = item as? Flashcard {
            let backs = formatItemBacks(fc, colorful: colorful)
            return "\(name) \(backs)"
        }
        fatalError("unknown item kind \(item)")
    }

    func formatKindSuffix(item: Item) -> String {
        if item is Kanji {
            return " /k"
        } else if item is Flashcard {
            return " /f"
        } else {
            return ""
        }
    }

    func formatPromptOutput(_ prompt: Prompt) -> String {
        switch prompt.output {
        case .meaning:
            return formatItemMeanings(prompt.item as! NormalItem, colorful: false)
        case .reading:
            return formatItemReadings(prompt.item as! NormalItem, colorful: false)
        case .flashcardFront:
            return (prompt.item as! Flashcard).front
        case .character:
            return prompt.item.name
        }
    }

    func formatAlternativesInner(_ items: [Item], label: String) -> String {
        if items.isEmpty { return "" }
        let initial = "Entered \(label) matches"
        if items.count > 8 {
            return " (\(initial) \(items.count) items)"
        } else {
            var ret = " \(initial):"
            for item in items {
                ret += "\n" + formatItemFull(item, colorful: false)
            }
            return ret
        }
    }
    func formatAlternativesSection(_ sect: AlternativesSection) -> String {
        switch sect.kind {
        case .meaningAlternatives:
            return formatAlternativesInner(sect.items, label: "kana")
        case .readingAlternatives:
            return formatAlternativesInner(sect.items, label: "meaning")
        case .sameReading:
            if sect.items.isEmpty { return "" }
            if sect.items.count > 6 { return "" }
            var ret = " Same reading:"
            for item in sect.items {
                ret += "\n" + formatItemFull(item, colorful: false)
            }
            return ret
        case .similarMeaning:
            if sect.items.isEmpty { return "" }
            var ret = " Similar meaning:"
            for item in sect.items {
                ret += "\n" + formatItemFull(item, colorful: false)
            }
            return ret
        }
    }
    func formatLabel(outcome: TestOutcome, qual: Int, srsUpdate: SRSUpdate, existingOutcome: TestOutcome?) -> String {
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
        if existingOutcome == .wrong {
            back = ANSI.rback
        } else if existingOutcome == .mu {
            back = ANSI.cback
        }
        return back(text) + srsUpdate.cliLabel
    }

    func formatResponseAcknowledgement(_ ra: ResponseAcknowledgement) -> String {
        let item = ra.prompt.item
        var out = formatLabel(outcome: ra.outcome, qual: ra.qual, srsUpdate: ra.srsUpdate, existingOutcome: ra.existingOutcome)
        // should this be further abstracted?
        switch ra.question.testKind {
        case .meaningToReading:
            out += " " + formatItemName(item) + " " + formatItemReadings(item as! NormalItem, colorful: false)
        case .readingToMeaning:
            out += " " + formatItemName(item) + " " + formatItemMeanings(item as! NormalItem, colorful: true)

        case .characterToRM, .confusion:
            switch ra.prompt.expectedInput {
            case .meaning:
                out += " " + formatItemMeanings(item as! NormalItem, colorful: true)
            case .reading:
                out += " " + formatItemReadings(item as! NormalItem, colorful: true)
            default: break
            }

        case .flashcard:
            out += " " + formatItemFull(item, colorful: true)
        }
        for section in ra.alternativesSections {
            let altOut = formatAlternativesSection(section)
            if !altOut.isEmpty {
                out += "\n" + altOut
            }
        }
        return out
    }

    static let readingPrompt: String = ANSI.red("reading> ")
    static let meaningPrompt: String = ANSI.blue("meaning> ")

    enum PromptResponse {
        case answer(String)
        case bang(String)
    }

    func promptInner(promptText: String, kana: Bool) throws -> PromptResponse {
        while true {
            print(promptText)
            let args: [String]
            if kana {
                args = [Subete.instance.basePath + "/read-kana.zsh", CLI.readingPrompt]
            } else {
                args = [Subete.instance.basePath + "/read-english.zsh", CLI.meaningPrompt]
            }
            let output = trim(try runAndGetOutput(args))
            if output == "" {
                continue
            }
            if output.starts(with: "!") {
                return .bang(output)
            }
            return .answer(output)
        }
    }
    func handleBang(_ input: String, curTest: Test, gotAnswerAlready: Bool, lastTest: Test?) {
        switch input {
        case "!right":
            handleChangeLast(outcome: .right, curTest: curTest, gotAnswerAlready: gotAnswerAlready, lastTest: lastTest)
        case "!wrong":
            handleChangeLast(outcome: .wrong, curTest: curTest, gotAnswerAlready: gotAnswerAlready, lastTest: lastTest)
        case "!mu":
            handleChangeLast(outcome: .mu, curTest: curTest, gotAnswerAlready: gotAnswerAlready, lastTest: lastTest)
        default:
            print("?bang? \(input)")
        }
    }
    func handleChangeLast(outcome: TestOutcome, curTest: Test, gotAnswerAlready: Bool, lastTest: Test?) {
        let test: Test
        var outcome: TestOutcome? = outcome
        if gotAnswerAlready {
            print("changing this test")
            test = curTest
            if outcome == .right { outcome = nil }
        } else {
            print("changing last test")
            guard let t = lastTest else {
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

    func doOneTest(_ test: Test, lastTest: Test?) throws {
        var gotAnswerAlready = false
        while !test.state.isDone {
            test.testSession.save()
            let prompt = test.state.curPrompt!
            let nextState = test.state.nextState
            let promptText = formatPromptOutput(prompt) + formatKindSuffix(item: prompt.item)
            let resp = try promptInner(promptText: promptText, kana: prompt.expectedInput == .reading)
            switch resp {
            case .answer(let answerText):
                let ra = try test.handlePromptResponse(prompt: prompt, input: answerText, final: nextState.isDone)
                print(formatResponseAcknowledgement(ra))
                gotAnswerAlready = true
                if ra.outcome == .right {
                    test.state = nextState
                }
            case .bang(let bangText):
                handleBang(bangText, curTest: test, gotAnswerAlready: gotAnswerAlready, lastTest: lastTest)
            }
        }

    }

    func doTestInSession(test: Test, lastTest: Test?, session: TestSession) throws {
        print("[\(session.base.numDone) | \(session.numRemainingQuestions())]")
        try doOneTest(test, lastTest: lastTest)
    }
}

extension TestKind: ExpressibleByArgument {}
extension RandomMode: ExpressibleByArgument {}
extension ItemKind: ExpressibleByArgument {}

struct ForecastCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forecast")
    func run() {
        Subete.initialize()
        let now = Date().timeIntervalSince1970
        let srsItems: [(nextTestDate: Int, question: Question)] = Subete.instance.srs.withLock { (srs: inout SRS) in
            Subete.instance.allQuestions.compactMap { (question) in
                guard let nextTestDate = srs.info(question: question).nextTestDate else { return nil }
                return (nextTestDate: nextTestDate, question: question)
            }
        }
        let maxDays = 20
        let secondsPerDay: Double = 60 * 60 * 24
        let byDay: [(key: Int, value: [(nextTestDate: Int, question: Question)])] =
            Dictionary(grouping: srsItems, by: { (val: (nextTestDate: Int, question: Question)) -> Int in
                min(maxDays, max(0, Int(ceil((TimeInterval(val.nextTestDate) - now) / secondsPerDay))))
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
        Subete.initialize()
        let item = try unwrapOrThrow(Subete.instance.allByKind(itemKind).findByName(name),
                                     err: MyError("no such item kind \(itemKind) name \(name)"))
        let question = Question(item: item, testKind: testKind)
        let testSession = TestSession(base: SerializableTestSession(
            pulledCompleteQuestions: IndexableSet([question]),
            randomMode: .all
        ))
        let test = Test(question: question, testSession: testSession)
        try CLI().doOneTest(test, lastTest: nil)
    }
}

struct BenchSTSCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bench-sts")
    @Flag() var deser: Bool = false
    func run() {
        Subete.initialize()
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
        Subete.initialize()
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
    func gatherSRSQuestions() -> [(nextTestDate: Int, question: Question)] {
        let now = Int(Date().timeIntervalSince1970)
        return Subete.instance.srs.withLock { (srs: inout SRS) in
            Subete.instance.allQuestions.compactMap { (question) in
                guard let nextTestDate = srs.info(question: question).nextTestDate else { return nil }
                return nextTestDate <= now ? (nextTestDate: nextTestDate, question: question) : nil
            }
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
        Subete.initialize()
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
            var lastTest: Test? = nil
            let cli = CLI()
            while let question = sess.randomQuestion() {
                let test = Test(question: question, testSession: sess)
                try cli.doTestInSession(test: test, lastTest: lastTest, session: sess)
                sess.base.numDone += 1
                lastTest = test
            }
            sess.trashSave()
        }
    }
}

Levenshtein.test()
Rerere.main()
