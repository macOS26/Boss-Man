// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SpriteKitWeb",
    products: [
        .library(name: "SpriteKit", targets: ["SpriteKit"]),
        .library(name: "KitABI", targets: ["KitABI"]),
    ],
    targets: [
        .target(name: "KitABI"),
        .target(name: "SpriteKit", dependencies: ["KitABI"]),
    ]
)
