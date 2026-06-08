import KitABI

// SK3DNode — SpriteKit's host for SceneKit scenes. Without SceneKit on web
// we don't run a real 3D scene graph; instead the runtime exposes a minimal
// WebGL2 viewport (gfx_3d_draw_billboard) that renders the supplied texture
// as a perspective-projected quad sized by the camera distance. Enough to
// compile + visibly render for games using SK3DNode for splash billboards or
// simple HUD ornaments. A full SCNScene shim is out of scope.
public final class SK3DNode: SKNode {
    public var viewportSize: CGSize
    public var scnScene: AnyObject?           // SCNScene stand-in (untyped)
    public var pointOfView: AnyObject?        // SCNNode stand-in
    public var isPlaying: Bool = true
    public var loops: Bool = false
    public var autoenablesDefaultLighting: Bool = false
    public var playbackSpeed: CGFloat = 1
    // Optional texture rendered as the billboard contents.
    public var contentTexture: SKTexture?
    // Stand-in for camera position; default behind the origin looking +z.
    public var cameraPosition = CGVector3(x: 0, y: 0, z: 1)

    public init(viewportSize: CGSize) {
        self.viewportSize = viewportSize
        super.init()
    }

    public override var frame: CGRect {
        CGRect(x: position.x - viewportSize.width  / 2,
               y: position.y - viewportSize.height / 2,
               width: viewportSize.width, height: viewportSize.height)
    }

    override func draw(alpha: CGFloat) {
        guard let t = contentTexture, t.handle != 0 else { return }
        let w = Float(viewportSize.width), h = Float(viewportSize.height)
        gfx_set_alpha(Float(alpha))
        gfx_save()
        gfx_scale(1, -1)
        gfx_3d_draw_billboard(t.handle,
                              Float(cameraPosition.x), Float(cameraPosition.y), Float(cameraPosition.z),
                              -w / 2, -h / 2, w, h, 0xFFFFFFFF)
        gfx_restore()
    }
}

// Tiny 3-component vector — used by SK3DNode for camera coords without
// pulling SceneKit / simd. Matches Apple's vector_float3 in shape.
public struct CGVector3: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var z: CGFloat
    public init(x: CGFloat = 0, y: CGFloat = 0, z: CGFloat = 0) {
        self.x = x
        self.y = y
        self.z = z
    }
    public static let zero = CGVector3()
}

