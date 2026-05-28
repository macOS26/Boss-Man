// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SuperBox64SpriteKit",   // brand; vends module `SpriteKit` so games import unchanged
    products: [
        .library(name: "SpriteKit", targets: ["SpriteKit"]),
        .library(name: "AppKit", targets: ["AppKit"]),
        .library(name: "KitABI", targets: ["KitABI"]),
    ],
    targets: [
        .target(name: "KitABI"),
        .target(name: "SpriteKit", dependencies: ["KitABI"]),
        .target(name: "AppKit", dependencies: ["SpriteKit"]),
    ]
)
