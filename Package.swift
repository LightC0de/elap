// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ELAP",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "ELAPCore",
            path: "Sources/ELAPCore",
            plugins: ["BuildNumberPlugin"]
        ),
        .executableTarget(
            name: "ELAP",
            dependencies: [
                "ELAPCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/ELAP"
        ),
        .testTarget(
            name: "ELAPTests",
            dependencies: ["ELAP", "ELAPCore"],
            path: "Tests/ELAPTests"
        ),
        .plugin(
            name: "BuildNumberPlugin",
            capability: .buildTool(),
            path: "Plugins/BuildNumberPlugin"
        )
    ]
)
