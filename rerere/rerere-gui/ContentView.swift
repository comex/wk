//
//  ContentView.swift
//  rerere-gui
//
//  Created by Nicholas Allegra on 11/27/24.
//  Copyright © 2024 Nicholas Allegra. All rights reserved.
//

import SwiftUI

let vocabBlue = Color(red: 0.63, green: 0.00, blue: 0.94)
let lightGreen = Color(red: 0.4627, green: 0.8392, blue: 0.5)
let meaningBitBackground = Color(red: 0.16, green: 0.48, blue: 0.65)
let readingBitBackground = Color(red: 1.00, green: 0.17, blue: 0.33)
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
struct BasicTextView: View {
    let text: String
    var bgColor: Color = defaultBitBackground
    @State var hover: Bool = false
    var body: some View {
        //let _ = print("BVFO render text=\(text) hover=\(hover)")
        let realBgColor: Color = !hover ? bgColor :
            bgColor.mix(with: .white, by: 0.2)
        
        Text(text)//"test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test ")
            .font(Font.system(size: 20))
            
            .foregroundStyle(.white.shadow(.drop(radius: 0, x: 2, y: 2)))
            .textSelection(.enabled)
            
            .padding(5)
            .background {
                RoundedRectangle(cornerRadius: 5)

                .fill(realBgColor)
                .stroke(.mint, lineWidth: 1)
                .animation(.easeIn.speed(hover ? 99.0 : 3.0) , value: hover)
                
            }
            .padding(2)
            .clipped().shadow(radius: 2, x: 2, y: 2)
            .scaleEffect(hover ? 1.1 : 1.0)
            //.zIndex(hover ? 2.0 : 1.0) // this causes the layout to invalidate!
            .animation(.easeIn.speed(hover ? 99.0 : 3.0) , value: hover)
            .trackHover($hover)
    
        
            
    }
}


private func style(forItem item: Item) -> AnyShapeStyle {
    switch type(of: item).kind {
        case .word: AnyShapeStyle(vocabBlue.gradient)
        default: AnyShapeStyle(lightGreen.gradient)
    }
}

private func baseColor(forItem item: Item) -> Color {
    switch type(of: item).kind {
        case .word: vocabBlue
        default: lightGreen
    }
}

struct IngsListView: View {
    let prompt: Prompt
    let superkind: Ing.Superkind
    let children: [IdentifiableWrapper<TextBit>]
    var body: some View {
        WrappingLayout(jitterSeed: 0) { //bits.first?.text.hashValue ?? 0) {
            // repeat 100x for UI testing:
            ForEach(0..<100) { i in
                ForEach(children) { child in
                    textBitView(bit: child.t, prompt: prompt)
                }
            }
        }
    }
}
@MainActor @ViewBuilder
private func textBitView(bit: TextBit, prompt: Prompt) -> some View {
    switch bit {
    case .ing(let ing, item: _):
        let bgColor = switch ing.superkind {
            case .meaning: meaningBitBackground
            case .reading, .flashcardBack: readingBitBackground
        }
        BasicTextView(text: ing.text, bgColor: bgColor)
    case .character(item: let item):
        BasicTextView(text: item.character)
    case .flashcardFront(item: let item):
        BasicTextView(text: item.front)
    case .unknownItemName(item: let item):
        BasicTextView(text: item.name)
    case .ingsList(superkind: let superkind, children: let children):
        IngsListView(prompt: prompt, superkind: superkind, children: identifiableWrapArray(children))
    }
}
struct PromptOutputView: View {
    let prompt: Prompt
    var useAppKit: Bool = true
    var body: some View {
        let _ = print("POV render")
        let bit = TextBit.bitForPromptOutput(prompt)

        let style: AnyShapeStyle = style(forItem: prompt.item)
        if useAppKit {
            AppKitGridViewRepresentable(
                items: flattenTextBit(bit, prompt: prompt),
                backgroundColor: NSColor(baseColor(forItem: prompt.item))
            )
        } else {
            ScrollView(.vertical) {
                textBitView(bit: bit, prompt: prompt)

            }
                .padding()
                .background(in: Rectangle())
                .backgroundStyle(style)
        }

    }

}
struct TestSnapshotView : View {
    let testSnapshot: Container<Test.Snapshot?>
    var body: some View {
        VStack {
            if let snapshot = self.testSnapshot.value {
                if let prompt = snapshot.state.curPrompt {
                    PromptOutputView(prompt: prompt)
                       // .drawingGroup(opaque: false)
                    AnswerInputView(expectedInput: prompt.expectedInput)
                }
                Text("Boo \(snapshot.counterForDebugging)")
                            
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
        TextField(label, text: $myText, selection: $selection)
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
    
    @State private var pendingText: String = ""
    
    var body: some View {
        KanjiInputView(label: "Reading", text: $pendingText)
            .onSubmit {
                print("got input \(pendingText)")
                pendingText = ""
            }
    }
}


struct ContentView: View {
    let test: Test

    var body: some View {
        let _ = print("** ContentView recalc")
        VStack {
            /*
            Text("Hello, world!")
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            
            */
            
            TestSnapshotView(testSnapshot: self.test.snapshot.container)
            

        }
        
        
    }
}


#Preview {

    ContentView(test: buildTestTest(itemKind: .word, name: "貰う", testKind: .meaningToReading))
        //.containerRelativeFrame([.horizontal])
    
}

func buildTestTest(itemKind: ItemKind, name: String, testKind: TestKind) -> Test {
    blockOnLikeYoureNotSupposedTo {
        await Subete.initialize()

        let item = Subete.itemData.allByKind(itemKind).findByName(name)!
        let question = Question(item: item, testKind: testKind)
        let testSession = TestSession(forSingleQuestion: question)
        return await Test(question: question, testSession: testSession)
    }
}
