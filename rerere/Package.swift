// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "rerere",
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "rerere",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "rerere/",
            sources: [
                "main.swift",
                "Levenshtein.swift",
            ],
            cSettings: [
                .headerSearchPath("../rerere-c"),
            ]
        ),
    ]
)
