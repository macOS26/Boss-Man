import KitABI

// .sks → JSON scene loader.
//
// Apple's .sks files are binary plists from the SpriteKit Particle / Scene
// editors; they aren't portable to WASI. The companion CLI sks2json
// (Tools/sks2json on macOS) walks the in-memory scene graph through Apple's
// SpriteKit and emits a portable JSON file with the same name, e.g.:
//   Level5.sks → Level5.json
//
// At runtime SKScene(fileNamed:) / SKReferenceNode(fileNamed:) /
// SKEmitterNode(fileNamed:) look for that JSON via the kit's asset_text ABI,
// then rebuild the node tree by walking the dictionary.
//
// JSON schema (subset of SpriteKit's node attributes):
//   {
//     "kind": "SKScene" | "SKSpriteNode" | "SKShapeNode" | "SKLabelNode" |
//             "SKEmitterNode" | "SKReferenceNode" | "SKNode" | "SKCameraNode" |
//             "SKTileMapNode" | ...,
//     "name": "playerSpawn",
//     "position": [x, y],
//     "zRotation": 0.0,
//     "zPosition": 0.0,
//     "xScale": 1.0,
//     "yScale": 1.0,
//     "alpha": 1.0,
//     "size": [w, h],                      // SKScene / SKSpriteNode / SKLabelNode
//     "anchorPoint": [x, y],               // SKSpriteNode
//     "color": [r, g, b, a],               // 0..1
//     "colorBlendFactor": 0..1,
//     "texture": "image-name",             // SKSpriteNode
//     "text": "Score",                     // SKLabelNode
//     "fontSize": 24,
//     "fontName": "JetBrainsMono-Bold",
//     "fontColor": [r, g, b, a],
//     "horizontalAlignment": "center"|"left"|"right",
//     "verticalAlignment":   "center"|"top"|"bottom"|"baseline",
//     "particleBirthRate": ...,            // SKEmitterNode + all property surface
//     "fileNamed": "Level5",               // SKReferenceNode
//     "children": [ ... ]
//   }

public enum SKSceneLoader {
    // Public entry: load a JSON file (compiled from .sks) and reconstruct the
    // root SKNode. Returns nil when the file isn't found or parsing fails.
    public static func loadNode(fileNamed name: String) -> SKNode? {
        guard let json = loadJSON(named: name) else { return nil }
        return build(from: json)
    }
    public static func loadScene(fileNamed name: String) -> SKScene? {
        guard let json = loadJSON(named: name) else { return nil }
        guard let node = build(from: json) as? SKScene else {
            // Wrap a non-scene root in a default scene for compatibility.
            let scene = SKScene(size: CGSize(width: 1184, height: 666))
            if let n = build(from: json) { scene.addChild(n) }
            return scene
        }
        return node
    }
    public static func loadEmitter(fileNamed name: String) -> SKEmitterNode? {
        guard let json = loadJSON(named: name) else { return nil }
        let emitter = SKEmitterNode()
        applyCommonProps(json, to: emitter)
        applyEmitterProps(json, to: emitter)
        return emitter
    }

    // ---- File loader ----------------------------------------------------------
    private static func loadJSON(named name: String) -> [String: Any]? {
        // Try a few common spellings. The CLI emits "<basename>.json" so the
        // most common case is direct.
        for candidate in [name, "\(name).json", "\(name).sks.json"] {
            if let bytes = readAssetText(candidate),
               let obj = parseJSON(bytes) as? [String: Any] {
                return obj
            }
        }
        return nil
    }

    private static func readAssetText(_ path: String) -> String? {
        let exists = withUTF8Ptr(path) { ptr, n -> Int32 in asset_exists(ptr, n) }
        if exists == 0 { return nil }
        // Probe size by passing a 1-byte buffer first; asset_text returns the
        // total byte length so we can allocate the right size.
        var probe: [Int8] = [0]
        let total = probe.withUnsafeMutableBufferPointer { p in
            withUTF8Ptr(path) { kptr, kn in asset_text(kptr, kn, p.baseAddress, Int32(1)) }
        }
        if total <= 0 { return nil }
        let cap = Int(total) + 1
        var buf = [Int8](repeating: 0, count: cap)
        _ = buf.withUnsafeMutableBufferPointer { p -> Int32 in
            let cap32 = Int32(p.count)
            return withUTF8Ptr(path) { kptr, kn in asset_text(kptr, kn, p.baseAddress, cap32) }
        }
        return String(cString: buf)
    }

