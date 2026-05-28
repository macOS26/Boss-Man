// swift-tools-version:6.0
import PackageDescription

// sks2json — macOS-only CLI that uses Apple's SpriteKit to load a .sks
// scene/particle file and emit the portable JSON the SuperBox64 SpriteKit
// runtime loader (SKSceneLoader) consumes.
let package = Package(
    name: "sks2json",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "sks2json",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
