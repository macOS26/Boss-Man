// swift-tools-version:6.0
import PackageDescription

// SuperBox64 SpriteKit — a Swift WebAssembly reimplementation of Apple's
// SpriteKit, plus drop-in shims for AppKit / UIKit / GameKit / GameplayKit /
// GameController / AVFoundation / AudioToolbox / Cocoa. A game written for
// macOS or iOS adds this package as a dependency, picks the modules it imports,
// and compiles to wasm32-wasip1 unchanged.
//
// Everything compiles under Swift 6 language mode. The Apple-mirror global
// singletons (UIScreen.main / NSScreen.main / GKLocalPlayer.local / etc.) are
// marked nonisolated(unsafe): the wasm target is single-threaded, so there is
// no real concurrency to police, but the keyword is required for v6 to accept
// the mutable shared globals.
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
        .library(name: "Box2DBridge",    targets: ["Box2DBridge"]),
        .library(name: "Combine",        targets: ["Combine"]),
        .library(name: "SwiftUI",        targets: ["SwiftUI"]),
    ],
    targets: [
        // Box2D 2.4.1 wrapped in a tiny C ABI (cb_add_box / cb_step / etc.) so
        // SwiftPM builds and links libcbox2d for every consumer — no more
        // hand-rolled .a in each game's repo. Header search paths cover the
        // three private subdirs Box2D's .cpp files cross-reference.
        .target(
            name: "Box2DBridge",
            path: "Sources/Box2DBridge",
            exclude: [],
            sources: ["box2d-src", "cbox2d.cpp"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("box2d-src"),
                .headerSearchPath("box2d-src/dynamics"),
                .headerSearchPath("box2d-src/collision"),
                .headerSearchPath("box2d-src/common"),
                .headerSearchPath("box2d-src/rope"),
                // Strip C++ exceptions so we don't leak __cxa_throw /
                // __cxa_allocate_exception into the wasm import list. The
                // runtime doesn't host a C++ unwinder and Box2D's hot paths
                // don't actually throw — exceptions only sneak in through
                // std::vector::push_back's bad_alloc edge case.
                .unsafeFlags(["-fno-exceptions"]),
            ]
        ),
        .target(name: "KitABI"),
        .target(name: "SpriteKit",      dependencies: ["KitABI"]),
        .target(name: "AppKit",         dependencies: ["SpriteKit"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "UIKit",          dependencies: ["SpriteKit", "AppKit", "KitABI"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "Cocoa",          dependencies: ["AppKit"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "GameKit",        dependencies: ["SpriteKit", "UIKit", "KitABI"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "GameplayKit",    dependencies: ["SpriteKit", "KitABI"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "GameController", dependencies: ["SpriteKit", "KitABI"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "AVFoundation",   dependencies: ["SpriteKit", "KitABI"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "AudioToolbox",   swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "Combine",        swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "SwiftUI",        dependencies: ["Combine", "SpriteKit"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
