// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Florestan",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "FlorestanCore"),
        .executableTarget(
            name: "Florestan",
            dependencies: ["FlorestanCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "FlorestanCoreTests", dependencies: ["FlorestanCore"]),
    ]
)