    // ---- Construction --------------------------------------------------------
    private static func build(from json: [String: Any]) -> SKNode? {
        let kind = (json["kind"] as? String) ?? "SKNode"
        let node: SKNode
        switch kind {
        case "SKScene":
            let size = readSize(json["size"]) ?? CGSize(width: 1184, height: 666)
            let scene = SKScene(size: size)
            if let bg = readColor(json["backgroundColor"]) { scene.backgroundColor = bg }
            if let ap = readPoint(json["anchorPoint"]) { scene.anchorPoint = ap }
            node = scene
        case "SKSpriteNode":
            let size = readSize(json["size"]) ?? CGSize(width: 32, height: 32)
            let color = readColor(json["color"]) ?? .white
            let sprite = SKSpriteNode(color: color, size: size)
            if let texName = json["texture"] as? String {
                sprite.texture = SKTexture(imageNamed: texName)
            }
            if let ap = readPoint(json["anchorPoint"]) { sprite.anchorPoint = ap }
            if let cbf = readCGFloat(json["colorBlendFactor"]) { sprite.colorBlendFactor = cbf }
            node = sprite
        case "SKLabelNode":
            let text = (json["text"] as? String) ?? ""
            let label = SKLabelNode(text: text)
            if let s = readCGFloat(json["fontSize"]) { label.fontSize = s }
            if let f = json["fontName"] as? String { label.fontName = f }
            if let c = readColor(json["fontColor"]) { label.fontColor = c }
            if let h = json["horizontalAlignment"] as? String {
                switch h { case "left": label.horizontalAlignmentMode = .left
                           case "right": label.horizontalAlignmentMode = .right
                           default: label.horizontalAlignmentMode = .center }
            }
            if let v = json["verticalAlignment"] as? String {
                switch v { case "top": label.verticalAlignmentMode = .top
                           case "bottom": label.verticalAlignmentMode = .bottom
                           case "baseline": label.verticalAlignmentMode = .baseline
                           default: label.verticalAlignmentMode = .center }
            }
            node = label
        case "SKShapeNode":
            let shape: SKShapeNode
            if let r = readCGFloat(json["radius"]) {
                shape = SKShapeNode(circleOfRadius: r)
            } else if let size = readSize(json["size"]) {
                shape = SKShapeNode(rectOf: size)
            } else {
                shape = SKShapeNode()
            }
            if let c = readColor(json["fillColor"])   { shape.fillColor = c }
            if let c = readColor(json["strokeColor"]) { shape.strokeColor = c }
            if let w = readCGFloat(json["lineWidth"]) { shape.lineWidth = w }
            node = shape
        case "SKEmitterNode":
            let emitter = SKEmitterNode()
            applyEmitterProps(json, to: emitter)
            node = emitter
        case "SKReferenceNode":
            if let inner = json["fileNamed"] as? String,
               let ref = loadNode(fileNamed: inner) {
                node = ref
            } else {
                node = SKReferenceNode()
            }
        case "SKCameraNode":
            node = SKCameraNode()
        default:
            node = SKNode()
        }
        applyCommonProps(json, to: node)
        if let kids = json["children"] as? [Any] {
            for child in kids {
                if let cdict = child as? [String: Any], let cnode = build(from: cdict) {
                    node.addChild(cnode)
                }
            }
        }
        return node
    }

