//
//  ContentView.swift
//  rerere-gui
//
//  Created by Nicholas Allegra on 11/27/24.
//  Copyright © 2024 Nicholas Allegra. All rights reserved.
//

import SwiftUI

let vocabBlue = Color(red: 0.63, green: 0.00, blue: 0.94)
let kanjiPink = Color(red: 1.00, green: 0.00, blue: 0.67)
let lightGreen = Color(red: 0.4627, green: 0.8392, blue: 0.5)
let meaningBitBackground = Color(red: 0.16, green: 0.48, blue: 0.65)
let readingBitBackground = Color(red: 1.00, green: 0.17, blue: 0.33)
//let itemNameBitBackground = Color(red: 0.57, green: 0.49, blue: 0.16)
let itemNameBitBackgroundForLine = Color(red: 0.44, green: 0.23, blue: 0.55)
let defaultBitBackground = Color.black.opacity(0)

struct IdentifiableWrapper<T>: Identifiable {
    typealias ID = Int
    let t: T
    let id: Int
}
func identifiableWrapArray<T>(_ ts: [T]) -> [IdentifiableWrapper<T>] {
    ts.enumerated().map { IdentifiableWrapper(t: $0.element, id: $0.offset) }
}

extension View {
    func trackHover(_ hovering: Binding<Bool>) -> some View {
        self.onContinuousHover { (phase: HoverPhase) -> Void in
            switch phase {
                case .active(_): hovering.wrappedValue = true
                case .ended: hovering.wrappedValue = false
            }
        }
    }
}

func containsJapanese(_ text: String) -> Bool {
    text.unicodeScalars.contains {
        // slightly overinclusive but it doesn't matter
        $0.value >= 0x3000 && $0.value <= 0x9fff
    }
}

struct BitBoxView: View {
    let text: String
    let bgColor: Color
    let style: TextBitsStyle
    var isFullWidth: Bool = false
    @State var hover: Bool = false
    var body: some View {
        //let _ = print("BVFO render text=\(text) hover=\(hover)")
        let bgColor: Color = {
            var c = self.bgColor
            if hover { c = c.mix(with: .white, by: 0.2) }
            return c
        }()
        
        let size: CGFloat = if style == .line {
            20
        } else {
            if isFullWidth {
                60
            } else if containsJapanese(text) {
                40
            } else {
                25
            }
        }
        
        Text(text)//"test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test ")
            .font(Font.system(size: size))
            
            .foregroundStyle(.white.shadow(.drop(radius: 0, x: 2, y: 2)))
            .textSelection(.enabled)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(5)
            .background {
                RoundedRectangle(cornerRadius: 5)

                .fill(bgColor)
                .stroke(.mint, lineWidth: 1)
                .animation(.easeIn.speed(hover ? 99.0 : 3.0) , value: hover)
                
            }
            .padding(2)
            //.clipped() // this doesn't seem to help perf
            .shadow(radius: 2, x: 2, y: 2)
            .scaleEffect(hover ? 1.1 : 1.0)
            //.zIndex(hover ? 2.0 : 1.0) // this causes the layout to invalidate on hover, we don't need it
            .animation(.easeIn.speed(hover ? 99.0 : 3.0) , value: hover)
            .trackHover($hover)
            //.drawingGroup(opaque: false) // messes up color
        
            
    }
}




enum TextBitsStyle {
    case line
    case prompt
}

struct IngsListView: View {
    let superkind: Ing.Superkind
    let children: [IdentifiableWrapper<TextBit>]
    let style: TextBitsStyle
    @State private var numChildren: Int = 100
    var body: some View {
        if style == .line {
            ForEach(children) { child in
                textBitView(bit: child.t, style: style)
            }
        } else {
            WrappingLayout { //bits.first?.text.hashValue ?? 0) {
                ForEach(children) { child in
                    textBitView(bit: child.t, style: style)
                }
            }
        }
    }
}
@MainActor @ViewBuilder
private func textBitView(bit: TextBit, style: TextBitsStyle) -> some View {
    let itemNameBitBackground: Color = style == .line ? itemNameBitBackgroundForLine : Color.black.opacity(0)
    switch bit {
    case .ing(let ing, item: _):
        let bgColor = switch ing.superkind {
            case .meaning: meaningBitBackground
            case .reading, .flashcardBack: readingBitBackground
        }
        BitBoxView(text: ing.text, bgColor: bgColor, style: style)
    case .character(item: let item):
        BitBoxView(text: item.character, bgColor: itemNameBitBackground, style: style, isFullWidth: style == .prompt)
    case .flashcardFront(item: let item):
        BitBoxView(text: item.front, bgColor: itemNameBitBackground, style: style)
    case .unknownItemName(item: let item):
        BitBoxView(text: item.name, bgColor: itemNameBitBackground, style: style)
    case .ingsList(superkind: let superkind, children: let children):
        //let xchildren = Array(repeating: children, count: 100).flatMap { $0 }

        IngsListView(superkind: superkind, children: identifiableWrapArray(children), style: style)
            //.border(Color.black, width: 1)
    }
}
struct PromptOutputView: View {
    let prompt: Prompt
    let showEverything: Bool

