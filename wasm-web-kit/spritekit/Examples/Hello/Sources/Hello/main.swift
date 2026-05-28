import SpriteKit

// Smallest-possible SuperBox64 SpriteKit demo: a moving sprite + label.
// Build with: TOOLCHAINS=org.swift.6.3.2-release xcrun --toolchain swift \
//   swift build --swift-sdk swift-6.3.2-RELEASE_wasm -c release
// The resulting Hello.wasm is loaded by web/index.html alongside runtime.js.

final class HelloScene: SKScene {
    static let logical = CGSize(width: 1184, height: 666)

    let pete = SKSpriteNode(color: .yellow, size: CGSize(width: 64, height: 64))
    let title = SKLabelNode(text: "SuperBox64 SpriteKit · Hello")

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        size = HelloScene.logical

        title.fontSize = 28
        title.position = CGPoint(x: size.width / 2, y: size.height - 60)
        addChild(title)

        pete.position = CGPoint(x: 80, y: size.height / 2)
        addChild(pete)

        // Travel side to side forever, easing.
        let go  = SKAction.moveTo(x: size.width - 80, duration: 1.6)
        let bk  = SKAction.moveTo(x: 80,              duration: 1.6)
        go.timingMode = .easeInEaseOut
        bk.timingMode = .easeInEaseOut
        pete.run(.repeatForever(.sequence([go, bk])))

        // A gentle 360° spin in parallel.
        pete.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 4)))
    }

    override func keyDown(_ key: Int) {
        // 36 = Escape in the kit's SF key mapping. On wasm there's no exit
        // pathway from the page, so we just remove the sprite as a visible
        // acknowledgement.
        if key == 36 { pete.removeFromParent() }
    }
}

nonisolated(unsafe) var view: SKView?

@_cdecl("boot")
public func boot() {
    let v = SKView()
    v.presentScene(HelloScene(size: HelloScene.logical))
    view = v
}

@_cdecl("frame")
public func frame(_ ms: Double) { view?.tick(ms) }
