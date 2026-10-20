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
    ],
    targets: [
        .executableTarget(
            name: "Termos",
            dependencies: [
                "SwiftTerm",
                .product(name: "CodeEditSourceEditor", package: "CodeEditSourceEditor"),
                .product(name: "CodeEditLanguages", package: "CodeEditLanguages"),
            ],
            path: "Sources/Termos",
            exclude: ["Resources/AppIcon.png"],
            resources: [.copy("Resources/AppIcon.icns")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
