import SpriteKit
import AppKit

// 3D bonus round: the office maze (level 1) rendered first/third-person with flat
// 2D graphics — a Wolfenstein-style DDA raycaster for the walls, a smooth blended
// sunset sky, and billboarded game sprites (pellets, gold discs, bosses) standing
// in the corridors. The camera trails behind Pete so you see him walking ahead of
// you. A top-down radar sits at the bottom. Common to both ports.
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

    // MARK: - Pete + chase camera (grid coords; y increases down the rows array)
    private var px = 1.5, py = 1.5, angle = 0.0
    private var moveDir = (x: 1, y: 0)       // current lane direction (cardinal)
    private var wantDir: (x: Int, y: Int)? = nil   // queued turn (taken at the next junction)
    private var tcx = 1.5, tcy = 1.5, targetAngle = 0.0
    private let camBack = 0.65               // how far the camera trails behind Pete

    private func open(_ c: Int, _ r: Int) -> Bool {
        r >= 0 && r < rowsCount && c >= 0 && c < map[r].count && map[r][c] != Strings.Tile.wallChar
    }
    private func cardinal(_ d: (x: Int, y: Int)) -> Double {
        if d.x > 0 { return 0 }; if d.x < 0 { return .pi }
        return d.y > 0 ? .pi / 2 : -.pi / 2
    }

    // MARK: - Layout / projection
    private let columns = 200
    private let planeScale = 0.5773          // tan(fov/2), fov 60° (no tan() on wasm)
    private var radarH: CGFloat = 180
    private var viewH: CGFloat { size.height - radarH }
    private var viewMidY: CGFloat { radarH + viewH * 0.70 }   // horizon, lifted for a look-down view
    private var bars: [SKShapeNode] = []
    private var zbuf: [Double] = []

    // MARK: - Billboards (pooled: built once, projected each frame)
    private struct Billboard { let node: SKNode; let nativeH: CGFloat; let worldH: CGFloat; let x, y: Double; var alive: Bool }
    private var billboards: [Billboard] = []
    private let spriteLayer = SKNode()
    private var pete: PixelPerson!
    private var peteBaseY: CGFloat = 0
    private var bob = 0.0

    private let statusLabel = SKLabelNode()
    private var isUserPaused = false

    // MARK: - Minimap (the real 2D level, centered at the bottom)
    private let mapLayer = SKNode()
    private var mapPete: PixelPerson!
    private var mapPickups: [Int: SKNode] = [:]
    private let mapCell: CGFloat = 32
    private var mapScale: CGFloat = 1

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60
        anchorPoint = .zero
        backgroundColor = .black
        zbuf = Array(repeating: 0, count: columns)
        placeStart()
        buildSky()
        buildColumns()
        spriteLayer.zPosition = 1
        addChild(spriteLayer)
        buildBillboards()
        buildPete()
        buildMap()
        buildHUD()
        render()
    }

    // MARK: - Setup
    private func placeStart() {
        var sc = 1, sr = 1, found = false
        outer: for r in 0..<rowsCount {
            for c in 0..<map[r].count where map[r][c] == Strings.Tile.workerChar { sc = c; sr = r; found = true; break outer }
        }
        if !found {
            search: for r in 0..<rowsCount {
                for c in 0..<map[r].count where map[r][c] != Strings.Tile.wallChar { sc = c; sr = r; break search }
            }
        }
        px = Double(sc) + 0.5; py = Double(sr) + 0.5; tcx = px; tcy = py
        for d in [(x: 1, y: 0), (x: 0, y: 1), (x: -1, y: 0), (x: 0, y: -1)] where open(sc + d.x, sr + d.y) {
            moveDir = d; break
        }
        targetAngle = cardinal(moveDir); angle = targetAngle
    }

    private func buildSky() {
        // 2D office palette: a dark ceiling (maze background) blending toward the
        // horizon over the dark checker-floor colour. One thin band per device row
        // so the gradient is smooth, no banding. Drawn once.
        let horC: (CGFloat, CGFloat, CGFloat) = (0.10, 0.10, 0.13)   // maze background, lit at horizon
        let topC: (CGFloat, CGFloat, CGFloat) = (0.02, 0.02, 0.035)  // darker toward the ceiling
        let skyBottom = viewMidY, skyTop = size.height
        let n = max(1, Int(skyTop - skyBottom))
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(max(1, n - 1))      // 0 horizon .. 1 ceiling
            let col = SKColor(red: horC.0 + (topC.0 - horC.0) * t,
                              green: horC.1 + (topC.1 - horC.1) * t,
                              blue: horC.2 + (topC.2 - horC.2) * t, alpha: 1)
            let band = SKShapeNode(rect: CGRect(x: 0, y: skyBottom + CGFloat(i), width: size.width, height: 2))
            band.fillColor = col; band.strokeColor = .clear; band.zPosition = -3
            addChild(band)
        }
        let ground = SKShapeNode(rect: CGRect(x: 0, y: radarH, width: size.width, height: viewMidY - radarH))
        ground.fillColor = SKColor(red: 0.11, green: 0.12, blue: 0.13, alpha: 1)   // floor-tile colour
        ground.strokeColor = .clear; ground.zPosition = -3
        addChild(ground)
    }

    private func buildColumns() {
        for _ in 0..<columns {
            let bar = SKShapeNode()
            bar.strokeColor = .clear; bar.isAntialiased = true; bar.zPosition = 0
            addChild(bar); bars.append(bar)
        }
    }

    private func buildBillboards() {
        for r in 0..<rowsCount {
            for (c, ch) in map[r].enumerated() {
                let x = Double(c) + 0.5, y = Double(r) + 0.5
                var node: SKNode?; var worldH: CGFloat = 0.6
                switch ch {
                case Strings.Tile.dotChar, Strings.Tile.hideoutChar:
                    node = SpriteFactory.pelletCube(size: 8); worldH = 0.14
                case Strings.Tile.goldDiscChar:
                    node = SpriteFactory.goldDiscVisual(radius: 10); worldH = 0.4
                case Strings.Tile.waterPelletChar:
                    node = SpriteFactory.waterPelletVisual(radius: 10); worldH = 0.4
                case Strings.Tile.boss1Char: node = SpriteFactory.bossPersonForBlueprint(0); worldH = 0.9
                case Strings.Tile.boss2Char: node = SpriteFactory.bossPersonForBlueprint(1); worldH = 0.9
                case Strings.Tile.boss3Char: node = SpriteFactory.bossPersonForBlueprint(2); worldH = 0.9
                case Strings.Tile.boss4Char: node = SpriteFactory.bossPersonForBlueprint(3); worldH = 0.9
                default: continue
                }
                guard let n = node else { continue }
                n.isHidden = true
                spriteLayer.addChild(n)
                let nh = max(1, n.calculateAccumulatedFrame().height)
                billboards.append(Billboard(node: n, nativeH: nh, worldH: worldH, x: x, y: y, alive: true))
            }
        }
    }

    private func buildPete() {
        pete = SpriteFactory.petePersonBack(walkExaggeration: 1)
        let nativeH = max(1, pete.calculateAccumulatedFrame().height)
        let target = viewH * 0.42
        pete.setScale(target / nativeH)
        pete.zPosition = 90                          // above every billboard, so pellets pass behind him
        peteBaseY = radarH + target / 2 + 6
        pete.position = CGPoint(x: size.width / 2, y: peteBaseY)
        spriteLayer.addChild(pete)
        pete.startWalking()
    }

    private func buildHUD() {
        statusLabel.fontName = Strings.Font.markerFeltWide
        statusLabel.fontSize = 24; statusLabel.fontColor = .white
        statusLabel.text = "BOSS-MAN 3D"
        statusLabel.horizontalAlignmentMode = .center
        statusLabel.position = CGPoint(x: size.width / 2, y: size.height - 36)
        statusLabel.zPosition = 50
        addChild(statusLabel)
    }

    private func togglePause() {
        isUserPaused.toggle()
        if isUserPaused { pete.stopWalking() } else { pete.startWalking() }
    }

    private func mapKey(_ c: Int, _ r: Int) -> Int { r * colsCount + c }
    private func mapLocal(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x) * mapCell, y: (CGFloat(rowsCount) - CGFloat(y)) * mapCell)
    }
    private func buildMap() {
        let panel = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: radarH))
        panel.fillColor = SKColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        panel.strokeColor = .clear; panel.zPosition = 29
        addChild(panel)

        let cubicle = SpriteFactory.cubicleColors[0]
        for r in 0..<rowsCount {
            for (c, ch) in map[r].enumerated() {
                let center = mapLocal(Double(c) + 0.5, Double(r) + 0.5)
                let floor = SpriteFactory.floorTile(size: mapCell, alternate: (c + r) % 2 == 0)
                floor.position = center; floor.zPosition = 0; mapLayer.addChild(floor)
                var pickup: SKNode?
                switch ch {
                case Strings.Tile.wallChar:
                    let wall = SpriteFactory.wallTile(size: mapCell, color: cubicle)
                    wall.position = center; wall.zPosition = 1; mapLayer.addChild(wall)
                case Strings.Tile.dotChar, Strings.Tile.hideoutChar:
                    pickup = SpriteFactory.dotVisual(size: mapCell * 0.2)
                case Strings.Tile.goldDiscChar:
                    pickup = SpriteFactory.goldDiscVisual(radius: mapCell * 0.28)
                case Strings.Tile.waterPelletChar:
                    pickup = SpriteFactory.waterPelletVisual(radius: mapCell * 0.32)
                case Strings.Tile.boss1Char: pickup = SpriteFactory.bossPersonForBlueprint(0)
                case Strings.Tile.boss2Char: pickup = SpriteFactory.bossPersonForBlueprint(1)
                case Strings.Tile.boss3Char: pickup = SpriteFactory.bossPersonForBlueprint(2)
                case Strings.Tile.boss4Char: pickup = SpriteFactory.bossPersonForBlueprint(3)
                default: break
                }
                if let pickup {
                    pickup.position = center; pickup.zPosition = 2; mapLayer.addChild(pickup)
                    switch ch {
                    case Strings.Tile.dotChar, Strings.Tile.hideoutChar, Strings.Tile.goldDiscChar, Strings.Tile.waterPelletChar:
                        mapPickups[mapKey(c, r)] = pickup
                    default: break
                    }
                }
            }
        }
        mapPete = SpriteFactory.petePerson(walkExaggeration: 1)
        mapPete.zPosition = 5
        mapLayer.addChild(mapPete)
        mapPete.startWalking()

        let mapW = CGFloat(colsCount) * mapCell, mapH = CGFloat(rowsCount) * mapCell
        mapScale = (radarH - 8) / mapH * CGFloat(MazeZoom.current) / 100
        mapLayer.setScale(mapScale)
        mapLayer.position = CGPoint(x: (size.width - mapW * mapScale) / 2, y: 4)
        mapLayer.zPosition = 30
        addChild(mapLayer)
    }

    // MARK: - Per-frame
    override func update(_ currentTime: TimeInterval) {
        if isUserPaused { return }
        step(); render()
    }

    private var camX = 0.0, camY = 0.0
    private func render() {
        let dirX = cos(angle), dirY = sin(angle)
        let planeX = -dirY * planeScale, planeY = dirX * planeScale
        // Camera trails behind Pete; pull in if it would sit inside a wall.
        var back = camBack
        while back > 0.05 && isWall(px - dirX * back, py - dirY * back) { back -= 0.1 }
        camX = px - dirX * back; camY = py - dirY * back

        // Cast a ray at every column boundary, then connect adjacent tops/bottoms
        // into sloped quads so wall silhouettes are continuous lines, not stairs.
        var topY = [CGFloat](repeating: 0, count: columns + 1)
        var botY = [CGFloat](repeating: 0, count: columns + 1)
        var dist = [Double](repeating: 0, count: columns + 1)
        var sides = [Int](repeating: 0, count: columns + 1)
        for j in 0...columns {
            let cameraX = 2.0 * Double(j) / Double(columns) - 1.0
            let rdx = dirX + planeX * cameraX, rdy = dirY + planeY * cameraX
            var mapX = Int(camX.rounded(.down)), mapY = Int(camY.rounded(.down))
            let ddx = rdx == 0 ? 1e30 : abs(1 / rdx), ddy = rdy == 0 ? 1e30 : abs(1 / rdy)
            var stepX = 0, stepY = 0, sideX = 0.0, sideY = 0.0
            if rdx < 0 { stepX = -1; sideX = (camX - Double(mapX)) * ddx } else { stepX = 1; sideX = (Double(mapX) + 1 - camX) * ddx }
            if rdy < 0 { stepY = -1; sideY = (camY - Double(mapY)) * ddy } else { stepY = 1; sideY = (Double(mapY) + 1 - camY) * ddy }
            var side = 0, guardN = 0
            while guardN < 200 {
                guardN += 1
                if sideX < sideY { sideX += ddx; mapX += stepX; side = 0 } else { sideY += ddy; mapY += stepY; side = 1 }
                if mapY < 0 || mapY >= rowsCount || mapX < 0 || mapX >= colsCount { break }
                if map[mapY][mapX] == Strings.Tile.wallChar { break }
            }
            let perp = side == 0 ? (sideX - ddx) : (sideY - ddy)
            let d = max(0.05, perp)
            dist[j] = d; sides[j] = side
            let lineH = min(viewH * 4, viewH / CGFloat(d))
            topY[j] = viewMidY + lineH / 2
            botY[j] = viewMidY - lineH / 2
        }
        let w = size.width / CGFloat(columns)
        for i in 0..<columns {
            let xL = CGFloat(i) * w, xR = CGFloat(i + 1) * w + 1   // 1px overlap hides AA seams between quads
            let p = CGMutablePath()
            p.move(to: CGPoint(x: xL, y: botY[i]))
            p.addLine(to: CGPoint(x: xL, y: topY[i]))
            p.addLine(to: CGPoint(x: xR, y: topY[i + 1]))
            p.addLine(to: CGPoint(x: xR, y: botY[i + 1]))
            p.closeSubpath()
            bars[i].path = p
            let d = (dist[i] + dist[i + 1]) / 2
            zbuf[i] = min(dist[i], dist[i + 1])
            let f = CGFloat(max(0.12, min(1.0, 1.0 - d / 16))) * (sides[i] == 1 ? 0.62 : 1.0)
            bars[i].fillColor = SKColor(red: 0.02 + 0.02 * f, green: 0.05 + 0.45 * f, blue: 0.10 + 0.88 * f, alpha: 1)
        }
        projectSprites(dirX: dirX, dirY: dirY, planeX: planeX, planeY: planeY)
        updateMap()
    }

    private func projectSprites(dirX: Double, dirY: Double, planeX: Double, planeY: Double) {
        let invDet = 1.0 / (planeX * dirY - dirX * planeY)
        var all: [(node: SKNode, nativeH: CGFloat, worldH: CGFloat, x: Double, y: Double)] = []
        for b in billboards where b.alive {
            all.append((b.node, b.nativeH, b.worldH, b.x, b.y))
        }
        for item in all {
            let node = item.node
            let relX = item.x - camX, relY = item.y - camY
            let tX = invDet * (dirY * relX - dirX * relY)
            let tY = invDet * (-planeY * relX + planeX * relY)   // depth
            guard tY > 0.15 else { node.isHidden = true; continue }
            let col = Int((size.width / 2) * CGFloat(1 + tX / tY) / (size.width / CGFloat(columns)))
            // Occlude against the wall depth at the sprite's center column.
            if col >= 0, col < columns, tY > zbuf[col] + 0.1 { node.isHidden = true; continue }
            if tY > 18 { node.isHidden = true; continue }       // far cull
            let screenX = (size.width / 2) * CGFloat(1 + tX / tY)
            guard screenX > -60, screenX < size.width + 60 else { node.isHidden = true; continue }
            let targetH = viewH / CGFloat(tY) * item.worldH
            let s = targetH / item.nativeH
            node.isHidden = false
            node.setScale(s)
            // Stand on the corridor floor: bottom of the slice at this depth.
            let floorY = viewMidY - (viewH / CGFloat(tY)) / 2
            node.position = CGPoint(x: screenX, y: floorY + targetH / 2)
            node.zPosition = min(40, CGFloat(2 + 30 / tY))      // nearer over farther, but always behind Pete
        }
    }

    private func updateMap() {
        mapPete.position = mapLocal(px, py)
        let dir: MoveDirection = moveDir.x > 0 ? .right : moveDir.x < 0 ? .left : moveDir.y > 0 ? .down : .up
        mapPete.setFacing(dir)
    }

    // MARK: - Lane movement (Pac-Man style: auto-forward, turn at junctions)
    private func step() {
        var da = targetAngle - angle
        while da > .pi { da -= 2 * .pi }; while da < -.pi { da += 2 * .pi }
        angle += max(-0.14, min(0.14, da))

        let speed = 0.05
        let dx = tcx - px, dy = tcy - py
        let dist = (dx * dx + dy * dy).squareRoot()
        if dist <= speed {
            px = tcx; py = tcy
            let col = Int(px.rounded(.down)), row = Int(py.rounded(.down))
            if let wd = wantDir, open(col + wd.x, row + wd.y) { moveDir = wd; wantDir = nil }
            if open(col + moveDir.x, row + moveDir.y) {
                tcx = Double(col + moveDir.x) + 0.5
                tcy = Double(row + moveDir.y) + 0.5
                targetAngle = cardinal(moveDir)
            }
        } else {
            px += dx / dist * speed; py += dy / dist * speed
        }
        for i in billboards.indices where billboards[i].alive && billboards[i].worldH < 0.5 {
            if abs(billboards[i].x - px) < 0.5 && abs(billboards[i].y - py) < 0.5 {
                billboards[i].alive = false; billboards[i].node.isHidden = true
                mapPickups[mapKey(Int(billboards[i].x), Int(billboards[i].y))]?.isHidden = true
            }
        }
        bob += 0.22
        pete.position = CGPoint(x: size.width / 2, y: peteBaseY + CGFloat(sin(bob) * 4))
    }

    private func exit() {
        view?.presentScene(TitleScene(size: size), transition: .fade(withDuration: 0.5))
    }

    // MARK: - Input (steer at junctions, relative to facing)
    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case KeyCode.esc:                       exit()
        case KeyCode.keyP:                      togglePause()
        case KeyCode.arrowLeft,  KeyCode.keyA:  wantDir = (x: moveDir.y, y: -moveDir.x)
        case KeyCode.arrowRight, KeyCode.keyD:  wantDir = (x: -moveDir.y, y: moveDir.x)
        case KeyCode.arrowDown,  KeyCode.keyS:  wantDir = (x: -moveDir.x, y: -moveDir.y)
        case KeyCode.arrowUp,    KeyCode.keyW:  wantDir = moveDir
        default:                                break
        }
    }

    required init?(coder: NSCoder) { fatalError(Strings.System.initCoderUnsupported) }
    override init(size: CGSize) { super.init(size: size) }
}
