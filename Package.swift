// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BossMan",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BossMan", targets: ["BossMan"])
    ],
    targets: [
        .executableTarget(
            name: "BossMan",
            path: "Sources/BossMan"
        )
    ]
)
