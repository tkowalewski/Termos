// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Termos",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Termos", targets: ["Termos"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.9.0"),
        .package(url: "https://github.com/CodeEditApp/CodeEditSourceEditor", from: "0.15.2"),
        .package(url: "https://github.com/CodeEditApp/CodeEditLanguages", from: "0.1.20"),
        .package(url: "https://github.com/swiftlang/swift-cmark", from: "0.9.0"),
        // Patched copy that replaces the version CodeEditSourceEditor depends on (see its README).
        .package(path: "Vendor/CodeEditTextView"),
    ],
    targets: [
        .executableTarget(
            name: "Termos",
            dependencies: [
                "SwiftTerm",
                .product(name: "CodeEditSourceEditor", package: "CodeEditSourceEditor"),
                .product(name: "CodeEditLanguages", package: "CodeEditLanguages"),
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            path: "Sources/Termos",
            exclude: ["Resources/AppIcon.png"],
            resources: [.copy("Resources/AppIcon.icns")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
