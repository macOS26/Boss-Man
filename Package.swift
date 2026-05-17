// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Boss-Man",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Boss-Man", targets: ["Boss-Man"])
    ],
    targets: [
        .executableTarget(
            name: "Boss-Man",
            path: "Sources/Boss-Man"
        )
    ]
)
