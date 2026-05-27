// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BossManSpriteKitWeb",
    dependencies: [ .package(path: "../wasm-web-kit/spritekit") ],
    targets: [
        .executableTarget(
            name: "Demo",
            dependencies: [ .product(name: "SpriteKit", package: "spritekit") ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xclang-linker", "-mexec-model=reactor",
                    "-Xlinker", "--export=boot",
                    "-Xlinker", "--export=frame",
                    "-Xlinker", "--export-if-defined=_initialize",
                    "-Xlinker", "--allow-undefined",
                    "-Xlinker", "/Users/toddbruss/Documents/GitHub/BossMan/boss-man-spritekit-web/native/libcbox2d.a",
                ])
            ]
        )
    ]
)
