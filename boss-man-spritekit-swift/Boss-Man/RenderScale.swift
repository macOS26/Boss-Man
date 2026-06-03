import SpriteKit
import AppKit

// Single home for the platform render-scale knobs, so the rest of the game reads
// clean (no inline #if scattered through the visuals).
//
// Apple SpriteKit caches each SKShapeNode/SKLabelNode to a bitmap that the maze
// camera magnifies (and the fullscreen aspectFit upscales), so Apple art is
// supersampled: built `factor` times larger inside a node scaled back down by the
// same factor, and the maze sheet is baked at the display's pixel density. WASM
// redraws every node live at the final resolution each frame, so it never caches
// and needs none of this -- every knob collapses to 1 there.
enum RenderScale {
    #if os(macOS)
    static let factor: CGFloat = 8
    #else
    static let factor: CGFloat = 1
    #endif

    // Maze-sheet bake scale. Apple bakes at the full screen's pixel density times
    // the maze zoom (full screen, not the window, so a windowed->fullscreen toggle
    // never leaves a soft sheet), capped to bound the texture. WASM bakes 1:1.
    static func mazeBake(sceneWidth: CGFloat, zoom: CGFloat) -> CGFloat {
        #if os(macOS)
        let displayW = NSScreen.main?.frame.width ?? sceneWidth
        return min(5, max(zoom, displayW / max(1, sceneWidth) * zoom))
        #else
        return 1
        #endif
    }
}
