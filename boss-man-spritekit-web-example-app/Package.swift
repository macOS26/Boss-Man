// swift-tools-version:6.0
import PackageDescription

// The demo links Box2DBridge from the SuperBox64 SpriteKit package — no more
// hand-rolled libcbox2d.a in native/. Reactor-mode linker flags export the two
// entrypoints the wasm runtime calls each frame.
let package = Package(
    name: "BossManSpriteKitWeb",
    dependencies: [ .package(path: "../wasm-web-kit/spritekit") ],
    targets: [
        .executableTarget(
            name: "Demo",
            dependencies: [
                .product(name: "SpriteKit",   package: "spritekit"),
                .product(name: "Box2DBridge", package: "spritekit"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xclang-linker", "-mexec-model=reactor",
                    "-Xlinker", "--export=boot",
                    "-Xlinker", "--export=frame",
                    "-Xlinker", "--export-if-defined=_initialize",
                    "-Xlinker", "--allow-undefined",
                ])
            ]
        )
    ]
)
