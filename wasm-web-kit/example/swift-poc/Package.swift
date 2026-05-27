// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "poc",
    targets: [
        .target(name: "cabi"),
        .executableTarget(
            name: "poc",
            dependencies: ["cabi"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xclang-linker", "-mexec-model=reactor",
                    "-Xlinker", "--export=boot",
                    "-Xlinker", "--export=frame",
                    "-Xlinker", "--export-if-defined=_initialize",
                    "-Xlinker", "--allow-undefined",
                    "-Xlinker", "/Users/toddbruss/Documents/GitHub/BossMan/wasm-web-kit/example/swift-poc/native/libcbox2d.a",
                ])
            ]
        )
    ]
)
