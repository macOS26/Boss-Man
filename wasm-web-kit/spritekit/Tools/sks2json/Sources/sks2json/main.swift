import Foundation
import SpriteKit

// sks2json — macOS CLI converter for .sks files.
//
// Apple's .sks files are binary plists from Xcode's Scene/Particle editor.
// They're decoded by SpriteKit's NSKeyedUnarchiver at runtime; outside Apple
// platforms there's no decoder. This tool uses real SpriteKit on macOS to
// load each .sks into an SKNode/SKEmitterNode/SKScene, walks the resulting
// tree, and writes a JSON representation that the SuperBox64 SpriteKit
// runtime (SKSceneLoader) re-builds at game start.
//
// Usage:
//   sks2json [--out <dir>] <file.sks> [file2.sks ...]
//
// With no input args, walks the current directory recursively for .sks files.

// ---- arg parsing -----------------------------------------------------------
var args = Array(CommandLine.arguments.dropFirst())
var outDir: String? = nil
var inputs: [String] = []
var i = 0
while i < args.count {
    let a = args[i]
    if a == "--out" || a == "-o" {
        if i + 1 >= args.count { fail("--out requires a path") }
        outDir = args[i + 1]; i += 2; continue
    }
    if a == "-h" || a == "--help" {
        print("""
        sks2json — convert SpriteKit .sks to portable JSON

        Usage:
          sks2json [--out <dir>] <file.sks> [file2.sks ...]
          sks2json                            # recurse into CWD

        Options:
          --out, -o <dir>   write JSON files into <dir> (mirrors source tree)
        """)
        exit(0)
    }
    inputs.append(a); i += 1
}

if inputs.isEmpty {
    // Walk CWD.
    let cwd = FileManager.default.currentDirectoryPath
    if let enumerator = FileManager.default.enumerator(atPath: cwd) {
        for case let file as String in enumerator where file.hasSuffix(".sks") {
            inputs.append((cwd as NSString).appendingPathComponent(file))
        }
    }
    if inputs.isEmpty { fail("no .sks files found in \(cwd)") }
}

for input in inputs { convert(input) }

func convert(_ input: String) {
    let url = URL(fileURLWithPath: input)
    let basename = url.deletingPathExtension().lastPathComponent
    let outPath: String
    if let dir = outDir {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        outPath = (dir as NSString).appendingPathComponent("\(basename).json")
    } else {
        outPath = url.deletingPathExtension().path + ".json"
    }

    // SpriteKit's typed loaders fall back to NSKeyedUnarchiver under the hood;
    // we try SKScene first (most .sks files), then SKReferenceNode (also valid
    // for non-scene .sks), then NSKeyedUnarchiver for particle files.
    var rootNode: SKNode? = nil
    if let scene = SKScene(fileNamed: basename) ?? SKScene(fileNamed: url.lastPathComponent) {
        rootNode = scene
    } else if let ref = SKReferenceNode(fileNamed: basename) {
        rootNode = ref
    } else if let emitter = SKEmitterNode(fileNamed: basename) {
        rootNode = emitter
    } else {
        // Try a generic unarchive — particle files store SKEmitterNode at root.
        do {
            let data = try Data(contentsOf: url)
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            if let node = unarchiver.decodeObject(of: [SKNode.self, SKScene.self, SKEmitterNode.self,
                                                       SKSpriteNode.self, SKShapeNode.self,
                                                       SKLabelNode.self, SKCameraNode.self],
                                                  forKey: NSKeyedArchiveRootObjectKey) as? SKNode {
                rootNode = node
            }
        } catch { /* fall through */ }
    }

    guard let node = rootNode else {
        warn("could not decode \(input) — try running from the .sks bundle's parent directory")
        return
    }

    let json = encode(node)
    do {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: outPath))
        print("✓ \(input)  →  \(outPath)")
    } catch {
        warn("write failed for \(outPath): \(error)")
    }
}

