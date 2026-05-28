// swift-tools-version:6.0
import PackageDescription

// SuperBox64 SpriteKit — a Swift WebAssembly reimplementation of Apple's
// SpriteKit, plus drop-in shims for AppKit / UIKit / GameKit / GameplayKit /
// GameController / AVFoundation / AudioToolbox / Cocoa. A game written for
// macOS or iOS adds this package as a dependency, picks the modules it imports,
// and compiles to wasm32-wasip1 unchanged.
//
// The shim modules deliberately compile under Swift 5 language mode — their
// global singletons (UIScreen.main / NSScreen.main / GCController.current /
// GKLocalPlayer.local) mirror Apple's framework shape, and on the single-
// threaded wasm target there's no real concurrency to police.
let package = Package(
    name: "SuperBox64SpriteKit",
    products: [
        .library(name: "SpriteKit",      targets: ["SpriteKit"]),
        .library(name: "KitABI",         targets: ["KitABI"]),
        .library(name: "AppKit",         targets: ["AppKit"]),
        .library(name: "UIKit",          targets: ["UIKit"]),
        .library(name: "Cocoa",          targets: ["Cocoa"]),
        .library(name: "GameKit",        targets: ["GameKit"]),
        .library(name: "GameplayKit",    targets: ["GameplayKit"]),
        .library(name: "GameController", targets: ["GameController"]),
        .library(name: "AVFoundation",   targets: ["AVFoundation"]),
        .library(name: "AudioToolbox",   targets: ["AudioToolbox"]),
    ],
    targets: [
        .target(name: "KitABI"),
        .target(name: "SpriteKit",      dependencies: ["KitABI"]),
        .target(name: "AppKit",         dependencies: ["SpriteKit"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "UIKit",          dependencies: ["SpriteKit", "AppKit", "KitABI"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "Cocoa",          dependencies: ["AppKit"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "GameKit",        dependencies: ["SpriteKit", "UIKit", "KitABI"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "GameplayKit",    dependencies: ["SpriteKit"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "GameController", dependencies: ["SpriteKit", "KitABI"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "AVFoundation",   dependencies: ["SpriteKit", "KitABI"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "AudioToolbox",   swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
