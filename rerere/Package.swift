// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "rerere-cli",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "rerere-cli",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: ".",
            exclude: [
                "rerere-gui",
                "rerere-guiTests",
                "rerere-guiUITests",
            ],
            sources: [
                "rerere/rerere.swift",
                "rerere/buffers.swift",
                "rerere/Levenshtein.swift",
                "rerere-cli/main.swift",
            ],
            cSettings: [
                .headerSearchPath("rerere-c"),
            ]
        ),
    ]
)
