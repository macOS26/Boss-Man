import SpriteKit
import AppKit

// 3D bonus round: a first-person pseudo-3D walk through level 1's maze, drawn with
// flat 2D shapes (Wolfenstein-style column raycaster) like the Atari "Capture the
// Flag" — corridor view up top, a top-down radar maze at the bottom, and a flag to
// reach. Common to both ports (SKShapeNode bars + labels only).
final class BonusScene: SKScene {

    // MARK: - Maze (level 1)
    private let map: [[Character]] = Levels.officeMaps.first.map { $0.map(Array.init) } ?? []
    private var rowsCount: Int { map.count }
    private var colsCount: Int { map.first?.count ?? 0 }

    private func isWall(_ x: Double, _ y: Double) -> Bool {
        let c = Int(x.rounded(.down)), r = Int(y.rounded(.down))
        guard r >= 0, r < rowsCount, c >= 0, c < map[r].count else { return true }
        return map[r][c] == Strings.Tile.wallChar
    }

    // MARK: - Player (grid coords, y increases downward through the rows array)
    private var px = 1.5, py = 1.5
    private var angle = 0.0                   // radians; 0 = +x (east)
    private var flag = (x: 1.5, y: 1.5)
    private var won = false

    // MARK: - Layout
    private let columns = 96
    private let fov = Double.pi / 3            // 60°
    private var radarH: CGFloat = 188
    private var viewH: CGFloat { size.height - radarH }
    private var viewMidY: CGFloat { radarH + viewH / 2 }