    var body: some View {
        let _ = print("POV render")
        let shapeStyle: AnyShapeStyle = style(for: prompt.item)
        let bits = identifiableWrapArray(TextBit.allBits(for: prompt.item))

        VStack {
            ForEach(bits) { bit in
                let visible = showEverything || TextBit.shouldShowTopLevelBitForPromptOutput(bit: bit.t, prompt: prompt)
                if visible {
                    textBitView(bit: bit.t, style: .prompt)
                        .animation(.easeInOut(duration: 0.05), value: showEverything)
                }
            }
        }
            .padding()
            .background(in: Rectangle())
            .backgroundStyle(shapeStyle)

    }

    private func style(for item: Item) -> AnyShapeStyle {
        switch type(of: item).kind {
            case .word: AnyShapeStyle(vocabBlue.gradient)
            case .kanji: AnyShapeStyle(kanjiPink.gradient)
            default: AnyShapeStyle(lightGreen.gradient)
        }
    }
}
struct AlternativesSectionView: View {
    let sect: AlternativesSection
    @State private var expanded: Bool = true
    var body: some View {
        let _ = print(sect)
        let label = switch sect.kind {
        case .meaningAlternatives:
            "Meaning Alternatives"
        case .readingAlternatives:
            "Reading Alternatives"
        case .sameReading:
            "Same Reading"
        case .similarMeaning:
            "Similar Meaning"
        }
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(identifiableWrapArray(sect.items)) { item in
                ItemLineView(item: item.t)
            }
        } label: {
            Label(label, systemImage: "wat")
                .labelStyle(.titleOnly)
#if os(macOS)
                    .onTapGesture {
                        expanded.toggle()
                    }
#endif
        }
    }
}
struct ItemLineView: View {
    let item: Item
    var body: some View {
        let bits: [TextBit] = TextBit.allBits(for: item)

        WrappingLayout {
            ForEach(identifiableWrapArray(bits)) { bit in
                textBitView(bit: bit.t, style: .line)
            }
        }
        
    }
}

struct ResponseAcknowledgementView: View {
    let responseAcknowledgement: ResponseAcknowledgement
    var body: some View {
        VStack {
            ForEach(identifiableWrapArray(responseAcknowledgement.alternativesSections)) { sect in
                if !sect.t.items.isEmpty {
                    AlternativesSectionView(sect: sect.t)
                }
            }
        }.padding(.horizontal, 5)
    }
}
struct TestSnapshotView : View {
    let testSnapshot: Container<Test.Snapshot?>
    let submitCallback: (String) -> Void
    let isInputFocused: FocusState<Bool>.Binding?

    var body: some View {
        VStack {
            if let snapshot = self.testSnapshot.value {
                if let prompt = snapshot.state.curPrompt {
                    ScrollView(.vertical) {
                        PromptOutputView(prompt: prompt, showEverything: snapshot.lastResponseAcknowledgement != nil)
                           // .drawingGroup(opaque: false)
                        if let lastResponseAcknowledgement = snapshot.lastResponseAcknowledgement {
                            ResponseAcknowledgementView(responseAcknowledgement: lastResponseAcknowledgement)
                        }
                    }
                        .scrollDismissesKeyboard(.immediately)

                    AnswerInputView(expectedInput: prompt.expectedInput, submitCallback: submitCallback, isInputFocused: isInputFocused)
                        .padding(.horizontal, 4)
                }
                            
            } else {
                Text("Loading")
            }
        }
    }
}

struct KanjiInputView: View {
    let label: String
    let text: Binding<String>
    
    @State var myText: String
    @State var selection: TextSelection? = nil
    init(label: String, text: Binding<String>) {
        self.label = label
        self.text = text
        self.myText = text.wrappedValue
    }

    var body: some View {
        TextField(label, text: $myText, selection: $selection, axis: .vertical)
            .autocorrectionDisabled()
#if os(iOS)
            .textInputAutocapitalization(.never)
#endif
            .onChange(of: myText) {
                var modText = myText
                //print("onChange 1 text=\(text.wrappedValue) myText=\(myText)")
                //if modText == text.wrappedValue { return }
                var sel = selection
                var changed = false
                fixKana(&modText) { fixIndex in
                    changed = true
                    if sel != nil {
                        switch sel!.indices {
                        case .multiSelection(let rangeSet):
                            sel = TextSelection(ranges: RangeSet(rangeSet.ranges.map { (range: Range<String.Index>) in
                                fixIndex(range.lowerBound)..<fixIndex(range.upperBound)
                            }))
                        case .selection(let range):
                            sel = TextSelection(range: fixIndex(range.lowerBound)..<fixIndex(range.upperBound))
                        @unknown default:
                            fatalError("unknown selection kind")
                        }
                    }
                }
                
                text.wrappedValue = modText

                if !changed {
                    return
                }
                myText = modText
                selection = sel
                
            }
            .onChange(of: text.wrappedValue) {
                //print("onChange 2 text=\(text.wrappedValue) myText=\(myText)")
                myText = text.wrappedValue
                selection = nil
            }
    }

}

