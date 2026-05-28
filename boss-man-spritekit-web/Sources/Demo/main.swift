import SpriteKit

// Pac-Man / BOSS-MAN-style maze on SuperBox64 SpriteKit (the wasm SpriteKit
// compat layer). Original demo code, NOT the BOSS-MAN game source. Features:
//  - grid-stepped lane movement (queue a turn; it executes at the next tile)
//  - a side tunnel that wraps left<->right
//  - a chasing boss with greedy grid AI (one shared tile-stepper drives both)
//  - an animated Pac-style player (mouth chomps, faces its direction)
// Grid/game logic lives here; the framework stays a generic SpriteKit.
enum Dir {
    case none, left, right, up, down
    var delta: (Int, Int) {
        switch self {
        case .left:  return (-1, 0)
        case .right: return (1, 0)
        case .up:    return (0, -1)
        case .down:  return (0, 1)
        case .none:  return (0, 0)
        }
    }
    var opposite: Dir {
        switch self { case .left: return .right; case .right: return .left
        case .up: return .down; case .down: return .up; case .none: return .none }
    }
}

final class Entity {
    var col: Int, row: Int
    var dir: Dir = .none
    var moveT: TimeInterval = 0
    var moving = false
    var from = CGPoint.zero, to = CGPoint.zero, tCol = 0, tRow = 0
    let node: SKNode
    let step: TimeInterval
    init(node: SKNode, col: Int, row: Int, step: TimeInterval) {
        self.node = node; self.col = col; self.row = row; self.step = step
    }
}

final class MazeScene: SKScene {
    static let MAZE = [
        "#####################",
        "#........#.#........#",
        "#.##.###.#.#.###.##.#",
        "#.#.......B.......#.#",
        "#.#.##.#####.##.#.#.#",
        "#......#..P..#......#",
        "#.#.##.#####.##.#.#.#",
        "#.#...............#.#",
        "#.##.###.#.#.###.##.#",
        "#........#.#........#",
        "#####################",
    ]
    // unit circle at 22.5deg steps (index 0 = +x), for the trig-free Pac wedge
    static let UNIT: [(CGFloat, CGFloat)] = [
        (1, 0), (0.924, 0.383), (0.707, 0.707), (0.383, 0.924), (0, 1),
        (-0.383, 0.924), (-0.707, 0.707), (-0.924, 0.383), (-1, 0),
        (-0.924, -0.383), (-0.707, -0.707), (-0.383, -0.924), (0, -1),
        (0.383, -0.924), (0.707, -0.707), (0.924, -0.383),
    ]
    static let TUNNEL_ROW = 5

    let tile: CGFloat = 48
    var cols = 0, rows = 0
    var originX: CGFloat = 0, mazeTop: CGFloat = 0
    var grid: [[Character]] = []

    var player: Entity!, boss: Entity!
    var playerSpawn = (0, 0), bossSpawn = (0, 0)
    var queued: Dir = .none
    var faceIdx = 0
    var dots: [Int: SKNode] = [:]
    var score = 0, total = 0, caught = 0
    let scoreLabel = SKLabelNode(text: "dots: 0")
    var lastTime: TimeInterval = 0

    func key(_ c: Int, _ r: Int) -> Int { r * cols + c }
    func walkable(_ c: Int, _ r: Int) -> Bool {
        guard r >= 0, r < rows, c >= 0, c < cols else { return false }
        return grid[r][c] != "#"
    }
    func tileAfter(_ c: Int, _ r: Int, _ d: Dir) -> (Int, Int) {
        let (dc, dr) = d.delta; var nc = c + dc; let nr = r + dr
        if dr == 0 && (nc < 0 || nc >= cols) { nc = (nc + cols) % cols }  // tunnel wrap
        return (nc, nr)
    }
    func canStep(_ c: Int, _ r: Int, _ d: Dir) -> Bool {
        guard d != .none else { return false }
        let (nc, nr) = tileAfter(c, r, d); return walkable(nc, nr)
    }
    func center(_ c: Int, _ r: Int) -> CGPoint {
        CGPoint(x: originX + CGFloat(c) * tile + tile / 2, y: mazeTop - CGFloat(r) * tile - tile / 2)
    }
    func pacPath(_ face: Int, _ open: Int, _ r: CGFloat) -> CGPath {
        let p = CGMutablePath(); p.move(to: .zero)
        let n = 16 - 2 * open
        for i in 0...n {
            let (x, y) = MazeScene.UNIT[(face + open + i) % 16]
            p.addLine(to: CGPoint(x: x * r, y: y * r))
        }
        p.closeSubpath(); return p
    }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(white: 0.05, alpha: 1)
        grid = MazeScene.MAZE.map { Array($0) }
        rows = grid.count; cols = grid[0].count
        grid[MazeScene.TUNNEL_ROW][0] = "."; grid[MazeScene.TUNNEL_ROW][cols - 1] = "."  // open tunnel mouths
        originX = (size.width - CGFloat(cols) * tile) / 2
        mazeTop = size.height - 110

