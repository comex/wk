//
//  ContentView.swift
//  rerere-gui
//
//  Created by Nicholas Allegra on 11/27/24.
//  Copyright © 2024 Nicholas Allegra. All rights reserved.
//

import SwiftUI

let meaningBlue = Color(red: 0.2627, green: 0.2392, blue: 0.5)
let lightGreen = Color(red: 0.4627, green: 0.8392, blue: 0.5)
struct PromptOutputView: View {
    let prompt: Prompt
    var body: some View {
        VStack {
            switch prompt.output {
            case .character:
                // TODO: make selectable
                // TODO: fill width
                let character = prompt.item.name
                Text(character)
                    .font(Font.system(size: 80))
                    .foregroundStyle(.white.shadow(.drop(radius: 0, x: 2, y: 2)))
                    
            default:
                fatalError("TODO")
            
            }
        }
            .padding()
            .background(in: Rectangle())
            .backgroundStyle(meaningBlue.gradient)
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
                Text("Boo \(snapshot.boogaloo)")
                            
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
    let test: Test = buildTestTest()


    

    var body: some View {
        let _ = print("** ContentView recalc")
        VStack {
            /*
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            */
            TestSnapshotView(testSnapshot: self.test.snapshot.container)

        }
        .padding()
        
    }
}

func buildTestTest() -> Test {
    blockOnLikeYoureNotSupposedTo {
        await Subete.initialize()

        let item = Subete.itemData.allWords.findByName("貰う")!
        let question = Question(item: item, testKind: .characterToRM)
        let testSession = TestSession(forSingleQuestion: question)
        return await Test(question: question, testSession: testSession)
    }
}


#Preview {
    ContentView()
}
