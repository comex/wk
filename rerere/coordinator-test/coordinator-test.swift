//
//  coordinator_testApp.swift
//  coordinator-test
//
//  Created by Nicholas Allegra on 4/5/26.
//  Copyright © 2026 Nicholas Allegra. All rights reserved.
//

import SwiftUI

final class Presenter: NSObject, NSFilePresenter, Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = .init()
    
    init(url: URL) {
        self.presentedItemURL = url
    }
}

actor State {
    private var presenter: Presenter?
    
}

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

#Preview {
    ContentView()
}

@main
struct coordinator_testApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
