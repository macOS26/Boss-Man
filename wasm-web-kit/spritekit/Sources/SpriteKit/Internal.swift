import KitABI

@inline(__always)
func skLog(_ s: String) {
    var str = s
    str.withUTF8 { b in
        if let p = b.baseAddress { p.withMemoryRebound(to: CChar.self, capacity: b.count) { js_log($0, Int32(b.count)) } }
    }
}

@inline(__always)
func withUTF8Ptr<R>(_ s: String, _ body: (UnsafePointer<CChar>, Int32) -> R) -> R {
    var str = s
    return str.withUTF8 { b in
        guard let base = b.baseAddress else { return body("".withCString { $0 }, 0) }
        return base.withMemoryRebound(to: CChar.self, capacity: b.count) { body($0, Int32(b.count)) }
    }
}
