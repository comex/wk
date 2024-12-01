//
//  rerere_guiTests.swift
//  rerere-guiTests
//
//  Created by Nicholas Allegra on 11/27/24.
//  Copyright © 2024 Nicholas Allegra. All rights reserved.
//

import Testing
import Foundation
@testable import rerere_gui

struct rerere_guiTests {

    @Test func testLevenshtein() async throws {
        var l = Levenshtein()
        #expect(l.distance(between: "xcheese", and: "cheesex") == 2)
    }
    
    @Test func testBlockOn() {
        let x = blockOnLikeYoureNotSupposedTo {
            try! await Task.sleep(nanoseconds: 1000000)
            return 42
        }
        #expect(x == 42)
    }

    @Test func testFixKana() async {
        await MainActor.run { () -> Void in
            let oldText = "f00xtsubarchi3"
            let oldIndices = Array(oldText.indices)
            var newIndices = oldIndices
            var newText = oldText
            fixKana(&newText) { (fixIndex) -> Void in
                newIndices = newIndices.map {
                    let new = fixIndex($0)
                    return new
                }
            }
            for i in 0..<oldIndices.count {
                let oldIndex = oldIndices[i]
                let newIndex = newIndices[i]
                let oldChar = String(oldText[oldIndex])
                let newChar = String(newText[newIndex])
                let exp: String
                switch oldChar {
                case "x":
                    exp = "っ"
                case "t", "s", "u", "b":
                    exp = "ば"
                case "a":
                    exp = "r"
                case "c":
                    exp = "ち"
                case "h", "i":
                    exp = "3"
                default:
                    exp = oldChar
                }
                assert(newChar == exp)
                #expect(newChar == exp)
            }
        }
    }
}
