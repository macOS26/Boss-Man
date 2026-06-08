// swift-tools-version: 6.2
import PackageDescription

// Boss-Man, SpriteKit edition, on wasm.
//
// This is a port of the original macOS Boss-Man SpriteKit game
// (../boss-man-spritekit-swift) to WebAssembly via the SuperBox64 SpriteKit
// reimplementation. The game's `import SpriteKit` lines work unchanged here:
// SuperBox64 SpriteKit vends a module named SpriteKit so source written for
// Apple's framework drops in. Box2D ships with the package as Box2DBridge.
//
// Build with `./build.sh` (debug) or `./build.sh release`. The resulting
// BossMan.wasm is loaded by web/index.html alongside the kit's runtime.js.
let package = Package(
    name: "BossManSpriteKit",
    dependencies: [
        .package(url: "https://github.com/macOS26/superbox64-spritekit", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "BossMan",
            dependencies: [
                .product(name: "SpriteKit",      package: "superbox64-spritekit"),
                .product(name: "KitABI",         package: "superbox64-spritekit"),
                .product(name: "Box2DBridge",    package: "superbox64-spritekit"),
                .product(name: "AppKit",         package: "superbox64-spritekit"),
                .product(name: "GameKit",        package: "superbox64-spritekit"),
                .product(name: "GameController", package: "superbox64-spritekit"),
                .product(name: "AVFoundation",   package: "superbox64-spritekit"),
            ],
            swiftSettings: [
                // Match Apple's implicit model: the game is @MainActor by
                // default, so apple source (which is @MainActor) compiles
                // unchanged. The @_cdecl boot/frame entry points opt out with
                // `nonisolated` and bridge in via MainActor.assumeIsolated.
                .defaultIsolation(MainActor.self),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xclang-linker", "-mexec-model=reactor",
                    "-Xlinker", "--export=boot",
                    "-Xlinker", "--export=frame",
                    "-Xlinker", "--export-if-defined=_initialize",
                    "-Xlinker", "--allow-undefined",
                ]),
            ]
        ),
    ]
)
