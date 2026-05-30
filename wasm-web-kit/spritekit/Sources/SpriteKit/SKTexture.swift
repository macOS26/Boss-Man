import KitABI

public enum SKTextureFilteringMode { case nearest, linear }

// Nil-returning variant of SKTexture(imageNamed:). The base initializer always
// hands back a texture (handle 0 / placeholder) so an SKSpriteNode can retry
// once a preload finishes; call sites that instead want to FALL BACK when an
// image isn't registered (e.g. draw an emoji label instead of a sprite) need
// this. Reusable by any ported game, so the texture-presence workaround lives
// here in the framework rather than each game.
public func textureNamed(_ name: String) -> SKTexture? {
    let t = SKTexture(imageNamed: name)
    return (t.isLoaded && t.size.width > 0 && t.size.height > 0) ? t : nil
}

public class SKTexture {
    public internal(set) var handle: Int32
    // The asset name we were constructed with — if any. Stored so that when
    // the manifest preloader registers an image after this SKTexture was
    // already built, we can retry the lookup on the next draw. Without this,
    // an SKSpriteNode created during boot() before the asset has loaded
    // would permanently render with handle 0 (i.e. invisible).
    var pendingName: String? = nil

    // True once the runtime has registered the backing image. Re-resolves
    // pendingName on every read so call sites get fresh state as preloads
    // finish.
    public var isLoaded: Bool {
        if handle > 0 { return true }
        return resolvePending() > 0
    }
    public var size: CGSize
    public var filteringMode: SKTextureFilteringMode = .linear
    public var usesMipmaps: Bool = false
    var sourceRect: CGRect = .zero

    public init(imageNamed name: String) {
        let h = withUTF8Ptr(name) { img_by_name($0, $1) }
        handle = h
        pendingName = h == 0 ? name : nil
        size = .zero
        if h > 0 { populateSize() }
    }
    init(handle: Int32) {
        self.handle = handle; size = .zero
        if handle > 0 { populateSize() }
    }

    // Called by anyone that needs a handle: SKSpriteNode.draw, SKView.texture.
    // Resolves a deferred name lookup the first time the runtime has the
    // asset registered. Also populates `size` so call sites can read the
    // natural image dimensions without guessing.
    @discardableResult
    func resolvePending() -> Int32 {
        if handle > 0 { return handle }
        guard let name = pendingName else { return 0 }
        let h = withUTF8Ptr(name) { img_by_name($0, $1) }
        if h > 0 { handle = h; pendingName = nil; populateSize() }
        return h
    }

    private func populateSize() {
        let w = img_width(handle)
        let h = img_height(handle)
        if w > 0 && h > 0 { size = CGSize(width: CGFloat(w), height: CGFloat(h)) }
    }

    // Apple exposes size as a property in modern Swift bindings; we keep it
    // as a property only (the historical -size() ObjC method collides).
    public func textureRect() -> CGRect {
        if sourceRect == .zero { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return sourceRect
    }

    // Sub-region init (atlas slicing). Hands back the parent's handle but
    // remembers the source rect; SKSpriteNode.draw reads `sourceRect` and
    // forwards it to gfx_draw_image.
    public convenience init(rect: CGRect, in parent: SKTexture) {
        self.init(handle: parent.handle)
        self.sourceRect = rect
        self.size = CGSize(width: rect.width, height: rect.height)
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

// SKMutableTexture — dynamic pixels written by the game. Backed by an
// in-memory RGBA buffer on the Swift side; modifyPixelData hands the game a
// writable raw pointer, then pushes the result through gfx_upload_pixels so
// subsequent gfx_draw_image calls render the updated pixels. The image
// handle is allocated up front via a 1×1 placeholder so the runtime has a
// slot to upload into.
public final class SKMutableTexture: SKTexture {
    var pixelBuffer: [UInt8]
    let pixelWidth: Int
    let pixelHeight: Int

    public init(size: CGSize) {
        let w = max(1, Int(size.width)), h = max(1, Int(size.height))
        self.pixelWidth = w; self.pixelHeight = h
        self.pixelBuffer = [UInt8](repeating: 0, count: w * h * 4)
        // Allocate the image slot up front by pushing the all-transparent
        // initial buffer; gfx_upload_pixels(0, ...) returns a fresh handle.
        let id = pixelBuffer.withUnsafeBufferPointer { buf -> Int32 in
            gfx_upload_pixels(0, Int32(w), Int32(h), buf.baseAddress, Int32(buf.count))
        }
        super.init(handle: id)
        self.size = CGSize(width: CGFloat(w), height: CGFloat(h))
    }
    public init(size: CGSize, pixelFormat: Int) { fatalError("init not supported") }

    public func modifyPixelData(_ block: (UnsafeMutableRawPointer?, Int) -> Void) {
        let count = pixelBuffer.count
        pixelBuffer.withUnsafeMutableBytes { raw in
            block(raw.baseAddress, count)
        }
        pushToRuntime()
    }
    // Force an upload of the current buffer — useful when game code has been
    // poking pixelBuffer directly through unsafe raw access.
    public func reload() { pushToRuntime() }

    private func pushToRuntime() {
        _ = pixelBuffer.withUnsafeBufferPointer { buf in
            gfx_upload_pixels(handle, Int32(pixelWidth), Int32(pixelHeight),
                              buf.baseAddress, Int32(buf.count))
        }
    }
}
