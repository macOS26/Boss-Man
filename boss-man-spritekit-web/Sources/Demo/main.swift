import SpriteKit

// A Pac-Man / BOSS-MAN-style maze on SuperBox64 SpriteKit (the wasm SpriteKit
// compat layer). Original demo code — NOT the BOSS-MAN game source. Movement is
// grid-stepped like the real game: the player occupies a tile, you queue a turn,
// and at each tile boundary it turns if the neighbor is open, otherwise keeps
// going or stops at a wall — interpolating between tile centers. The grid logic
// lives here in the game, not in the framework (which stays generic).
//
// NB: constants are `static let` (lazily initialized) — top-level `let` in a
// reactor's main.swift never runs.
enum Dir {
    case none, left, right, up, down
    var delta: (Int, Int) {
        switch self {
        case .left:  return (-1, 0)
        case .right: return (1, 0)
        case .up:    return (0, -1)   // toward the top of the maze (row - 1)
        case .down:  return (0, 1)
        case .none:  return (0, 0)
        }
    }
}

final class MazeScene: SKScene {
    static let MAZE = [
        "#####################",
        "#........#.#........#",
        "#.##.###.#.#.###.##.#",
        "#.#...............#.#",
        "#.#.##.#####.##.#.#.#",
        "#......#. P .#......#",
        "#.#.##.#####.##.#.#.#",
        "#.#...............#.#",
        "#.##.###.#.#.###.##.#",
        "#........#.#........#",
        "#####################",
    ]
    static let STEP: TimeInterval = 0.13   // seconds per tile (Pac-Man pacing)

    let tile: CGFloat = 48
    var cols = 0, rows = 0
    var originX: CGFloat = 0, mazeTop: CGFloat = 0

    var player: SKShapeNode!
    var col = 0, row = 0                    // current tile
    var dir: Dir = .none, queued: Dir = .none
    var moveT: TimeInterval = 0             // time left in the current tile step
    var moving = false
    var fromPx = CGPoint.zero, toPx = CGPoint.zero
    var targetCol = 0, targetRow = 0

    var dots: [Int: SKNode] = [:]           // tileKey -> dot node
    var score = 0, total = 0
    let scoreLabel = SKLabelNode(text: "dots: 0")

    func key(_ c: Int, _ r: Int) -> Int { r * cols + c }
    func walkable(_ c: Int, _ r: Int) -> Bool {
        guard r >= 0, r < rows, c >= 0, c < cols else { return false }
        let line = Array(MazeScene.MAZE[r])
        return c < line.count && line[c] != "#"
    }
    func center(_ c: Int, _ r: Int) -> CGPoint {
        CGPoint(x: originX + CGFloat(c) * tile + tile / 2, y: mazeTop - CGFloat(r) * tile - tile / 2)
    }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(white: 0.05, alpha: 1)
        let maze = MazeScene.MAZE
        rows = maze.count; cols = maze[0].count
        originX = (size.width - CGFloat(cols) * tile) / 2
        mazeTop = size.height - 110

        let title = SKLabelNode(text: "BOSS-MAN-style maze - SuperBox64 SpriteKit")
        title.fontSize = 30; title.fontColor = .systemYellow
        title.position = CGPoint(x: size.width / 2, y: size.height - 40); addChild(title)
        scoreLabel.fontSize = 22; scoreLabel.fontColor = .systemGreen
        scoreLabel.position = CGPoint(x: size.width / 2, y: size.height - 74); addChild(scoreLabel)

        for (r, line) in maze.enumerated() {
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
                    dot.position = p; addChild(dot)
                    dots[key(c, r)] = dot; total += 1
                case "P":
                    col = c; row = r
                    player = SKShapeNode(circleOfRadius: tile / 2 - 4)
                    player.fillColor = SKColor(red: 0.2, green: 0.85, blue: 1, alpha: 1)
                    player.strokeColor = .white; player.lineWidth = 2; player.position = p
                    addChild(player)
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

    func startStep() {
        if queued != .none {
            let (dc, dr) = queued.delta
            if walkable(col + dc, row + dr) { dir = queued; queued = .none }
        }
        let (dc, dr) = dir.delta
        guard dir != .none, walkable(col + dc, row + dr) else { moving = false; return }
        targetCol = col + dc; targetRow = row + dr
        fromPx = center(col, row); toPx = center(targetCol, targetRow)
        moveT = MazeScene.STEP; moving = true
    }

    func enterTile() {
        if let dot = dots.removeValue(forKey: key(col, row)) {
            dot.removeFromParent(); score += 1
            scoreLabel.text = score >= total ? "all \(total) dots cleared!" : "dots: \(score)/\(total)"
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard player != nil else { return }
        var remaining = lastTime == 0 ? 0 : currentTime - lastTime
        lastTime = currentTime
        // consume dt across tile boundaries so movement stays smooth
        var guardCount = 0
        while remaining > 0 && guardCount < 8 {
            guardCount += 1
            if !moving { startStep(); if !moving { break } }
            let step = min(remaining, moveT)
            moveT -= step; remaining -= step
            let t = CGFloat(max(0, min(1, 1 - moveT / MazeScene.STEP)))
            player.position = CGPoint(x: fromPx.x + (toPx.x - fromPx.x) * t,
                                      y: fromPx.y + (toPx.y - fromPx.y) * t)
            if moveT <= 1e-6 {
                col = targetCol; row = targetRow; player.position = toPx; moving = false
                enterTile()
            }
        }
    }
    var lastTime: TimeInterval = 0
}

nonisolated(unsafe) var skView: SKView? = nil
@_cdecl("boot") func boot() { let v = SKView(); v.presentScene(MazeScene(size: CGSize(width: 1184, height: 666))); skView = v }
@_cdecl("frame") func frame(_ dtMs: Double) { skView?.tick(dtMs) }
