import KitABI

public enum SKTextureFilteringMode { case nearest, linear }

public class SKTexture {
    public internal(set) var handle: Int32
    // True when the runtime has the backing image registered. Games use this
    // to fall back to a procedural placeholder when an asset hasn't loaded
    // (or is missing from manifest.json).
    public var isLoaded: Bool { handle > 0 }
    public var size: CGSize
    public var filteringMode: SKTextureFilteringMode = .linear   // honored later if we add a tex-state ABI
    public var usesMipmaps: Bool = false
    // Sub-region (atlas slicing). When non-zero, draws pull only the
    // rectangle (sourceX, sourceY, sourceW, sourceH) out of the parent
    // image. Coordinates are in source pixels, matching gfx_draw_image's
    // sx/sy/sw/sh arguments.
    var sourceRect: CGRect = .zero

    public init(imageNamed name: String) {
        handle = withUTF8Ptr(name) { img_by_name($0, $1) }
        size = .zero
    }
    init(handle: Int32) { self.handle = handle; size = .zero }

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
        pixelBuffer.withUnsafeBufferPointer { buf in
            gfx_upload_pixels(handle, Int32(pixelWidth), Int32(pixelHeight),
                              buf.baseAddress, Int32(buf.count))
        }
    }
}
