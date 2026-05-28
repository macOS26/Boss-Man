import SpriteKit
import KitABI

// Reactor-mode wasm entry. The runtime loads us with WASI mode `reactor` so
// _initialize() runs once (libc/libc++ ctors + Swift runtime setup), then
// `boot` is called once to bring the SKView + first scene up, and `frame`
// fires every animation frame with the dt in milliseconds.
//
// SpriteKit games written for macOS/iOS don't have explicit boot/frame
// entrypoints — they use @main App or NSApplicationDelegate. On wasm the kit
// drives the frame loop directly, so we expose those two exports and stash
// the SKView in a nonisolated(unsafe) global. The single-threaded wasm event
// loop makes the !-marked global safe.
//
// Logical render size matches the original macOS Boss-Man: 1183 x 665.44. We
// round up to 1184 x 666 so it lines up on integer pixels at devicePixelRatio
// 1 and 2; the kit's letterbox handles the actual display scale.

nonisolated(unsafe) var view: SKView? = nil

@_cdecl("boot")
public func boot() {
    let size = CGSize(width: 1184, height: 666)
    let v = SKView()
    v.showsFPS = false
    v.shouldCullNonVisibleNodes = true
    v.preferredFramesPerSecond = 60
    v.ignoresSiblingOrder = true
    v.allowsTransparency = true

    let title = TitleScene(size: size)
    title.scaleMode = .aspectFit
    v.presentScene(title)
    view = v
}

@_cdecl("frame")
public func frame(_ dtMs: Double) {
    view?.tick(dtMs)
}
