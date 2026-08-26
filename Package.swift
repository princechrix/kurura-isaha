// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KururaIsaha",
    platforms: [.macOS(.v14)],
    targets: [
        // Everything that can be reasoned about without a menu bar attached: the pull
        // scaling curve, duration parsing, and the wire format the CLI speaks.
        .target(
            name: "KururaCore",
            path: "Sources/KururaCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "KururaIsaha",
            dependencies: ["KururaCore"],
            path: "Sources/KururaIsaha",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "kurura",
            dependencies: ["KururaCore"],
            path: "Sources/kurura",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KururaCoreTests",
            dependencies: ["KururaCore"],
            path: "Tests/KururaCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
