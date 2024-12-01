//
//  ContentView.swift
//  rerere-gui
//
//  Created by Nicholas Allegra on 11/27/24.
//  Copyright © 2024 Nicholas Allegra. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    let test: Test = buildTestTest()
    let testSnapshot: Container<Test.Snapshot?>
    @State private var pendingText: String = ""
    init() {
        self.testSnapshot = self.test.snapshot.container
    }
    func shoveTest() {
        //let prompt = lastPrompt!
        let text = pendingText
        pendingText = ""
        Task {
            
        }
    }
    func getText(_ snapshot: Test.Snapshot?) -> String {
        return "Boo \(snapshot?.boogaloo ?? -1)"
    }

    var body: some View {
        
        VStack {
            /*
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            */
            Text("\(test.question)")
            
            Text(getText(testSnapshot.value))
            TextField("Some text", text: $pendingText)
                .onSubmit(shoveTest)
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
    ContentView()
}
