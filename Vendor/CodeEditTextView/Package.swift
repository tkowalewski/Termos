// swift-tools-version: 5.9

// CodeEditTextView 0.12.1 (https://github.com/CodeEditApp/CodeEditTextView) with a fix
// applied, see README.md. Lint plugin and tests are left out.

import PackageDescription

let package = Package(
    name: "CodeEditTextView",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "CodeEditTextView",
            targets: ["CodeEditTextView"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ChimeHQ/TextStory",
            from: "0.9.0"
        ),
        .package(
            url: "https://github.com/apple/swift-collections.git",
            .upToNextMajor(from: "1.0.0")
        ),
    ],
    targets: [
        .target(
            name: "CodeEditTextView",
            dependencies: [
                "TextStory",
                .product(name: "Collections", package: "swift-collections"),
                "CodeEditTextViewObjC"
            ]
        ),
        .target(
            name: "CodeEditTextViewObjC",
            publicHeadersPath: "include"
        ),
    ]
)
