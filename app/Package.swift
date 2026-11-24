// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TidywiseApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TidywiseApp",
            path: "Sources/TidywiseApp",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
