// swift-tools-version:6.0
import PackageDescription

// Smallest possible SuperBox64 SpriteKit consumer. Builds to wasm32-wasip1
// and exports boot/frame so the kit's runtime.js can drive it.
let package = Package(
    name: "Hello",
    dependencies: [
        .package(path: "../.."),    // pulls in SuperBox64 SpriteKit + Box2DBridge
    ],
    targets: [
        .executableTarget(
            name: "Hello",
            dependencies: [
                .product(name: "SpriteKit",   package: "spritekit"),
                .product(name: "Box2DBridge", package: "spritekit"),
            ],
            linkerSettings: [.unsafeFlags([
                "-Xclang-linker", "-mexec-model=reactor",
                "-Xlinker", "--export=boot",
                "-Xlinker", "--export=frame",
                "-Xlinker", "--export-if-defined=_initialize",
                "-Xlinker", "--allow-undefined",
            ])]
        )
    ]
)
