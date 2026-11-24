// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WissenApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WissenApp",
            path: "Sources/WissenApp",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
