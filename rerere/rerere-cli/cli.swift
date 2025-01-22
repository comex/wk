import ArgumentParser
import Foundation

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
    return try unwrapOrThrow(
        String(decoding: output!, as: UTF8.self), err: MyError("invalid utf8 in output"))
}
#endif
func runAndGetOutput(_ args: [String]) throws -> String {
    let pipe = Pipe()
    let stdoutFd = pipe.fileHandleForWriting.fileDescriptor
    let myArgs: [UnsafeMutablePointer<Int8>?] =
        args.map {
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
    return try unwrapOrThrow(
        String(decoding: output!, as: UTF8.self), err: MyError("invalid utf8 in output"))

}

struct CLI {
   func format(bit: TextBit, colorful: Bool) -> String {
        switch bit {
        case .ing(let ing, let item):
			var text = ing.text
            if colorful {
                switch (ing.superkind, ing.kind == .primary) {
                case (.meaning, true):
                    text = ANSI.purple(text)
                case (.meaning, false):
                    text = ANSI.dpurple(text)
                case (.reading, true):
                    text = ANSI.red(text)
                case (.reading, false):
                    text = ANSI.dred(text)
                case (.flashcardBack, _):
                    break
                }
				text += formatKindSuffix(item: item)
            }
            return text

        case .character(let item):
			var text = item.character
            if colorful && item is Kanji {
                text = ANSI.purple(text)
            }
			if colorful {
				text += formatKindSuffix(item: item)
			}
            return text
        
        case .flashcardFront(let item):
			return item.front

		case .unknownItemName(let item):
			return item.name
		
		case .ingsList(_, let children):
			var out = ""
			var prevKind: Ing.Kind? = nil
			for bit in children {
				guard case .ing(let ing, _) = bit else {
					fatalError("ingsList child not ing")
				}
				if let prevKind {
					// XXX: this should be different
					if ing.kind != prevKind {
						out += " >> "
					} else {
						out += ", "
					}
				}
				out += format(bit: bit, colorful: colorful)
				prevKind = ing.kind
			}
			return out
        }
    }
 
    func formatItemFull(_ item: Item, colorful: Bool) -> String {
        let bits: [TextBit] = [TextBit.bitForName(of: item)] + TextBit.bitsForAllIngs(of: item)
		return bits.map { format(bit: $0, colorful: colorful) }.joined(separator: " ")
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
        return format(bit: TextBit.bitForPromptOutput(prompt), colorful: true)
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
    func formatLabel(
        outcome: TestOutcome, qual: Int, srsUpdate: SRSUpdate, existingOutcome: TestOutcome?
    ) -> String {
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
        var out = formatLabel(
            outcome: ra.outcome, qual: ra.qual, srsUpdate: ra.srsUpdate,
            existingOutcome: ra.existingOutcome)
        // should this be further abstracted?  ...no, I want to allow divergence in GUI
        switch ra.question.testKind {
        case .meaningToReading:
			out += " " + format(bit: TextBit.character(item: item as! NormalItem), colorful: true)
            out += " " + format(bit: TextBit.bitForReadings(of: item as! NormalItem), colorful: false)
        case .readingToMeaning:
            out += " " + format(bit: TextBit.character(item: item as! NormalItem), colorful: true)
            out += " " + format(bit: TextBit.bitForMeanings(of: item as! NormalItem), colorful: true)
        case .characterToRM, .confusion:
            switch ra.prompt.expectedInput {
            case .meaning:
                out += " " + format(bit: TextBit.bitForMeanings(of: item as! NormalItem), colorful: true)
            case .reading:
                out += " " + format(bit: TextBit.bitForReadings(of: item as! NormalItem), colorful: true)
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
                args = [Subete.basePath + "/read-kana.zsh", CLI.readingPrompt]
            } else {
                args = [Subete.basePath + "/read-english.zsh", CLI.meaningPrompt]
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
    func handleBang(_ input: String, curTest: Test, gotAnswerAlready: Bool, lastTest: Test?) async {
        switch input {
        case "!right":
            await handleChangeLast(
                outcome: .right, curTest: curTest, gotAnswerAlready: gotAnswerAlready,
                lastTest: lastTest)
        case "!wrong":
            await handleChangeLast(
                outcome: .wrong, curTest: curTest, gotAnswerAlready: gotAnswerAlready,
                lastTest: lastTest)
        case "!mu":
            await handleChangeLast(
                outcome: .mu, curTest: curTest, gotAnswerAlready: gotAnswerAlready,
                lastTest: lastTest)
        default:
            print("?bang? \(input)")
        }
    }
    func handleChangeLast(
        outcome: TestOutcome, curTest: Test, gotAnswerAlready: Bool, lastTest: Test?
    ) async {
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
        let srsUpdate = try! await test.markResult(outcome: outcome)
        if !srsUpdate.isNoChangeOther {
            print(srsUpdate.cliLabel)
        }
    }

    func doOneTest(_ test: Test, lastTest: Test?) async throws {
        var gotAnswerAlready = false
        while await !test.state.isDone {
            await test.testSession.save()
            let prompt = await test.state.curPrompt!
            let nextState = await test.state.nextState
            let promptText = formatPromptOutput(prompt)
            let resp = try promptInner(
                promptText: promptText, kana: prompt.expectedInput == .reading)
            switch resp {
            case .answer(let answerText):
                let ra = try await test.handlePromptResponse(
                    input: answerText, final: nextState.isDone)
                print(formatResponseAcknowledgement(ra))
                gotAnswerAlready = true
                if ra.outcome == .right {
                    await test.setState(nextState)
                }
            case .bang(let bangText):
                await handleBang(
                    bangText, curTest: test, gotAnswerAlready: gotAnswerAlready, lastTest: lastTest)
            }
        }

    }

    func doTestInSession(test: Test, lastTest: Test?, session: isolated TestSession) async throws {
        print("[\(session.base.numDone) | \(session.numRemainingQuestions())]")
        try await doOneTest(test, lastTest: lastTest)
    }
}

extension TestKind: ExpressibleByArgument {}
extension RandomMode: ExpressibleByArgument {}
extension ItemKind: ExpressibleByArgument {}

struct ForecastCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forecast")
    func run() async {
        await Subete.initialize()
        let now = Date().timeIntervalSince1970
        let srsItems: [(nextTestDate: Int, question: Question)] = await Subete.withSRS {
            (srs: inout SRS) in
            Subete.itemData.allQuestions.compactMap { (question) in
                guard let nextTestDate = srs.info(question: question).nextTestDate else {
                    return nil
                }
                return (nextTestDate: nextTestDate, question: question)
            }
        }
        let maxDays = 20
        let secondsPerDay: Double = 60 * 60 * 24
        let byDay: [(key: Int, value: [(nextTestDate: Int, question: Question)])] =
            Dictionary(
                grouping: srsItems,
                by: { (val: (nextTestDate: Int, question: Question)) -> Int in
                    min(
                        maxDays,
                        max(0, Int(ceil((TimeInterval(val.nextTestDate) - now) / secondsPerDay))))
                }
            ).sorted { $0.key < $1.key }
        var total = 0
        for (days, items) in byDay {
            let keyStr = days == maxDays ? "later" : String(days)
            print("\(keyStr): \(items.count)")
            total += items.count
        }
        print(" * total: \(total)")
    }
}

struct TestOneCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-one")
    @Argument()
    var testKind: TestKind
    @Argument()
    var itemKind: ItemKind
    @Argument()
    var name: String
    func run() async {
        await runOrExit { try await runImpl() }
    }
    func runImpl() async throws {
        await Subete.initialize()
        let item = try unwrapOrThrow(
            Subete.itemData.allByKind(itemKind).findByName(name),
            err: MyError("no such item kind \(itemKind) name \(name)"))
        let question = Question(item: item, testKind: testKind)
        let testSession = TestSession(forSingleQuestion: question)
        let test = await Test(question: question, testSession: testSession)
        try await CLI().doOneTest(test, lastTest: nil)
    }
}

struct BenchSTSCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bench-sts")
    @Flag() var deser: Bool = false
    func run() async {
        await Subete.initialize()
        let sts = SerializableTestSession(
            pulledIncompleteQuestions: IndexableSet(Subete.itemData.allQuestions[..<500]),
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

struct BenchStartupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bench-startup")
    func run() async {
        await Subete.initialize()
    }
}

@main
struct Rerere: AsyncParsableCommand {
    @Option() var minQuestions: Int?
    @Option() var maxQuestions: Int?
    @Option() var minRandomQuestionsFraction: Double = 0.33
    @Option() var randomMode: RandomMode = .all

    static let configuration = CommandConfiguration(
        subcommands: [
            ForecastCommand.self, TestOneCommand.self, BenchStartupCommand.self,
            BenchSTSCommand.self,
        ])

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
            return (
                minQuestions: _minQuestions, maxQuestions: max(defaultMaxQuestions, _minQuestions)
            )
        case (nil, .some(let _maxQuestions)):
            return (
                minQuestions: min(defaultMinQuestions, _maxQuestions), maxQuestions: _maxQuestions
            )
        case (.some(let _minQuestions), .some(let _maxQuestions)):
            return (minQuestions: _minQuestions, maxQuestions: _maxQuestions)
        }
    }
    func gatherSRSQuestions() async -> [(nextTestDate: Int, question: Question)] {
        let now = Int(Date().timeIntervalSince1970)
        return await Subete.withSRS { (srs: inout SRS) in
            Subete.itemData.allQuestions.compactMap { (question) in
                guard let nextTestDate = srs.info(question: question).nextTestDate else {
                    return nil
                }
                return nextTestDate <= now ? (nextTestDate: nextTestDate, question: question) : nil
            }
        }
    }
    func calcQuestionSplit(minQuestions: Int, maxQuestions: Int, availSRSQuestions: Int) -> (
        numSRSQuestions: Int, numRandomQuestions: Int
    ) {
        if self.minRandomQuestionsFraction >= 1.0 {
            return (numSRSQuestions: 0, numRandomQuestions: minQuestions)
        } else {
            var numQuestionsX: Double =
                Double(availSRSQuestions) / (1.0 - self.minRandomQuestionsFraction)
            numQuestionsX = max(numQuestionsX, Double(minQuestions))
            numQuestionsX = min(numQuestionsX, Double(maxQuestions))
            let numQuestions = Int(numQuestionsX)
            let numSRSQuestions = min(
                availSRSQuestions, Int(numQuestionsX * (1.0 - self.minRandomQuestionsFraction)))
            return (
                numSRSQuestions: numSRSQuestions,
                numRandomQuestions: numQuestions - numSRSQuestions
            )
        }
    }
    func makeSerializableSession() async -> SerializableTestSession {
        let (minQuestions, maxQuestions) = resolveMinMax()
        var srsQuestions = await gatherSRSQuestions()
        let (numSRSQuestions, numRandomQuestions) = calcQuestionSplit(
            minQuestions: minQuestions, maxQuestions: maxQuestions,
            availSRSQuestions: srsQuestions.count)
        print("got \(srsQuestions.count) SRS questions")
        if numSRSQuestions < srsQuestions.count {
            print("...but limiting to \(numSRSQuestions)")
            srsQuestions.sort { $0.nextTestDate > $1.nextTestDate }
            srsQuestions = Array(srsQuestions[0..<numSRSQuestions])
        }
        return SerializableTestSession(
            pulledIncompleteQuestions: IndexableSet(srsQuestions.map { $0.question }),
            numUnpulledRandomQuestions: numRandomQuestions,
            randomMode: randomMode
        )
    }

    func run() async throws {
    
        await Subete.initialize()
        let path = "\(Subete.basePath)/sess.json"
        let url = URL(fileURLWithPath: path)
        let sess: TestSession
        do {
            sess = try TestSession(fromSaveURL: url)
            print("Loaded existing session \(path)")
        } catch let e as NSError
            where e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoSuchFileError
        {
            print("Starting new session \(path)")
            let ser = await makeSerializableSession()
            sess = TestSession(base: ser, saveURL: url)
        }
        await runOrExit {
            await sess.save()
            var lastTest: Test? = nil
            let cli = CLI()
            while let question = await sess.randomQuestion() {
                let test = await Test(question: question, testSession: sess)
                try await cli.doTestInSession(test: test, lastTest: lastTest, session: sess)
                await sess.bumpNumDone()
                lastTest = test
            }
            await sess.trashSave()
        }
    }
}
