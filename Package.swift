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
            resources: [
                .process("Resources/RedStapler.svg"),
                // AppIcon.icon is an Icon Composer bundle (macOS Tahoe).
                // SwiftPM can't compile it, so copy it verbatim and we load
                // the source SVG inside at runtime as the Dock icon.
                .copy("Resources/AppIcon.icon")
            ],
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
