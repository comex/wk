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

extension EnvironmentValues {
    @Entry var KIVText: String = "#?"
}

struct KanjiInputViewInner: NSViewRepresentable {

    typealias NSViewType = NSTextField
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        let kiv: KanjiInputViewInner
        
        init(kiv: KanjiInputViewInner) {
            self.kiv = kiv
        }
        deinit {
        
        }
        func controlTextDidChange(_ obj: Notification) {
            print("controlTextDidChange")
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
        
        let textField = withObservationTracking {
            NSTextField(string: context.environment.KIVText)
        } onChange: {
            print("onChange")
        }
        /*
        } onChange: { [weak textField] in
            print("onChange")
            MainActor.assumeIsolated {
                textField?.stringValue = self.text.wrappedValue
            }
        }*/
        textField.placeholderString = self.label
        textField.delegate = context.coordinator
        return textField
    }
    
    func updateNSView(_ textField: NSTextField, context: Context) {
        print("updateNSView")
    }
    let label: String
    let onSubmit: () -> Void

}

struct KanjiInputView: View {
    let label: String
    @Binding var text: String
    let onSubmit: () -> Void
    var body: some View {
        let _ = print("KIV outer: text is \(text)")
        KanjiInputViewInner(label: self.label, onSubmit: self.onSubmit)
            .environment(\.KIVText, self.text)
    }
}

struct AnswerInputView: View {
    @State private var pendingText: String = "FF"
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
