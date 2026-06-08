import cabi

func log(_ s: String) {
    var str = s
    str.withUTF8 { buf in
        if let base = buf.baseAddress {
            base.withMemoryRebound(to: CChar.self, capacity: buf.count) { js_log($0, Int32(buf.count)) }
        }
    }
}

@_cdecl("boot")
func boot() {
    log("Swift + Box2D (C++) wasm reactor booted (no Emscripten)")
    cb_init()
}

@_cdecl("frame")
func frame(_ dtMs: Double) {
    cb_step(Float(min(dtMs, 100.0) / 1000.0))   // step the Box2D world from Swift
    gfx_clear(0x12121cff)
    // ground bar
    gfx_fill_rect(0, 600, 1184, 66, 0x333a44ff)
    // map Box2D y (0..18, up-positive) to screen y (down-positive)
    let y = cb_box_y()
    let screenY = Float(600) - (y / 18.0) * 540.0 - 64.0
    gfx_fill_rect(544, screenY, 96, 96, 0x66cc66ff)  // the falling box, driven by Box2D
}
