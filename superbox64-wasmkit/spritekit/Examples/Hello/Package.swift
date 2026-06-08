// swift-tools-version:6.2
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
                .product(name: "SpriteKit",   package: "superbox64-spritekit"),
                .product(name: "Box2DBridge", package: "superbox64-spritekit"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)],
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
