//
//  rerere_guiTests.swift
//  rerere-guiTests
//
//  Created by Nicholas Allegra on 11/27/24.
//  Copyright © 2024 Nicholas Allegra. All rights reserved.
//

import Testing

@testable import rerere_gui

struct rerere_guiTests {

    @Test func testLevenshtein() async throws {
        var l = Levenshtein()
        #expect(l.distance(between: "xcheese", and: "cheesex") == 2)
    }

}
