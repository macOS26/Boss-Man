import SpriteKit
import KitABI

// Reactor-mode wasm entry. The runtime loads us in WASI `reactor` mode, so
// _initialize() runs once (libc/libc++ ctors + Swift runtime setup), then
// `boot` brings the SKView and first scene up, and `frame` fires once per
// animation frame with the elapsed dt in milliseconds.
//
// macOS/iOS SpriteKit games have no explicit boot/frame entry (they use @main
// App or NSApplicationDelegate). On wasm the kit drives the loop, so we export
// just those two functions and keep the SKView in a nonisolated(unsafe) global;
// the single-threaded wasm event loop makes that unsynchronised global safe.
//
// The logical render size matches the original macOS Boss-Man, rounded up to
// whole pixels so it lands on integer coordinates at any devicePixelRatio; the
// kit's letterbox handles the actual display scale.

nonisolated(unsafe) var view: SKView? = nil

@_cdecl("boot")
public nonisolated func boot() {
    MainActor.assumeIsolated {
        let size = CGSize(width: 1184, height: 666)
        let v = SKView()
        v.showsFPS = true
        v.shouldCullNonVisibleNodes = true
        v.preferredFramesPerSecond = 60
        v.ignoresSiblingOrder = true
        v.allowsTransparency = true

        let title = TitleScene(size: size)
        title.scaleMode = .aspectFit
        v.presentScene(title)
        view = v
    }
}

@_cdecl("frame")
public nonisolated func frame(_ dtMs: Double) {
    MainActor.assumeIsolated { view?.tick(dtMs) }
}

// MARK: - TileMover conformances
// The kit's tile-movement protocols are wasm-only and this game's grid types
// already satisfy them, so these conformances are empty. They live here rather
// than in the common type files to stay out of the apple build.
extension GridMap: TileMap {}
extension MoveDirection: TileDirection {}
extension PixelPerson: TileWalkAnimating {}
