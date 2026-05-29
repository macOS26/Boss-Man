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
        .package(path: "../wasm-web-kit/spritekit"),
    ],
    targets: [
        .executableTarget(
            name: "BossMan",
            dependencies: [
                .product(name: "SpriteKit",      package: "spritekit"),
                .product(name: "KitABI",         package: "spritekit"),
                .product(name: "Box2DBridge",    package: "spritekit"),
                .product(name: "AppKit",         package: "spritekit"),
                .product(name: "GameKit",        package: "spritekit"),
                .product(name: "GameController", package: "spritekit"),
                .product(name: "AVFoundation",   package: "spritekit"),
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
