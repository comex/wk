//
//  ContentView.swift
//  rerere-gui
//
//  Created by Nicholas Allegra on 11/27/24.
//  Copyright © 2024 Nicholas Allegra. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
    }
}

func buildTestTest() -> Test {
    blockOnLikeYoureNotSupposedTo { await Subete.initialize() }

    let item = Subete.itemData.allWords.findByName("貰える")!
    let question = Question(item: item, testKind: .meaningToReading)
    let testSession = TestSession(forSingleQuestion: question)
    return Test(question: question, testSession: testSession)
}

#Preview {
    let x = buildTestTest()
    ContentView()
}
