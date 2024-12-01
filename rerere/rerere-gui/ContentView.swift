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

struct KanjiInputView: NSViewRepresentable {

    typealias NSViewType = NSTextField
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        let kiv: KanjiInputView

        
        init(kiv: KanjiInputView) {
            self.kiv = kiv
        }
        
        func controlTextDidChange(_ obj: Notification) {
            
            let textField = obj.object as! NSTextField
            textField.stringValue = textField.stringValue.replacing("a", with: "bb")
            print("controlTextDidChange to \(textField.stringValue)")
            self.kiv.text = textField.stringValue
            
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            print("doCommandBy \(commandSelector)")
            if commandSelector == #selector(NSStandardKeyBindingResponding.insertNewline) {
                self.kiv.onSubmit()
                return true
            }
            return false
        }
        func controlTextDidEndEditing(_ obj: Notification) {
            print("didEndEditing")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(kiv: self)
    }
    
    func makeNSView(context: Context) -> NSTextField {
        print("makeNSView")
        
        let textField = NSTextField(string: self.text)
   
        textField.placeholderString = self.label
        textField.delegate = context.coordinator
        return textField
    }
    
    func updateNSView(_ textField: NSTextField, context: Context) {
        print("updateNSView")
        textField.stringValue = self.text
    }
    let label: String
    @Binding var text: String
    let onSubmit: () -> Void

}

struct AnswerInputView: View {
    @State private var pendingText: String = ""
    let takeInput: (String) -> Void
    var body: some View {
        KanjiInputView(label: "Reading", text: $pendingText, onSubmit: {
            
            takeInput(pendingText)
            pendingText = ""
        })
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
