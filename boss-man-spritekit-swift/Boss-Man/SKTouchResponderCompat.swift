#if os(macOS)
import CoreGraphics

// macOS counterpart to the SuperBox64 SpriteKit SKTouchResponder protocol. The
// wasm framework delivers per-finger multi-touch through it, macOS has no touch
// hardware, so nothing calls these here, but declaring the same protocol lets
// the scene's conformance compile from one common source.
protocol SKTouchResponder: AnyObject {
    func touchBegan(finger: Int, at p: CGPoint)
    func touchMoved(finger: Int, at p: CGPoint)
    func touchEnded(finger: Int, at p: CGPoint)
}
#endif
