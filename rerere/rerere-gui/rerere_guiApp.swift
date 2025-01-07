//
//  rerere_guiApp.swift
//  rerere-gui
//
//  Created by Nicholas Allegra on 11/27/24.
//  Copyright © 2024 Nicholas Allegra. All rights reserved.
//

import SwiftUI

@main
struct rerere_guiApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(test: buildTestTest(itemKind: .word, name: "貰う", testKind: .readingToMeaning))
        }
            .windowResizability(.contentSize)
            // setting an explicit defaultSize is needed to avoid insanity - todo: radar
            .defaultSize(width: 300, height: 100)
    }
}