    private var bars: [SKShapeNode] = []
    private var playerDot = SKShapeNode(circleOfRadius: 3)
    private var heading = SKShapeNode()
    private let statusLabel = SKLabelNode()
    private let winLabel = SKLabelNode()

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60
        anchorPoint = .zero
        backgroundColor = .black
        placeStartAndFlag()
        buildSky()
        buildColumns()
        buildRadar()
        buildHUD()
        render()
    }

    // MARK: - Setup
    private func placeStartAndFlag() {
        guard rowsCount > 0 else { return }
        // Start at the worker spawn if present, else the first open cell from the
        // top-left. Flag at the farthest open cell (deepest into the maze).
        var start: (Int, Int)? = nil
        var open: [(Int, Int)] = []
        for r in 0..<rowsCount {
            for c in 0..<map[r].count where map[r][c] != Strings.Tile.wallChar {
                open.append((c, r))
                if map[r][c] == Strings.Tile.workerChar { start = (c, r) }
            }
        }
        let s = start ?? open.first ?? (1, 1)
        px = Double(s.0) + 0.5; py = Double(s.1) + 0.5
        let far = open.max { a, b in
            let da = abs(a.0 - s.0) + abs(a.1 - s.1)
            let db = abs(b.0 - s.0) + abs(b.1 - s.1)
            return da < db
        } ?? s
        flag = (Double(far.0) + 0.5, Double(far.1) + 0.5)
    }

    private func buildSky() {
        // Sunset gradient (sky) over the upper view, solid green ground below the
        // horizon — a stack of bands keeps it #if-free and cheap.
        let horizon = viewMidY
        let bands = 7
        let sky: [(CGFloat, CGFloat, CGFloat)] = [
            (0.16, 0.18, 0.45), (0.30, 0.24, 0.55), (0.55, 0.34, 0.62),
            (0.82, 0.45, 0.55), (0.95, 0.60, 0.42), (0.98, 0.72, 0.40), (1.0, 0.82, 0.45),
        ]
        for i in 0..<bands {
            let h = (size.height - horizon) / CGFloat(bands)
            let band = SKShapeNode(rect: CGRect(x: 0, y: horizon + CGFloat(bands - 1 - i) * h,
                                                 width: size.width, height: h + 1))
            let c = sky[i]
            band.fillColor = SKColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
            band.strokeColor = .clear
            band.zPosition = -2
            addChild(band)
        }
        let ground = SKShapeNode(rect: CGRect(x: 0, y: radarH, width: size.width, height: horizon - radarH))
        ground.fillColor = SKColor(red: 0.20, green: 0.42, blue: 0.16, alpha: 1)
        ground.strokeColor = .clear
        ground.zPosition = -2
        addChild(ground)
    }

    private func buildColumns() {
        let w = size.width / CGFloat(columns)
        for i in 0..<columns {
            // Unit-height bar centered on the horizon; per-frame we set yScale
            // (slice height) + fillColor (distance shade) instead of rebuilding paths.
            let bar = SKShapeNode(rect: CGRect(x: CGFloat(i) * w, y: -0.5, width: w + 0.5, height: 1))
            bar.strokeColor = .clear
            bar.zPosition = 0
            addChild(bar)
            bars.append(bar)
        }
    }

    private var radarScale: CGFloat = 6
    private var radarOX: CGFloat = 12
    private var radarOY: CGFloat = 12

    private func buildRadar() {
        let panel = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: radarH))
        panel.fillColor = SKColor(red: 0.30, green: 0.14, blue: 0.06, alpha: 1)
        panel.strokeColor = .clear
        panel.zPosition = 5
        addChild(panel)
        radarScale = min((size.width / 2 - 24) / CGFloat(max(1, colsCount)),
                         (radarH - 24) / CGFloat(max(1, rowsCount)))
        radarOX = 16
        radarOY = radarH - 12
        let cell = radarScale
        for r in 0..<rowsCount {
            for c in 0..<map[r].count where map[r][c] == Strings.Tile.wallChar {
                let n = SKShapeNode(rect: CGRect(x: radarOX + CGFloat(c) * cell,
                                                 y: radarOY - CGFloat(r + 1) * cell,
                                                 width: cell, height: cell))
                n.fillColor = SKColor(red: 0.82, green: 0.62, blue: 0.18, alpha: 1)
                n.strokeColor = .clear
                n.zPosition = 6
                addChild(n)
            }
        }
        let flagX = radarOX + CGFloat(flag.x) * cell
        let flagY = radarOY - CGFloat(flag.y) * cell
        let pole = SKShapeNode(rect: CGRect(x: flagX, y: flagY, width: 1.5, height: cell * 2))
        pole.fillColor = .white; pole.strokeColor = .clear; pole.zPosition = 7
        addChild(pole)
        let cloth = SKShapeNode(rect: CGRect(x: flagX, y: flagY + cell * 1.2, width: cell * 1.6, height: cell * 0.8))
        cloth.fillColor = SKColor(red: 0.45, green: 0.65, blue: 1.0, alpha: 1)
        cloth.strokeColor = .clear; cloth.zPosition = 7
        addChild(cloth)
        playerDot.fillColor = .systemRed; playerDot.strokeColor = .white; playerDot.lineWidth = 1
        playerDot.zPosition = 8
        addChild(playerDot)
        heading.strokeColor = .systemRed; heading.lineWidth = 1.5; heading.zPosition = 8
        addChild(heading)
    }

    private func buildHUD() {
        statusLabel.fontName = Strings.Font.markerFeltWide
        statusLabel.fontSize = 26
        statusLabel.fontColor = .white
        statusLabel.text = "CAPTURE THE FLAG"
        statusLabel.horizontalAlignmentMode = .center
        statusLabel.position = CGPoint(x: size.width / 2, y: size.height - 40)
        statusLabel.zPosition = 10
        addChild(statusLabel)

        winLabel.fontName = Strings.Font.markerFeltWide
        winLabel.fontSize = 48
        winLabel.fontColor = .systemYellow
        winLabel.horizontalAlignmentMode = .center
        winLabel.position = CGPoint(x: size.width / 2, y: viewMidY)
        winLabel.zPosition = 20
        winLabel.text = ""
        addChild(winLabel)
    }

    // MARK: - Render (per frame)
    override func update(_ currentTime: TimeInterval) {
        step()
        render()
    }

    private func render() {
        let dirX = cos(angle), dirY = sin(angle)
        for i in 0..<columns {
            // Linear ray spread across the FOV (no atan/tan on wasm); cos() below
            // removes the resulting fisheye.
            let rayAngle = angle - fov / 2 + (Double(i) + 0.5) / Double(columns) * fov
            let rx = cos(rayAngle), ry = sin(rayAngle)
            var dist = 0.0
            let stepDist = 0.02
            var hit = false
            var x = px, y = py
            while dist < 24 {
                x += rx * stepDist; y += ry * stepDist; dist += stepDist
                if isWall(x, y) { hit = true; break }
            }
            let perp = max(0.05, dist * (rx * dirX + ry * dirY))   // fisheye correct
            let sliceH = min(viewH, CGFloat(viewH) / CGFloat(perp) * 0.9)
            let bar = bars[i]
            bar.position = CGPoint(x: 0, y: viewMidY)
            bar.yScale = sliceH
            // Shade by distance; slight tint so it reads as walls.
            let shade = CGFloat(max(0.12, min(1.0, 1.0 - perp / 14)))
            bar.fillColor = hit
                ? SKColor(red: 0.22 * shade + 0.04, green: 0.24 * shade + 0.04, blue: 0.30 * shade + 0.05, alpha: 1)
                : .clear
        }
        let cell = radarScale
        playerDot.position = CGPoint(x: radarOX + CGFloat(px) * cell, y: radarOY - CGFloat(py) * cell)
        let hp = CGMutablePath()
        hp.move(to: playerDot.position)
        hp.addLine(to: CGPoint(x: playerDot.position.x + dirX * cell * 2.5,
                               y: playerDot.position.y - dirY * cell * 2.5))
        heading.path = hp
    }

    // MARK: - Movement
    private var pressed = Set<Int>()
    private func step() {
        guard !won else { return }
        let move = 0.06, turn = 0.045
        if pressed.contains(KeyCode.arrowLeft)  || pressed.contains(KeyCode.keyA) { angle -= turn }
        if pressed.contains(KeyCode.arrowRight) || pressed.contains(KeyCode.keyD) { angle += turn }
        var nx = px, ny = py
        if pressed.contains(KeyCode.arrowUp)   || pressed.contains(KeyCode.keyW) { nx += cos(angle) * move; ny += sin(angle) * move }
        if pressed.contains(KeyCode.arrowDown) || pressed.contains(KeyCode.keyS) { nx -= cos(angle) * move; ny -= sin(angle) * move }
        if !isWall(nx, py) { px = nx }      // slide along walls (axis-separated)
        if !isWall(px, ny) { py = ny }
        if abs(px - flag.x) < 0.6 && abs(py - flag.y) < 0.6 { capture() }
    }

    private func capture() {
        won = true
        winLabel.text = "FLAG CAPTURED!"
        run(.sequence([.wait(forDuration: 2.2), .run { [weak self] in self?.exit() }]))
    }

    private func exit() {
        view?.preferredFramesPerSecond = 60
        view?.presentScene(TitleScene(size: size), transition: .fade(withDuration: 0.5))
    }

    // MARK: - Input
    override func keyDown(with event: NSEvent) {
        let code = Int(event.keyCode)
        if code == KeyCode.esc { exit(); return }
        pressed.insert(code)
    }
    override func keyUp(with event: NSEvent) { pressed.remove(Int(event.keyCode)) }

    required init?(coder: NSCoder) { fatalError(Strings.System.initCoderUnsupported) }
    override init(size: CGSize) { super.init(size: size) }
}
