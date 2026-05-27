import KitABI

public final class SKTexture {
    let handle: Int32
    public var size: CGSize
    public init(imageNamed name: String) {
        handle = withUTF8Ptr(name) { img_by_name($0, $1) }
        size = .zero
    }
    init(handle: Int32) { self.handle = handle; size = .zero }
}