        let title = SKLabelNode(text: "BOSS-MAN-style maze - SuperBox64 SpriteKit")
        title.fontSize = 28; title.fontColor = .systemYellow
        title.position = CGPoint(x: size.width / 2, y: size.height - 38); addChild(title)
        scoreLabel.fontSize = 22; scoreLabel.fontColor = .systemGreen
        scoreLabel.position = CGPoint(x: size.width / 2, y: size.height - 70); addChild(scoreLabel)

        for (r, line) in grid.enumerated() {
            for (c, ch) in line.enumerated() {
                let p = center(c, r)
                switch ch {
                case "#":
                    let w = SKShapeNode(rectOf: CGSize(width: tile - 3, height: tile - 3), cornerRadius: 5)
                    w.fillColor = SKColor(red: 0.16, green: 0.36, blue: 0.95, alpha: 1)
                    w.strokeColor = SKColor(red: 0.3, green: 0.5, blue: 1, alpha: 1); w.lineWidth = 2
                    w.position = p; addChild(w)
                case ".":
                    let dot = SKShapeNode(circleOfRadius: 5)
                    dot.fillColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1); dot.strokeColor = .clear
                    dot.position = p; addChild(dot); dots[key(c, r)] = dot; total += 1
                case "P":
                    playerSpawn = (c, r)
                    let n = SKShapeNode(circleOfRadius: tile / 2 - 4)
                    n.fillColor = SKColor(red: 1, green: 0.86, blue: 0.1, alpha: 1); n.strokeColor = .clear
                    n.position = p; addChild(n)
                    player = Entity(node: n, col: c, row: r, step: 0.13)
                case "B":
                    bossSpawn = (c, r)
                    let n = SKShapeNode(circleOfRadius: tile / 2 - 4)
                    n.fillColor = SKColor(red: 0.85, green: 0.18, blue: 0.18, alpha: 1)
                    n.strokeColor = .white; n.lineWidth = 2; n.position = p; addChild(n)
                    boss = Entity(node: n, col: c, row: r, step: 0.16)
                default: break
                }
            }
        }
        scoreLabel.text = "dots: 0/\(total)"
    }

    override func keyDown(_ k: Int) {
        switch k {
        case SKKey.left:  queued = .left
        case SKKey.right: queued = .right
        case SKKey.up:    queued = .up
        case SKKey.down:  queued = .down
        default: break
        }
    }

    // One tile-stepper for any entity; `decide` chooses the next direction at a
    // tile boundary, `onArrive` fires when a tile is reached.
    func advance(_ e: Entity, _ dt: TimeInterval, decide: (Entity) -> Dir, onArrive: (Entity) -> Void) {
        var rem = dt, guardCount = 0
        while rem > 0 && guardCount < 8 {
            guardCount += 1
            if !e.moving {
                e.dir = decide(e)
                guard e.dir != .none else { break }
                let (nc, nr) = tileAfter(e.col, e.row, e.dir)
                guard walkable(nc, nr) else { e.moving = false; break }
                if abs(nc - e.col) > 1 {                 // tunnel wrap: pop to far mouth
                    e.col = nc; e.node.position = center(nc, nr); onArrive(e); break
                }
                e.tCol = nc; e.tRow = nr; e.from = center(e.col, e.row); e.to = center(nc, nr)
                e.moveT = e.step; e.moving = true
            }
            let s = min(rem, e.moveT); e.moveT -= s; rem -= s
            let t = CGFloat(max(0, min(1, 1 - e.moveT / e.step)))
            e.node.position = CGPoint(x: e.from.x + (e.to.x - e.from.x) * t,
                                      y: e.from.y + (e.to.y - e.from.y) * t)
            if e.moveT <= 1e-6 { e.col = e.tCol; e.row = e.tRow; e.node.position = e.to; e.moving = false; onArrive(e) }
        }
    }

    func playerDecide(_ e: Entity) -> Dir {
        if queued != .none && canStep(e.col, e.row, queued) { let q = queued; queued = .none; return q }
        if canStep(e.col, e.row, e.dir) { return e.dir }
        return .none
    }
    // BFS shortest path (respects walls + the tunnel) -> first step toward the
    // player. Like the real game's pathfinder; reliably hunts even an idle player.
    func bossDecide(_ e: Entity) -> Dir {
        let startK = key(e.col, e.row), goalK = key(player.col, player.row)
        if startK == goalK { return e.dir }
        let dirs: [Dir] = [.up, .down, .left, .right]
        var prev = [Int: Int](); prev[startK] = -1
        var q = [(e.col, e.row)]; var head = 0; var found = false
        while head < q.count {
            let (c, r) = q[head]; head += 1
            if key(c, r) == goalK { found = true; break }
            for d in dirs {
                let (nc, nr) = tileAfter(c, r, d)
                let k = key(nc, nr)
                if walkable(nc, nr) && prev[k] == nil { prev[k] = key(c, r); q.append((nc, nr)) }
            }
        }
        guard found else { return e.dir }
        var cur = goalK
        while let p = prev[cur], p != startK, p != -1 { cur = p }   // first step off the start
        let curC = cur % cols, curR = cur / cols
        for d in dirs { let (nc, nr) = tileAfter(e.col, e.row, d); if nc == curC && nr == curR { return d } }
        return e.dir
    }
    func collect(_ e: Entity) {
        if let dot = dots.removeValue(forKey: key(e.col, e.row)) {
            dot.removeFromParent(); score += 1
            scoreLabel.text = score >= total ? "all \(total) dots cleared!" : "dots: \(score)/\(total)  caught: \(caught)"
        }
        checkCatch()
    }
    func checkCatch() {
        guard let p = player, let b = boss, p.col == b.col, p.row == b.row else { return }
        caught += 1
        p.col = playerSpawn.0; p.row = playerSpawn.1; p.dir = .none; p.moving = false
        p.node.position = center(p.col, p.row)
        b.col = bossSpawn.0; b.row = bossSpawn.1; b.dir = .none; b.moving = false
        b.node.position = center(b.col, b.row)
        queued = .none
        scoreLabel.text = "dots: \(score)/\(total)  caught: \(caught)"
    }

    override func update(_ currentTime: TimeInterval) {
        guard player != nil, boss != nil else { return }
        let dt = lastTime == 0 ? 0 : currentTime - lastTime
        lastTime = currentTime
        advance(player, dt, decide: playerDecide, onArrive: collect)
        advance(boss, dt, decide: bossDecide, onArrive: { [weak self] _ in self?.checkCatch() })
        // animated Pac mouth, facing the travel direction
        switch player.dir {
        case .right: faceIdx = 0
        case .up:    faceIdx = 4
        case .left:  faceIdx = 8
        case .down:  faceIdx = 12
        case .none:  break
        }
        let open = [0, 1, 2, 1][Int(currentTime * 12) % 4]
        if let shape = player.node as? SKShapeNode { shape.path = pacPath(faceIdx, open, tile / 2 - 4) }
    }
}

nonisolated(unsafe) var skView: SKView? = nil
@_cdecl("boot") func boot() { let v = SKView(); v.presentScene(MazeScene(size: CGSize(width: 1184, height: 666))); skView = v }
@_cdecl("frame") func frame(_ dtMs: Double) { skView?.tick(dtMs) }
