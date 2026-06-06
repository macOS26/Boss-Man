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

