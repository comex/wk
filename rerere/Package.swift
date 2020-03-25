// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "rerere",
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "rerere",
            dependencies: ["Yams"],
            path: "rerere/",
            sources: [
                "main.swift",
                "Levenshtein.swift",
            ]),
    ]
)
