import SpriteKit

// MARK: - Shared geometry / game logic (no class dependency)

func dpadWedgePath(centerAngle: CGFloat, inner: CGFloat, outer: CGFloat) -> CGPath {
    let a0 = centerAngle - .pi / 4, a1 = centerAngle + .pi / 4
    let steps = 10
    let p = CGMutablePath()
    for i in 0...steps {
        let t = a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps)
        let pt = CGPoint(x: cos(t) * outer, y: sin(t) * outer)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    for i in 0...steps {
        let t = a1 - (a1 - a0) * CGFloat(i) / CGFloat(steps)
        p.addLine(to: CGPoint(x: cos(t) * inner, y: sin(t) * inner))
    }
    p.closeSubpath()
    return p
}

// One D-pad for the whole game (2D + 3D bonus). The X-diagonals split the ring into four EQUAL cardinal
// wedges that match the drawn dpadWedgePath, so the hit-area lines up with what is painted and a single
// pointer (mouse / one finger) yields exactly ONE cardinal; two cardinals need two fingers. "" = inside
// the dead centre or past the outer ring.
func dpadCardinal(_ p: CGPoint, center: CGPoint, deadzone: CGFloat, radius: CGFloat) -> String {
    let dx = p.x - center.x, dy = p.y - center.y
    let mag = (dx * dx + dy * dy).squareRoot()
    if mag < deadzone || mag > radius { return "" }
    if abs(dx) >= abs(dy) { return dx > 0 ? "right" : "left" }
    return dy > 0 ? "up" : "down"
}

// Draw the four-wedge D-pad face (wedges + arrow glyphs + X-diagonal boundary lines) into `parent` at
// `center`, returning the per-direction wedge shapes so the caller can light them on press. The base ring
// is the caller's (stick mode reuses it). The left arrow is the right glyph mirrored so it renders the
// same weight as the others.
func buildDpadFace(in parent: SKNode, center: CGPoint, inner: CGFloat, outer: CGFloat, z: CGFloat) -> [String: SKShapeNode] {
    var wedges: [String: SKShapeNode] = [:]
    let dirs: [(String, CGFloat, String)] = [("up", .pi / 2, "\u{25B2}"), ("left", .pi, "\u{25B6}"),
                                             ("down", -.pi / 2, "\u{25BC}"), ("right", 0, "\u{25B6}")]
    for (name, ang, glyph) in dirs {
        let w = SKShapeNode(path: dpadWedgePath(centerAngle: ang, inner: inner, outer: outer))
        w.position = center
        w.fillColor = SKColor(white: 1, alpha: 0.12); w.strokeColor = .clear
        w.lineWidth = 0; w.zPosition = z
        parent.addChild(w); wedges[name] = w
        let arrow = SKLabelNode(text: glyph)
        arrow.fontSize = 24; arrow.fontColor = SKColor(white: 1, alpha: 0.7)
        arrow.verticalAlignmentMode = .center; arrow.horizontalAlignmentMode = .center
        if name == "left" { arrow.xScale = -1 }
        let r = (inner + outer) / 2
        arrow.position = CGPoint(x: center.x + cos(ang) * r, y: center.y + sin(ang) * r)
        arrow.zPosition = z + 1
        parent.addChild(arrow)
    }
    let xPath = CGMutablePath()
    for k in 0..<4 {
        let t = CGFloat.pi / 4 + CGFloat(k) * CGFloat.pi / 2
        xPath.move(to: CGPoint(x: cos(t) * inner, y: sin(t) * inner))
        xPath.addLine(to: CGPoint(x: cos(t) * outer, y: sin(t) * outer))
    }
    let xlines = SKShapeNode(path: xPath)
    xlines.position = center
    xlines.strokeColor = SKColor(white: 1, alpha: 0.5); xlines.lineWidth = 2; xlines.zPosition = z
    parent.addChild(xlines)
    return wedges
}

// Light the pressed wedge (dim the rest) on a face built by buildDpadFace.
func lightDpadFace(_ wedges: [String: SKShapeNode], up: Bool, down: Bool, left: Bool, right: Bool) {
    let on: [String: Bool] = ["up": up, "down": down, "left": left, "right": right]
    for (k, v) in on { wedges[k]?.fillColor = SKColor(white: 1, alpha: v ? 0.34 : 0.12) }
}

func dropletThreatens(dropletGrid d: CGPoint, dir: MoveDirection, boss b: CGPoint, range: Int, isWalkable: (CGPoint) -> Bool) -> Bool {
    let (dx, dy) = dir.delta
    let dist: Int
    if dx != 0 {
        guard Int(b.y) == Int(d.y) else { return false }
        let delta = Int(b.x) - Int(d.x)
        guard delta != 0, (dx > 0) == (delta > 0) else { return false }
        dist = abs(delta)
    } else {
        guard Int(b.x) == Int(d.x) else { return false }
        let delta = Int(b.y) - Int(d.y)
        guard delta != 0, (dy > 0) == (delta > 0) else { return false }
        dist = abs(delta)
    }
    guard dist <= range else { return false }
    var step = d
    for _ in 0..<dist {
        step = CGPoint(x: step.x + CGFloat(dx), y: step.y + CGFloat(dy))
        if !isWalkable(step) { return false }
    }
    return true
}

