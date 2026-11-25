// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Notchcord",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Notchcord", path: "Sources/Notchcord")
    ]
)
