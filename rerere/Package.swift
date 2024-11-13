// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "rerere",
    platforms: [
        .macOS(.v12),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.6"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
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
