//
//  ContentView.swift
//  rerere-gui
//
//  Created by Nicholas Allegra on 11/27/24.
//  Copyright © 2024 Nicholas Allegra. All rights reserved.
//

import SwiftUI

struct SnapshotView : View {
    let testSnapshot: Container<Test.Snapshot?>
    var body: some View {
        Text("Boo \(self.testSnapshot.value?.boogaloo ?? -1)")
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
                print("onChange 1 text=\(text.wrappedValue) myText=\(myText)")
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
                if !changed {
                    return
                }
                myText = modText
                selection = sel
                print("onChange 1 text=\(text.wrappedValue) myText=\(myText)")
                text.wrappedValue = myText
            }
            .onChange(of: text.wrappedValue) {
                print("onChange 2 text=\(text.wrappedValue) myText=\(myText)")
                myText = text.wrappedValue
                selection = nil
            }
    }

}

struct AnswerInputView: View {
    @State private var pendingText: String = ""
    let takeInput: (String) -> Void
    var body: some View {
        KanjiInputView(label: "Reading", text: $pendingText)
            .onSubmit {
                takeInput(pendingText)
                pendingText = ""
            }
    }
}


struct ContentView: View {
    let test: Test = buildTestTest()
    var bla: String = "asdf"

    func takeInput(_ text: String) {
        print("got input \(text)")
    }
    

    var body: some View {
        let _ = print("** ContentView recalc")
        VStack {
            /*
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            */
            Text("\(test.question)")
            SnapshotView(testSnapshot: self.test.snapshot.container)
            AnswerInputView(takeInput: self.takeInput)

        }
        .padding()
        
    }
}

func buildTestTest() -> Test {
    blockOnLikeYoureNotSupposedTo {
        await Subete.initialize()

        let item = Subete.itemData.allWords.findByName("貰う")!
        let question = Question(item: item, testKind: .meaningToReading)
        let testSession = TestSession(forSingleQuestion: question)
        return await Test(question: question, testSession: testSession)
    }
}


#Preview {
    AnswerInputView { print("got \($0)") }
}
