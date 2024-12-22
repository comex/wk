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
struct PromptOutputView: View {
    let prompt: Prompt
    var body: some View {
        let _ = print("POV render")
        let bits = TextBit.bitsForPromptOutput(prompt)
        
        let style: AnyShapeStyle = style(forItem: prompt.item)
        ScrollView {
            view(prompt: prompt, bits: bits)
        }
            .padding()
            .background(in: Rectangle())
            .backgroundStyle(style)

    }
    
    @ViewBuilder
    private func view(prompt: Prompt, bits: [TextBit]) -> some View {
        switch prompt.output {
            case .character: viewForCharacter(bits: bits)
            default: viewForOther(bits: bits)
        }
    }
    
    struct BitViewForOther: View {
        let bit: TextBit
        @State var hover: Bool = false
        var body: some View {
            let _ = print("BVFO render text=\(bit.text) hover=\(hover)")
            let bgColor1: Color = switch bit.kind {
            case .ing(let ing):
                ing.superkind == .reading ? readingBitBackground : meaningBitBackground
            default:
                .black.opacity(0)
            }
            let bgColor: Color = !hover ? bgColor1 :
                bgColor1.mix(with: .white, by: 0.2)
            
            Text(bit.text)//"test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test ")
                .font(Font.system(size: 20))
                
                .foregroundStyle(.white.shadow(.drop(radius: 0, x: 2, y: 2)))
                .textSelection(.enabled)
                
                .padding(5)
                .background {
                    RoundedRectangle(cornerRadius: 5)
    
                    .fill(bgColor)
                    .stroke(.mint, lineWidth: 1)
                    .animation(.easeIn.speed(hover ? 99.0 : 3.0) , value: hover)
                    
                }
                .padding(2)
                .clipped().shadow(radius: 2, x: 2, y: 2)
                .scaleEffect(hover ? 1.1 : 1.0)
                .zIndex(hover ? 2.0 : 1.0)
                .animation(.easeIn.speed(hover ? 99.0 : 3.0) , value: hover)
                .trackHover($hover)
        
            
                
        }
    }

    @ViewBuilder
    private func viewForOther(bits: [TextBit]) -> some View {
        WrappingLayout(jitterSeed: bits.first?.text.hashValue ?? 0) {
            ForEach(identifiableWrapArray(bits)) { bitWrapper in
                BitViewForOther(bit: bitWrapper.t)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    @ViewBuilder
    private func viewForCharacter(bits: [TextBit]) -> some View {
        let _ = ensure(bits.count == 1)
        Text(bits[0].text)
            .font(Font.system(size: 80))
            .padding(.leading)
            .foregroundStyle(.white.shadow(.drop(radius: 0, x: 2, y: 2)))
            .textSelection(.enabled)
    }
    private func style(forItem item: Item) -> AnyShapeStyle {
        switch type(of: item).kind {
            case .word: AnyShapeStyle(vocabBlue.gradient)
            default: AnyShapeStyle(lightGreen.gradient)
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
        HStack {
            /*
            Text("Hello, world!")
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            
            */
            
            TestSnapshotView(testSnapshot: self.test.snapshot.container)
            .border(.yellow)
//            .containerRelativeFrame([.horizontal, .vertical])
            

        }
        .border(.red)
//        .containerRelativeFrame([.horizontal, .vertical])
        
        
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
