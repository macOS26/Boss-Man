import KitABI

// SpriteKit's "camera" is just an SKNode the scene treats specially: the
// rendered world is translated/rotated/scaled by the camera's inverse so the
// camera position appears in the centre. We honor position, zRotation, and
// xScale/yScale; childNode hit-testing in scene space is unchanged.
//
// SKView.render() applies the inverse before rendering the scene tree:
//   translate(-cam.position) -> rotate(-cam.zRotation) -> scale(1/sx, 1/sy)
//
// The camera node itself is still a regular SKNode and can hold UI overlays
// in its child tree — they ride along with the camera as you'd expect.
public final class SKCameraNode: SKNode {
    public override init() { super.init() }

    // Convenience: rectangle (in scene coordinates) currently visible to this
    // camera, assuming the scene's view size.
    public func containsInFrustum(_ node: SKNode) -> Bool {
        guard let scene = self.scene else { return false }
        let visible = visibleRect(in: scene)
        let p = node.absolutePosition()
        return visible.contains(p)
    }

    public func visibleRect(in scene: SKScene) -> CGRect {
        let w = scene.size.width / max(xScale, 0.0001)
        let h = scene.size.height / max(yScale, 0.0001)
        return CGRect(x: position.x - w / 2, y: position.y - h / 2, width: w, height: h)
    }

    public func containsPoint(_ point: CGPoint) -> Bool {
        guard let scene = self.scene else { return false }
        return visibleRect(in: scene).contains(point)
    }
}
