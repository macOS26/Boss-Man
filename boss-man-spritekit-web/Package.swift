// swift-tools-version: 6.2
import PackageDescription

// Boss-Man, SpriteKit edition, on wasm.
//
// This is a port of the original macOS Boss-Man SpriteKit game
// (../boss-man-spritekit-swift) to WebAssembly via the SuperBox64 SpriteKit
// reimplementation. The game's `import SpriteKit` lines work unchanged here:
// SuperBox64 SpriteKit vends a module named SpriteKit so source written for
// Apple's framework drops in. Box2D v3 (pure C) ships inside the package; SpriteKit links it directly.
//
// Build with `./build.sh` (debug) or `./build.sh release`. The resulting
// BossMan.wasm is loaded by web/index.html alongside the kit's runtime.js.
let package = Package(
    name: "BossManSpriteKit",
    dependencies: [
        .package(url: "https://github.com/SuperBox64/SuperBox64Kit", branch: "embedded"),
    ],
    targets: [
        .executableTarget(
            name: "BossMan",
            dependencies: [
                .product(name: "SpriteKit",      package: "SuperBox64Kit"),
                .product(name: "KitABI",         package: "SuperBox64Kit"),
                .product(name: "AppKit",         package: "SuperBox64Kit"),
                .product(name: "GameKit",        package: "SuperBox64Kit"),
                .product(name: "GameController", package: "SuperBox64Kit"),
                .product(name: "AVFoundation",   package: "SuperBox64Kit"),
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
