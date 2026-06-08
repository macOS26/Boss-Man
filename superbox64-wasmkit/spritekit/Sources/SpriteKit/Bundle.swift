// Minimal Foundation URL + Bundle so resource-loading code written against the
// Apple SDK compiles and runs on wasm. The kit's asset table is keyed by
// basename, so a URL is just a (resource, extension) pair; loaders such as
// NSImage(contentsOf:) and Data(contentsOf:) resolve through the host
// (img_by_name / asset_text) on url.resource. Bundle.main.url never decides
// existence itself — it hands back a URL and lets the failable loader probe —
// which matches how the macOS callers pair url lookup with a failable load.
public struct URL {
    public let resource: String
    public let pathExtension: String
    public init(resource: String, ext: String) {
        self.resource = resource
        self.pathExtension = ext
    }
    public var lastPathComponent: String {
        pathExtension.isEmpty ? resource : "\(resource).\(pathExtension)"
    }
}

public final class Bundle {
    public static let main = Bundle()
    public init() {}
    public func url(forResource name: String?, withExtension ext: String?) -> URL? {
        guard let name else { return nil }
        return URL(resource: name, ext: ext ?? "")
    }
}