// ---- node → dictionary ----------------------------------------------------
func encode(_ node: SKNode) -> [String: Any] {
    var d: [String: Any] = [:]
    d["kind"] = String(describing: type(of: node))
    if let n = node.name { d["name"] = n }
    d["position"]  = [node.position.x, node.position.y]
    if node.zPosition != 0 { d["zPosition"] = node.zPosition }
    if node.zRotation != 0 { d["zRotation"] = node.zRotation }
    if node.xScale   != 1 { d["xScale"]    = node.xScale }
    if node.yScale   != 1 { d["yScale"]    = node.yScale }
    if node.alpha    != 1 { d["alpha"]     = node.alpha }
    if node.isHidden       { d["isHidden"]  = true }

    if let s = node as? SKScene {
        d["size"] = [s.size.width, s.size.height]
        d["backgroundColor"] = rgba(s.backgroundColor)
        d["anchorPoint"] = [s.anchorPoint.x, s.anchorPoint.y]
    }
    if let s = node as? SKSpriteNode {
        d["size"] = [s.size.width, s.size.height]
        d["anchorPoint"] = [s.anchorPoint.x, s.anchorPoint.y]
        d["color"] = rgba(s.color)
        d["colorBlendFactor"] = s.colorBlendFactor
        if let texName = s.texture?.description.captureTextureName() {
            d["texture"] = texName
        }
    }
    if let l = node as? SKLabelNode {
        d["text"] = l.text ?? ""
        d["fontSize"] = l.fontSize
        if let f = l.fontName { d["fontName"] = f }
        if let c = l.fontColor { d["fontColor"] = rgba(c) }
        d["horizontalAlignment"] = ["left","center","right"][l.horizontalAlignmentMode.rawValue]
        d["verticalAlignment"]   = ["baseline","center","top","bottom"][l.verticalAlignmentMode.rawValue]
    }
    if let sh = node as? SKShapeNode {
        d["fillColor"]   = rgba(sh.fillColor)
        d["strokeColor"] = rgba(sh.strokeColor)
        d["lineWidth"]   = sh.lineWidth
    }
    if let e = node as? SKEmitterNode {
        emitter(e, into: &d)
    }

    if !node.children.isEmpty {
        d["children"] = node.children.map { encode($0) }
    }
    return d
}

func emitter(_ e: SKEmitterNode, into d: inout [String: Any]) {
    d["particleBirthRate"] = e.particleBirthRate
    d["numParticlesToEmit"] = e.numParticlesToEmit
    d["particleLifetime"] = e.particleLifetime
    d["particleLifetimeRange"] = e.particleLifetimeRange
    d["particleSpeed"] = e.particleSpeed
    d["particleSpeedRange"] = e.particleSpeedRange
    d["emissionAngle"] = e.emissionAngle
    d["emissionAngleRange"] = e.emissionAngleRange
    d["xAcceleration"] = e.xAcceleration
    d["yAcceleration"] = e.yAcceleration
    d["particleAlpha"] = e.particleAlpha
    d["particleAlphaRange"] = e.particleAlphaRange
    d["particleAlphaSpeed"] = e.particleAlphaSpeed
    d["particleScale"] = e.particleScale
    d["particleScaleRange"] = e.particleScaleRange
    d["particleScaleSpeed"] = e.particleScaleSpeed
    d["particleRotation"] = e.particleRotation
    d["particleRotationRange"] = e.particleRotationRange
    d["particleRotationSpeed"] = e.particleRotationSpeed
    d["particleColor"] = rgba(e.particleColor)
    d["particleColorBlendFactor"] = e.particleColorBlendFactor
    d["particleColorBlendFactorRange"] = e.particleColorBlendFactorRange
    d["particleColorBlendFactorSpeed"] = e.particleColorBlendFactorSpeed
    d["particleSize"] = [e.particleSize.width, e.particleSize.height]
    if let texName = e.particleTexture?.description.captureTextureName() {
        d["particleTexture"] = texName
    }
}

func rgba(_ c: NSColor) -> [CGFloat] {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
    return [r, g, b, a]
}

extension String {
    // SKTexture's debug description includes "name='foo'" — pull that out so
    // the JSON references the asset by name. Apple doesn't expose the name
    // through a public API on SKTexture.
    func captureTextureName() -> String? {
        if let r = range(of: #"name='([^']+)'"#, options: .regularExpression) {
            let inner = String(self[r])
            if let s = inner.range(of: "'"), let e = inner.range(of: "'", range: s.upperBound..<inner.endIndex) {
                return String(inner[s.upperBound..<e.lowerBound])
            }
        }
        return nil
    }
}

func warn(_ s: String) { FileHandle.standardError.write(("⚠️  " + s + "\n").data(using: .utf8)!) }
func fail(_ s: String) -> Never { warn(s); exit(2) }