struct AnswerInputView: View {
    let expectedInput: PromptExpectedInput
    let submitCallback: (String) -> Void
    let isInputFocused: FocusState<Bool>.Binding?
    @FocusState var localFocused: Bool

    @State private var pendingText: String = ""

    var body: some View {
        if let isInputFocused { let _ = print("AIV: isFocused=\(isInputFocused.wrappedValue)") }
        let field: any View = switch expectedInput {
        case .meaning:
            TextField("Meaning", text: $pendingText, axis: .vertical)
               
        case .reading:
            KanjiInputView(label: "Reading", text: $pendingText)


        case .flashcardBack:
            TextField("Flashcard", text: $pendingText, axis: .vertical)
        }
        
        AnyView(field)
            .focused(isInputFocused ?? $localFocused)
            .onAppear {
                if let isInputFocused { isInputFocused.wrappedValue = true }
            }
            .onSubmit {
                self.doSubmit()
            }
            .onChange(of: pendingText) {
                if pendingText.hasSuffix("\n") {
                    pendingText.removeLast()
                    self.doSubmit()
                }
            }
    }
    func doSubmit() {
        print("got input \(pendingText)")
        self.submitCallback(pendingText)
        pendingText = ""
    }
}

@MainActor
final class BookmarkManager: ObservableObject {
    var wkURL: URL? = nil
    enum State {
        case Uninit, Loading, Ready
    }
    @Published var state: State = .Uninit
    init() {
        if let bookmark = UserDefaults.standard.data(forKey: "WKDirBookmark") {
            var stale = false
            
            do {
#if os(macOS)
                let options: NSURL.BookmarkResolutionOptions = [.withSecurityScope]
#else
                let options: NSURL.BookmarkResolutionOptions = []
#endif
                
                let url = try URL(resolvingBookmarkData: bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
                if stale {
                    try saveBookmark(url: url)
                }
                self.setURL(url)
            } catch (let e) {
                print("Failed to resolve bookmark: \(e)")
            }
        } else {
            print("No WKDirBookmark setting")
        }
    }

    func saveBookmark(url: URL) throws {
#if os(macOS)
        let options: NSURL.BookmarkCreationOptions = [.withSecurityScope]
#else
        let options: NSURL.BookmarkCreationOptions = []
#endif
        let bookmarkData = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo:
         nil)
        UserDefaults.standard.set(bookmarkData, forKey: "WKDirBookmark")
    }
    func setURL(_ url: URL) {
        
        ensure(self.state == .Uninit)
        self.state = .Loading
        guard url.startAccessingSecurityScopedResource() else {
            fatalError("startAccessingSecurityScopedResource failed for \(url)")
        }
        Task {


            await Subete.initialize(settings: SubeteSettings(useFakeLog: true, wkDir: url))
            // lazy-load SRS:
            Task { await Subete.withSRS { _ in } }
            self.state = .Ready
        }
    }
}

struct ContentView: View {
    @StateObject var bookmarkManager = BookmarkManager()
    @State var isImporting: Bool = false
    @State var theTest: Test? = nil // TBD
    let isInputFocused: FocusState<Bool>.Binding?
    var body: some View {
        let _ = print("** ContentView recalc")
        switch bookmarkManager.state {
        case .Uninit:
            Button("Select WK Dir") {
                self.isImporting = true
            }.fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    bookmarkManager.setURL(url)
                    try! bookmarkManager.saveBookmark(url: url)
                    print("import success")
                case .failure:
                    print("import failed")
                }
            }
  
        case .Loading:
            Text("loading")
        case .Ready:
            let _ = Task {
                if theTest == nil { theTest = buildTestTest(itemKind: .word, name: "貰う", testKind: .meaningToReading) }
            }
            if let theTest {
                TestView(test: theTest, isInputFocused: isInputFocused)
            } else {
                Text("no test yet")
            }

        }
    }
}
struct TestView: View {
    let test: Test
    let isInputFocused: FocusState<Bool>.Binding?
    var body: some View {
        TestSnapshotView(testSnapshot: self.test.snapshot.container, submitCallback: { (input: String) in
            Task { try! await self.test.handlePromptResponse(input: input) }
        }, isInputFocused: isInputFocused)
        
    }
}

#Preview {

    TestView(test: buildTestTest(itemKind: .word, name: "貰う", testKind: .meaningToReading, input: "asdf"), isInputFocused: nil)
    //ContentView(test: buildTestTest(itemKind: .kanji, name: "貰", testKind: .characterToRM, input: nil))
    
}

func buildTestTest(itemKind: ItemKind, name: String, testKind: TestKind, input: String? = nil) -> Test {
    blockOnLikeYoureNotSupposedTo {
        if Subete.didInit.load() == nil {
            await Subete.initialize(settings: SubeteSettings(useFakeLog: true, wkDir: findWKDirOnBuildMachine()))
        }

        let item = Subete.itemData.allByKind(itemKind).findByName(name)!
        let question = Question(item: item, testKind: testKind)
        let testSession = TestSession(forSingleQuestion: question)
        let test = await Test(question: question, testSession: testSession)
        if let input { try! await test.handlePromptResponse(input: input) }
        return test
    }
}
