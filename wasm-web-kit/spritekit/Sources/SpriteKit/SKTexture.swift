import KitABI

public enum SKTextureFilteringMode { case nearest, linear }

public class SKTexture {
    let handle: Int32
    public var size: CGSize
    public var filteringMode: SKTextureFilteringMode = .linear   // honored later if we add a tex-state ABI
    public var usesMipmaps: Bool = false

    public init(imageNamed name: String) {
        handle = withUTF8Ptr(name) { img_by_name($0, $1) }
        size = .zero
    }
    init(handle: Int32) { self.handle = handle; size = .zero }

    // Apple exposes size as a property in modern Swift bindings; we keep it
    // as a property only (the historical -size() ObjC method collides).
    public func textureRect() -> CGRect { CGRect(x: 0, y: 0, width: 1, height: 1) }

    // Sub-region init (atlas slicing). Backend doesn't support sub-rects yet,
    // so we hand back the parent texture and record the rect for the future
    // gfx_draw_image call to crop.
    public convenience init(rect: CGRect, in parent: SKTexture) {
        self.init(handle: parent.handle); self.size = CGSize(width: rect.width, height: rect.height)
    }

    // Preload — assets are eager-loaded by the runtime's manifest, so these
    // resolve immediately. Match Apple's signatures so games using them work.
    public func preload(completionHandler h: @escaping () -> Void) { h() }
    public static func preload(_ textures: [SKTexture], withCompletionHandler h: @escaping () -> Void) { h() }

    // Normal-map / CIFilter derivations — return self on Canvas2D (we don't
    // run a lighting pass or a filter chain).
    public func generatingNormalMap() -> SKTexture { self }
    public func generatingNormalMap(withSmoothness s: CGFloat, contrast c: CGFloat) -> SKTexture { self }
    public func applying(_ filter: AnyObject) -> SKTexture { self }
}

// SKMutableTexture — dynamic pixels written by the game (CPU pixel buffer).
// Backed by an in-memory RGBA buffer on the Swift side; calling modifyPixelData
// hands the game a writable raw pointer. Future ABI extension can push the
// buffer through the runtime to a Canvas ImageData for actual display.
public final class SKMutableTexture: SKTexture {
    var pixelBuffer: [UInt8]
    public init(size: CGSize) {
        let w = Int(size.width), h = Int(size.height)
        self.pixelBuffer = [UInt8](repeating: 0, count: max(0, w * h * 4))
        super.init(handle: -1); self.size = size
    }
    public func modifyPixelData(_ block: (UnsafeMutableRawPointer?, Int) -> Void) {
        let count = pixelBuffer.count
        pixelBuffer.withUnsafeMutableBytes { raw in
            block(raw.baseAddress, count)
        }
    }
}
