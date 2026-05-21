// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacResourceWidget",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacResourceWidget",
            path: "Sources/MacResourceWidget"
        )
    ]
)
