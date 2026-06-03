// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BossManDesktop",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BossManDesktop",
            path: "Sources/BossManDesktop"
        )
    ]
)