    // ---- Property helpers ----------------------------------------------------
    private static func applyCommonProps(_ json: [String: Any], to node: SKNode) {
        if let p = readPoint(json["position"])  { node.position  = p }
        if let z = readCGFloat(json["zPosition"]) { node.zPosition = z }
        if let r = readCGFloat(json["zRotation"]) { node.zRotation = r }
        if let s = readCGFloat(json["xScale"])    { node.xScale = s }
        if let s = readCGFloat(json["yScale"])    { node.yScale = s }
        if let a = readCGFloat(json["alpha"])     { node.alpha = a }
        if let n = json["name"] as? String        { node.name = n }
        if let h = json["isHidden"] as? Bool      { node.isHidden = h }
    }
    private static func applyEmitterProps(_ json: [String: Any], to e: SKEmitterNode) {
        if let v = readCGFloat(json["particleBirthRate"])     { e.particleBirthRate = v }
        if let v = json["numParticlesToEmit"] as? Int          { e.numParticlesToEmit = v }
        if let v = readCGFloat(json["particleLifetime"])       { e.particleLifetime = v }
        if let v = readCGFloat(json["particleLifetimeRange"])  { e.particleLifetimeRange = v }
        if let v = readCGFloat(json["particleSpeed"])          { e.particleSpeed = v }
        if let v = readCGFloat(json["particleSpeedRange"])     { e.particleSpeedRange = v }
        if let v = readCGFloat(json["emissionAngle"])          { e.emissionAngle = v }
        if let v = readCGFloat(json["emissionAngleRange"])     { e.emissionAngleRange = v }
        if let v = readCGFloat(json["xAcceleration"])          { e.xAcceleration = v }
        if let v = readCGFloat(json["yAcceleration"])          { e.yAcceleration = v }
        if let v = readCGFloat(json["particleAlpha"])          { e.particleAlpha = v }
        if let v = readCGFloat(json["particleAlphaRange"])     { e.particleAlphaRange = v }
        if let v = readCGFloat(json["particleAlphaSpeed"])     { e.particleAlphaSpeed = v }
        if let v = readCGFloat(json["particleScale"])          { e.particleScale = v }
        if let v = readCGFloat(json["particleScaleRange"])     { e.particleScaleRange = v }
        if let v = readCGFloat(json["particleScaleSpeed"])     { e.particleScaleSpeed = v }
        if let v = readCGFloat(json["particleRotation"])       { e.particleRotation = v }
        if let v = readCGFloat(json["particleRotationRange"])  { e.particleRotationRange = v }
        if let v = readCGFloat(json["particleRotationSpeed"])  { e.particleRotationSpeed = v }
        if let c = readColor(json["particleColor"])            { e.particleColor = c }
        if let v = readCGFloat(json["particleColorBlendFactor"])      { e.particleColorBlendFactor = v }
        if let v = readCGFloat(json["particleColorBlendFactorRange"]) { e.particleColorBlendFactorRange = v }
        if let v = readCGFloat(json["particleColorBlendFactorSpeed"]) { e.particleColorBlendFactorSpeed = v }
        if let s = readSize(json["particleSize"])              { e.particleSize = s }
        if let texName = json["particleTexture"] as? String {
            e.particleTexture = SKTexture(imageNamed: texName)
        }
    }

    private static func readSize(_ any: Any?) -> CGSize? {
        guard let arr = any as? [Any], arr.count >= 2,
              let w = readCGFloat(arr[0]), let h = readCGFloat(arr[1]) else { return nil }
        return CGSize(width: w, height: h)
    }
    private static func readPoint(_ any: Any?) -> CGPoint? {
        guard let arr = any as? [Any], arr.count >= 2,
              let x = readCGFloat(arr[0]), let y = readCGFloat(arr[1]) else { return nil }
        return CGPoint(x: x, y: y)
    }
    private static func readColor(_ any: Any?) -> SKColor? {
        guard let arr = any as? [Any], arr.count >= 3,
              let r = readCGFloat(arr[0]), let g = readCGFloat(arr[1]), let b = readCGFloat(arr[2]) else { return nil }
        let a = arr.count >= 4 ? (readCGFloat(arr[3]) ?? 1) : 1
        return SKColor(red: r, green: g, blue: b, alpha: a)
    }
    private static func readCGFloat(_ any: Any?) -> CGFloat? {
        if let d = any as? Double { return CGFloat(d) }
        if let i = any as? Int    { return CGFloat(i) }
        if let f = any as? Float  { return CGFloat(f) }
        return nil
    }
}

// =============================================================================
// SKScene(fileNamed:) / SKReferenceNode(fileNamed:) routes through the loader.
// We add convenience initializers that try the loader and fall back to the
// existing empty-node behaviour if the JSON isn't found.
// =============================================================================
public extension SKScene {
    convenience init?(fileNamed name: String) {
        if let scene = SKSceneLoader.loadScene(fileNamed: name) {
            self.init(size: scene.size)
            self.backgroundColor = scene.backgroundColor
            self.anchorPoint = scene.anchorPoint
            for child in scene.children { self.addChild(child) }
            return
        }
        return nil
    }
}
