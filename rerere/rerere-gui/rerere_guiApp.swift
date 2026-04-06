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
    @FocusState var isInputFocused: Bool
    var body: some Scene {
        WindowGroup {
            ContentView(isInputFocused: $isInputFocused)
                .defaultFocus($isInputFocused, true, priority: .userInitiated)
        }
            .windowResizability(.contentMinSize)
            // setting an explicit defaultSize is needed to avoid insanity - todo: radar
            .defaultSize(width: 300, height: 100)
    }
}

