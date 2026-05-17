// swift-tools-version: 6.2
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
            path: "Sources/Boss-Man",
            resources: [.process("Resources")],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist"
                ])
            ]
        )
    ]
)
