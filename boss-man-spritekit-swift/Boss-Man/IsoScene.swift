import SpriteKit
import AppKit

// 3D bonus round: the office maze (level 1) rendered first/third-person with flat
// 2D graphics — a Wolfenstein-style DDA raycaster for the walls, a smooth blended
// sunset sky, and billboarded game sprites (pellets, gold discs, bosses) standing
// in the corridors. The camera trails behind Pete so you see him walking ahead of
// you. A top-down radar sits at the bottom. Common to both ports.
final class IsoScene: SKScene, BossControllerDelegate, WorkerControllerDelegate, SKTouchResponder {

    // MARK: - Maze (loaded for the selected level; the editor's test plays the edited rows)
    private lazy var map: [[Character]] =
        LevelStore.loadLevel(index: max(0, min(state.level - 1, Levels.levelNames.count - 1))).map { Array($0) }
    private var rowsCount: Int { map.count }
    private var colsCount: Int { map.first?.count ?? 0 }

    // Set by the caller before the scene is presented. The title launches level 1
    // (BOSS 3D); the level editor's test launches the edited level in practice mode.
    var startingLevel: Int {
        get { state.level }
        set { state.level = max(1, newValue) }
    }
    var practiceMode: Bool {
        get { state.practiceMode }
        set { state.practiceMode = newValue }
    }

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
        guard r >= 0, r < rowsCount, c >= 0, c < map[r].count else { return false }
        return map[r][c] != Strings.Tile.wallChar
    }
    private func cardinal(_ d: (x: Int, y: Int)) -> Double {
        if d.x > 0 { return 0 }; if d.x < 0 { return .pi }
        return d.y > 0 ? .pi / 2 : -.pi / 2
    }

    // MARK: - Layout / projection
    private let columns = 220
    private let planeScale = 1.2              // tan(fov/2): wide ~100° FOV so a big swath of maze shows left/right
    private var radarH: CGFloat = 180
    private var viewH: CGFloat { size.height - radarH }
    private var viewMidY: CGFloat { radarH + viewH * 0.70 }   // horizon, lifted for a look-down view
    // Overhead-ish framing so the whole maze reads: a raised camera (eyeHeight > 0.5 drops the
    // walls below the horizon = looking DOWN on the maze) plus shorter walls you can see over.
    // 0.5 / 1.0 is the flat eye-level look; raise eyeHeight and lower wallHeightScale to tilt down.
    private let eyeHeight: CGFloat = 0.7
    private let wallHeightScale: CGFloat = 0.5
    private let maxVoxelDist = 30.0          // how far down the maze the voxel-span march draws
    private var wallQuads: [SKShapeNode] = []   // painter's-sorted wall face + cap quads (grows lazily)
    // A run of adjacent columns hitting the same wall face, merged into one straight-edged quad.
    private struct WallRun {
        var firstCol: Int, lastCol: Int
        var yLoA: CGFloat, yHiA: CGFloat   // span at the first column's centre
        var yLoB: CGFloat, yHiB: CGFloat   // span at the last column's centre
        var depthSum: Double, n: Int, side: Int, par: Int
    }
    private let floorA = SKShapeNode()   // alternating floor-tile checker, cast per frame
    private let floorB = SKShapeNode()
    private let floorFar = SKShapeNode()  // far rows: solid (the checker aliases to garbage at distance)
    private var zbuf: [Double] = []

    // MARK: - Billboards (pooled: built once, projected each frame)
    private struct Billboard { let node: SKNode; let nativeH: CGFloat; let worldH: CGFloat; let x, y: Double; var alive: Bool }
    private var billboards: [Billboard] = []

    // MARK: - Bosses — the REAL BossController from the 100% game (speed, square +
    // smooth modes, flee/splash/capture/respawn all inherited; nothing hand-rolled).
    private var gridMap: GridMap!
    private var pathfinder: Pathfinder!
    private var bossController: BossController!
    private var travelerSpawner: TravelerSpawner!   // the fish/treat that walks across the maze (same spawner as 2D)
    private var workerController: WorkerController!  // REAL 2D physics for Pete (TileMover collision); iso/minimap render from it
    private let workerHost = SKNode()               // hidden parent so the mover runs; Pete is drawn in iso + minimap from worker.grid
    private var bossMapNodes: [ObjectIdentifier: PixelPerson] = [:]   // radar mirror per boss node
    private var bossNativeH: [ObjectIdentifier: CGFloat] = [:]        // cached unscaled height for projection
    private var bossFeet: [ObjectIdentifier: CGFloat] = [:]           // cached LOCAL feet offset (frame.minY relative to origin)
    private var bossGrid: [ObjectIdentifier: (Double, Double)] = [:]  // smooth (continuous) grid pos per boss, captured pre-projection
    private var peteShielded = false
    private struct Shot { var x, y: Double; let dir: (x: Int, y: Int); let node: SKNode; let nativeH: CGFloat; let mapNode: SKNode; var alive: Bool }
    private var shots: [Shot] = []
    private var gameOver = false
    private var gameOverScreen: GameOverScreen?
    private var dying = false
    private var deathFramesLeft = 0
    private let deathFrames = 90   // 1.5s at 60fps: hold the catcher on screen
    private var pressed = Set<Int>()
    private var collected = Set<Int>()
    private let sound = SoundManager()

    // MARK: - On-screen controls (same layout/sizing as the 100% game)
    private let joystickRadius: CGFloat = 129.375
    private let joystickDeadzone: CGFloat = 20   // D-pad centre hole + input deadzone (smaller = more reach)
    private var joystickCenter = CGPoint.zero
    // X-pattern D-pad: four ring-sector wedges (up/down/left/right) split by an X.
    // Each finger lights at most one wedge; two fingers light two (forward + a turn)
    // ONLY when the phone actually has two fingers down. Keyed "up/down/left/right".
    private var dpadWedges: [String: SKShapeNode] = [:]
    private var dpadFinger: [Int: String] = [:]   // active finger id -> its wedge
    private var usingTouch = false                 // a real touch arrived: ignore the synthetic mouse pointer
    private var fireButtonCenter = CGPoint.zero
    private let fireButtonRadius: CGFloat = 129.375
    private var controlsShown = false

    private let spriteLayer = SKNode()
    private let nameLayer = SKNode()
    private var bossNames: [ObjectIdentifier: SKLabelNode] = [:]
    private var peteName: SKLabelNode!
    private var pete: PixelPerson!
    private var peteBaseY: CGFloat = 0
    private var bob = 0.0
    private var throbClock = 0.0   // free-running clock for the post-spawn boss pulse

    private var hud: HUD!
    private let uiLayer = SKNode()
    private let state = RoundState()
    private let waterGun = WaterGunState()
    private var waterGunPickedUp = false
    private let goldDisc = GoldDiscTimer()
    private let goldDiscDuration: TimeInterval = 20
    private var frightenSecondsLeft: TimeInterval = 0
    private let reportItemPoints = [10, 25, 50, 100]
    private var onBrownBox = false
    private var spawnPx = 1.5, spawnPy = 1.5
    private var isUserPaused = false

    // MARK: - Minimap (the real 2D level, centered at the bottom)
    private let mapLayer = SKNode()
    private var mapPete: PixelPerson!
    private var mapPickups: [Int: SKNode] = [:]
    private let mapCell: CGFloat = 32
    private var mapScale: CGFloat = 1

    // MARK: - Isometric world (1-POINT PERSPECTIVE: a fixed elevated camera looks north across the whole
    // board; the grid recedes to a centre vanishing point, the near row spans the full screen width and
    // far rows converge — raised blocks for walls, yellow squares for dots. The camera never moves, so the
    // maze is projected ONCE at build time; only the moving sprites are projected per frame.)
    private let isoWorld = SKNode()
    private let isoMaze = SKNode()
    private var isoDotRowCells: [Int: [Int]] = [:]    // row -> columns holding a dot; batched per row (body + lit top)
    private var isoDotFrontNode: [Int: SKShapeNode] = [:]
    private var isoDotSideNode: [Int: SKShapeNode] = [:]
    private var isoDotTopNode: [Int: SKShapeNode] = [:]
    private var isoDotCollected: Set<Int> = []        // collected mapKeys; the row nodes are rebuilt (rarely) on pickup
    private var isoDotsLeft = 0
    private var isoPickups: [Int: SKNode] = [:]        // water gun / pellets / machine emojis / brown box, built once, hidden|grayed on collect
    private var isoTraveler: SKNode?                   // iso mirror of the walking traveler (the REAL node keeps its SKAction walk in the scene root)
    private var isoTravelerEmoji = ""
    private var mapTraveler: SKNode?                   // minimap mirror of the traveler (kept in sync with the iso mirror)
    private var mapTravelerEmoji = ""
    private var travCol = 0.0, travRow = 0.0          // SMOOTHED traveler position (glides between its discrete grid tiles)
    private var travActive = false
    private var travFlip: CGFloat = 1                 // horizontal facing (same convention as the 2D traveler)

    // PARALLEL overhead projection (no vanishing point = a true top-down/isometric look, not a horizon).
    // The board is tilted down (TH < TW vertical squash) with short raised blocks; depth = row. Because
    // it is parallel, the whole board projects ONCE and the view simply translates to follow Pete (ZOOM 2D
    // scroll) with no re-projection, and sprites keep a constant size (no depth shrink, no jitter).
    private var isoTW: CGFloat = 0, isoTH: CGFloat = 0, isoWH: CGFloat = 0
    private func setupProjection() {
        let zoom: CGFloat = 2.4                                     // ZOOMED IN: bigger tiles/lanes; the view scrolls to follow Pete, the minimap shows the rest
        isoTW = size.width / CGFloat(max(1, colsCount)) * zoom      // tile width
        isoTH = isoTW * 0.62                                        // more top-down (TH closer to TW = more overhead)
        isoWH = isoTW * 0.46 - 2                                    // blocks, 2px lower
        pVpY = isoTH * 6                                            // vanishing line above the far edge (depth converges toward it)
    }
    private let pFocal = 70.0                                      // 1-pt depth convergence strength (smaller = stronger)
    private var pVpY: CGFloat = 0                                   // vanishing line above the far edge
    private func persp(_ rowEdge: Double) -> CGFloat { CGFloat(pFocal / (pFocal + (Double(rowsCount) - rowEdge))) }

    // 1-POINT PERSPECTIVE: the whole board converges toward a centre vanishing point with depth. Vertical
    // wall edges (constant col+row, varying height) stay perfectly vertical; only the depth (top) edges
    // converge. Walls are drawn front + top only (no side faces) so there are no slanted side trapezoids.
    private func proj(_ colEdge: Double, _ rowEdge: Double, _ y: CGFloat) -> CGPoint {
        let p = persp(rowEdge)
        let x0 = (CGFloat(colEdge) - CGFloat(colsCount) / 2) * isoTW
        let y0 = -CGFloat(rowEdge) * isoTH + y * isoWH
        return CGPoint(x: x0 * p, y: pVpY + (y0 - pVpY) * p)
    }
    private func perspScale(_ row: Double) -> CGFloat { persp(row) } // sprites shrink slightly with depth

    private func quadPath(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPath {
        let p = CGMutablePath(); p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.addLine(to: d); p.closeSubpath(); return p
    }
    @discardableResult private func addQuad(_ path: CGPath, _ fill: SKColor, _ stroke: SKColor, _ z: CGFloat) -> SKShapeNode {
        let n = SKShapeNode(path: path); n.fillColor = fill; n.strokeColor = stroke; n.lineWidth = 0.5; n.isAntialiased = false; n.zPosition = z
        isoMaze.addChild(n); return n
    }
    private func addSub(_ p: CGMutablePath, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) {
        p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.addLine(to: d); p.closeSubpath()
    }
    // One RAISED dot block: near (south) face into `front`, a position-based side into `side`, lit top.
    private func appendDotFaces(_ front: CGMutablePath, _ side: CGMutablePath, _ top: CGMutablePath, _ c: Int, _ r: Int, _ gold: Bool) {
        let h = gold ? 0.28 : 0.20
        let cx0 = Double(c) + 0.5, ry0 = Double(r) + 0.5, mid = Double(colsCount) / 2
        let yT = ((gold ? 1.2 : 0.95) * isoWH - 3) / max(1, isoWH)     // dot block height, 3px lower
        let bNW = proj(cx0 - h, ry0 - h, 0), bNE = proj(cx0 + h, ry0 - h, 0)
        let bSE = proj(cx0 + h, ry0 + h, 0), bSW = proj(cx0 - h, ry0 + h, 0)
        let uNW = proj(cx0 - h, ry0 - h, yT), uNE = proj(cx0 + h, ry0 - h, yT)
        let uSE = proj(cx0 + h, ry0 + h, yT), uSW = proj(cx0 - h, ry0 + h, yT)
        addSub(front, bSW, bSE, uSE, uSW)                                  // near (south) face
        if cx0 < mid { addSub(side, bNE, bSE, uSE, uNE) }                  // east face (left of centre)
        else if cx0 > mid { addSub(side, bNW, bSW, uSW, uNW) }             // west face (right of centre)
        addSub(top, uNW, uNE, uSE, uSW)                                    // lit top
    }
    private func isDotTile(_ ch: Character) -> Bool {
        ch == Strings.Tile.dotChar || ch == Strings.Tile.hideoutChar   // gold disc is a round billboard, not a raised block
    }

    private func buildIso() {
        setupProjection()
        let cube = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]
        // Alternating cubicle blocks (VOXEL 3D parity): even cells dimmed to ~82%, odd cells full.
        let cubeP = [cube.blended(withFraction: 0.18, of: .black) ?? cube, cube]
        var topP = [SKColor](), frontP = [SKColor](), sideP = [SKColor](), edgeP = [SKColor]()
        for base in cubeP {
            topP.append(base)
            frontP.append(base.blended(withFraction: 0.30, of: .black) ?? base)
            sideP.append(base.blended(withFraction: 0.50, of: .black) ?? base)
            edgeP.append(base.blended(withFraction: 0.22, of: .white) ?? base)
        }
        // Checkerboard floor (VOXEL 3D): two shades by (col+row) parity.
        let floorP = [SKColor(white: 0.07, alpha: 1), SKColor(white: 0.14, alpha: 1)]
        let floorEdge = SKColor(white: 0.16, alpha: 1)
        let dotFront = SKColor.systemYellow.blended(withFraction: 0.30, of: .black) ?? .systemYellow   // same shading the walls use
        let dotSide  = SKColor.systemYellow.blended(withFraction: 0.50, of: .black) ?? .systemYellow
        let mid = Double(colsCount) / 2
        // FPS: coalesce same-colour faces of a depth row into ONE SKShapeNode (many subpaths, one draw).
        // Parity splits each face-type into two nodes (even/odd) so the checker + block alternation reads.
        for r in 0..<rowsCount {
            let row = map[r]
            let z = CGFloat(r) * 4                          // near rows (high r) draw over far rows (painter's)
            let pFloor = [CGMutablePath(), CGMutablePath()], pFront = [CGMutablePath(), CGMutablePath()]
            let pSide = [CGMutablePath(), CGMutablePath()], pTop = [CGMutablePath(), CGMutablePath()]
            var hasFloor = [false, false], hasFront = [false, false], hasSide = [false, false], hasTop = [false, false]
            var dotCols: [Int] = []
            for c in 0..<min(colsCount, row.count) {
                let ch = row[c]; let dc = Double(c); let par = (c + r) & 1
                let fNW = proj(dc, Double(r), 0), fNE = proj(dc + 1, Double(r), 0)
                let fSE = proj(dc + 1, Double(r + 1), 0), fSW = proj(dc, Double(r + 1), 0)
                if ch == Strings.Tile.wallChar {
                    let tNW = proj(dc, Double(r), 1), tNE = proj(dc + 1, Double(r), 1)
                    let tSE = proj(dc + 1, Double(r + 1), 1), tSW = proj(dc, Double(r + 1), 1)
                    addSub(pFront[par], fSW, fSE, tSE, tSW); hasFront[par] = true
                    if dc + 0.5 < mid { addSub(pSide[par], fNE, fSE, tSE, tNE); hasSide[par] = true }   // east face (left of centre)
                    else if dc + 0.5 > mid { addSub(pSide[par], fNW, fSW, tSW, tNW); hasSide[par] = true }   // west face (right of centre)
                    addSub(pTop[par], tNW, tNE, tSE, tSW); hasTop[par] = true
                } else {
                    addSub(pFloor[par], fNW, fNE, fSE, fSW); hasFloor[par] = true
                    if isDotTile(ch) { dotCols.append(c) }
                }
            }
            for par in 0...1 {
                if hasFloor[par] { addQuad(pFloor[par], floorP[par], floorEdge, z - 1) }
                if hasSide[par]  { addQuad(pSide[par], sideP[par], sideP[par], z + 0.1) }
                if hasFront[par] { addQuad(pFront[par], frontP[par], frontP[par], z + 0.2) }
                if hasTop[par]   { addQuad(pTop[par], topP[par], edgeP[par], z + 0.3) }
            }
            if !dotCols.isEmpty {                            // the row's dots batched (front + side + top, like the walls); rebuilt only on pickup
                isoDotRowCells[r] = dotCols
                let pF = CGMutablePath(), pS = CGMutablePath(), pT = CGMutablePath()
                for c in dotCols { appendDotFaces(pF, pS, pT, c, r, map[r][c] == Strings.Tile.goldDiscChar) }
                isoDotSideNode[r]  = addQuad(pS, dotSide, dotSide, z + 0.55)
                isoDotFrontNode[r] = addQuad(pF, dotFront, dotFront, z + 0.6)
                isoDotTopNode[r]   = addQuad(pT, .systemYellow, .systemYellow, z + 0.7)
                isoDotsLeft += dotCols.count
            }
        }
    }

    private func rebuildDotRow(_ r: Int) {
        guard let cols = isoDotRowCells[r] else { return }
        let pF = CGMutablePath(), pS = CGMutablePath(), pT = CGMutablePath()
        for c in cols where !isoDotCollected.contains(mapKey(c, r)) { appendDotFaces(pF, pS, pT, c, r, map[r][c] == Strings.Tile.goldDiscChar) }
        isoDotFrontNode[r]?.path = pF
        isoDotSideNode[r]?.path = pS
        isoDotTopNode[r]?.path = pT
    }

    // The non-dot collectibles (water gun, pellets, the 4 TPS machines, the brown box) as iso emoji
    // billboards, built ONCE and planted on their tile — hidden/grayed on pickup, mirrored in the minimap.
    private func buildIsoPickups() {
        let s = isoTW * 0.7
        for r in 0..<rowsCount {
            let row = map[r]
            for c in 0..<min(colsCount, row.count) {
                let node: SKNode
                switch row[c] {
                case Strings.Tile.waterGunChar:    node = throbbing(emojiBillboard(Strings.Emoji.waterGun, s), 1.18, 0.5)
                case Strings.Tile.printerChar:     node = emojiBillboard(Strings.Emoji.printer, s)
                case Strings.Tile.faxChar:         node = emojiBillboard(Strings.Emoji.fax, s)
                case Strings.Tile.coverSheetChar:  node = emojiBillboard(Strings.Emoji.coverSheet, s)
                case Strings.Tile.bookBinderChar:  node = emojiBillboard(Strings.Emoji.bookBinder, s)
                case Strings.Tile.brownBoxChar:    node = emojiBillboard(Strings.Emoji.brownBox, s)
                case Strings.Tile.waterPelletChar: node = throbbing(SpriteFactory.waterPelletVisual(radius: isoTW * 0.3), 1.25, 0.5)
                case Strings.Tile.goldDiscChar:    node = throbbing(SpriteFactory.goldDiscVisual(radius: isoTW * 0.34), 1.18, 0.5)   // round disc, not a yellow block
                default: continue
                }
                spriteLayer.addChild(node)
                placeIsoSprite(node, CGFloat(c) + 0.5, CGFloat(r) + 0.5, s)
                node.position.y += 6                            // raise the TPS/machine emojis 6px
                node.zPosition = CGFloat(r) * 4 + 0.55          // above the row's blocks, below Pete
                isoPickups[mapKey(c, r)] = node
            }
        }
    }

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60
        anchorPoint = .zero
        backgroundColor = .black
        placeStart()
        isoWorld.zPosition = 0
        addChild(isoWorld)
        isoWorld.addChild(isoMaze)
        spriteLayer.zPosition = 0
        isoWorld.addChild(spriteLayer)       // Pete + bosses ride in world space and depth-sort against the blocks
        nameLayer.zPosition = 150
        isoWorld.addChild(nameLayer)
        workerHost.alpha = 0                 // the real worker runs here, hidden; Pete is drawn in iso + minimap from its grid
        addChild(workerHost)
        buildIso()
        buildIsoPickups()                    // water gun / pellets / machine emojis / brown box in the iso world
        buildPete()
        buildMap()                           // the 2D minimap: the real tilemap + worker + bosses
        setupBossController()
        buildHUD()
        buildControls()
        render()
        sound.startBackgroundMusic()
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
        spawnPx = px; spawnPy = py
        for d in [(x: 1, y: 0), (x: 0, y: 1), (x: -1, y: 0), (x: 0, y: -1)] where open(sc + d.x, sr + d.y) {
            moveDir = d; break
        }
        targetAngle = cardinal(moveDir); angle = targetAngle
    }

    private func buildSky() {
        // 2D office palette: a dark ceiling (maze background) blending toward the
        // horizon over the dark checker-floor colour. One thin band per device row
        // so the gradient is smooth, then baked to a single sprite (the bands are
        // static, so this is ~240 fewer draw calls per frame on Apple).
        // Ceiling + floor derive from the level's cubicle colour (dark at the ceiling,
        // a touch brighter at the horizon) so the whole 3D environment matches the level.
        let cube = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]
        let tree = SKNode()
        let skyBottom = viewMidY, skyTop = size.height
        let n = max(1, Int(skyTop - skyBottom))
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(max(1, n - 1))      // 0 horizon .. 1 ceiling
            let factor = 0.18 + (0.05 - 0.18) * t            // cube brightness: horizon -> ceiling
            let col = cube.blended(withFraction: 1 - factor, of: .black) ?? cube
            let band = SKShapeNode(rect: CGRect(x: 0, y: skyBottom + CGFloat(i), width: size.width, height: 2))
            band.fillColor = col; band.strokeColor = .clear
            tree.addChild(band)
        }
        let ground = SKShapeNode(rect: CGRect(x: 0, y: radarH, width: size.width, height: viewMidY - radarH))
        ground.fillColor = cube.blended(withFraction: 0.88, of: .black) ?? cube   // dark level-tinted floor base
        ground.strokeColor = .clear
        tree.addChild(ground)
        addBaked(tree, to: self, z: -3)

        // Alternating floor-tile checker (cast per frame in castFloor), drawn above the
        // baked ground (z -3) and below the walls (z 0). Two nodes, one per shade.
        floorA.fillColor = cube.blended(withFraction: 0.87, of: .black) ?? cube   // ~cube * 0.13
        floorB.fillColor = cube.blended(withFraction: 0.76, of: .black) ?? cube   // ~cube * 0.24
        floorFar.fillColor = cube.blended(withFraction: 0.81, of: .black) ?? cube   // mid shade between A/B
        floorA.strokeColor = .clear; floorB.strokeColor = .clear; floorFar.strokeColor = .clear
        floorA.zPosition = -2; floorB.zPosition = -2; floorFar.zPosition = -2
        floorA.isAntialiased = false; floorB.isAntialiased = false; floorFar.isAntialiased = false
        addChild(floorA); addChild(floorB); addChild(floorFar)
    }

    // Floor-cast the maze floor as an alternating checker so the tile grid reads in 3D
    // (matches the C++ DoomScene::drawFloor). Each scene row below the horizon maps to a
    // perpendicular distance; the world position sweeps left-ray -> right-ray across the
    // row; cell parity picks the shade. Coalesced into per-row run rects in two paths.
    private func castFloor() {
        let dirX = cos(angle), dirY = sin(angle)
        let planeX = -dirY * planeScale, planeY = dirX * planeScale
        let rdx0 = dirX - planeX, rdy0 = dirY - planeY
        let rdx1 = dirX + planeX, rdy1 = dirY + planeY
        let W = size.width, rowH: CGFloat = 2
        let pathA = CGMutablePath(), pathB = CGMutablePath(), pathFar = CGMutablePath()
        var yu = radarH
        while yu < viewMidY - 0.5 {
            let distFromHorizon = Double(viewMidY - yu)
            let d = Double(viewH) * Double(eyeHeight) / distFromHorizon
            if d > 13 {   // checker cells shrink below ~1px here and alias to garbage; fill solid to the horizon
                pathFar.addRect(CGRect(x: 0, y: yu, width: W, height: rowH))
                yu += rowH
                continue
            }
            let fx0 = camX + d * rdx0, fy0 = camY + d * rdy0
            let stepX = d * (rdx1 - rdx0) / Double(W), stepY = d * (rdy1 - rdy0) / Double(W)
            var runStart: CGFloat = 0
            var runParity = (Int(fx0.rounded(.down)) + Int(fy0.rounded(.down))) & 1
            var x: CGFloat = 1
            while x <= W {
                var parity = -1
                if x < W {
                    let wx = fx0 + stepX * Double(x), wy = fy0 + stepY * Double(x)
                    parity = (Int(wx.rounded(.down)) + Int(wy.rounded(.down))) & 1
                }
                if parity != runParity {
                    let r = CGRect(x: runStart, y: yu, width: x - runStart, height: rowH)
                    if runParity == 1 { pathA.addRect(r) } else { pathB.addRect(r) }
                    runStart = x; runParity = parity
                }
                x += 1
            }
            yu += rowH
        }
        floorA.path = pathA; floorB.path = pathB; floorFar.path = pathFar
    }

    // Bake a static node tree to one texture and add it as a single sprite (one
    // draw call). Falls back to the live tree if no view is available to bake with.
    private func addBaked(_ tree: SKNode, to parent: SKNode, z: CGFloat) {
        if let tex = view?.texture(from: tree) {
            let sprite = SKSpriteNode(texture: tex)
            let f = tree.calculateAccumulatedFrame()
            sprite.position = CGPoint(x: f.midX, y: f.midY)
            sprite.zPosition = z
            parent.addChild(sprite)
        } else {
            tree.zPosition = z
            parent.addChild(tree)
        }
    }

    private func buildColumns() {
        // Wall quads are pooled lazily in render() (count varies with the view).
    }

    private func emojiBillboard(_ text: String, _ fontSize: CGFloat) -> SKNode {
        let label = SKLabelNode(fontNamed: Strings.Font.menlo)
        label.text = text; label.fontSize = fontSize
        label.verticalAlignmentMode = .center; label.horizontalAlignmentMode = .center
        guard let tex = view?.texture(from: label) else { return label }
        tex.filteringMode = .linear      // interpolate (smooth) when the raycaster scales it
        return SKSpriteNode(texture: tex)
    }

    // Wrap a power-up visual so it throbs in the 3D view: the raycaster scales the
    // PARENT each frame, the throb runs on the CHILD, so the two multiply instead of
    // the projection clobbering the pulse (matching MazeBuilder's throb).
    private func throbbing(_ visual: SKNode, _ peak: CGFloat, _ dur: TimeInterval) -> SKNode {
        let parent = SKNode()
        parent.addChild(visual)
        visual.run(.repeatForever(.sequence([.scale(to: peak, duration: dur), .scale(to: 1.0, duration: dur)])))
        return parent
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
                    node = throbbing(SpriteFactory.goldDiscVisual(radius: 10), 1.25, 0.35); worldH = 0.4
                case Strings.Tile.waterPelletChar:
                    node = throbbing(SpriteFactory.waterPelletVisual(radius: 10), 1.3, 0.4); worldH = 0.4
                case Strings.Tile.waterGunChar:   node = throbbing(emojiBillboard(Strings.Emoji.waterGun, 128), 1.25, 0.35); worldH = 0.5
                case Strings.Tile.printerChar:    node = emojiBillboard(Strings.Emoji.printer, 128); worldH = 0.6
                case Strings.Tile.faxChar:        node = emojiBillboard(Strings.Emoji.fax, 128); worldH = 0.6
                case Strings.Tile.coverSheetChar: node = emojiBillboard(Strings.Emoji.coverSheet, 128); worldH = 0.6
                case Strings.Tile.bookBinderChar: node = emojiBillboard(Strings.Emoji.bookBinder, 128); worldH = 0.6
                case Strings.Tile.brownBoxChar:   node = emojiBillboard(Strings.Emoji.brownBox, 128); worldH = 0.6
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
        pete = SpriteFactory.petePerson(walkExaggeration: 1)   // iso looks down on Pete from the front, not his back
        let nativeH = max(1, pete.calculateAccumulatedFrame().height)
        let target = viewH * 0.42
        pete.setScale(target / nativeH)
        pete.zPosition = 90                          // above every billboard, so pellets pass behind him
        peteBaseY = radarH + target / 2 + 6
        pete.position = CGPoint(x: size.width / 2, y: peteBaseY)
        spriteLayer.addChild(pete)
        pete.startWalking()
        peteName = makeNameplate(Strings.Worker.pete)
        peteName.position = CGPoint(x: size.width / 2, y: peteBaseY + target / 2 + 16)
        nameLayer.addChild(peteName)
    }

    private func makeNameplate(_ text: String) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: Strings.Font.menloBold)
        l.text = text
        l.fontSize = 22
        l.fontColor = .white
        l.horizontalAlignmentMode = .center
        l.verticalAlignmentMode = .center
        return l
    }

    private func buildHUD() {
        uiLayer.zPosition = 1000
        addChild(uiLayer)
        hud = HUD(requiredItems: Strings.Machine.required)
        hud.install(in: uiLayer, size: size, extraRow: false)   // compact 150/200-style HUD, never the extended row
        state.dotCount = map.reduce(0) { $0 + $1.filter { $0 == Strings.Tile.dotChar || $0 == Strings.Tile.hideoutChar }.count }
        refreshHUD()
    }

    private func refreshHUD() {
        hud.updateStatus(score: state.score, highScore: state.highScore, level: state.level,
                         dots: state.collectedDots, total: state.dotCount,
                         reports: state.tpsReportsDelivered, items: state.reportItems)
        hud.updateLives(state.lives)
        hud.updateWaterGun(active: waterGun.isActive, pellets: waterGunPickedUp ? waterGun.pelletsRemaining : -1, blueMode: false)
        hud.updateLevelEmojis(Array(levelTravelers.prefix(1)))
    }

    private func startGoldDiscMode() {
        goldDisc.activate()
        bossController.setGoldDiscActive(true)   // recolors the real boss nodes (the 3D billboards) to flee blue
        recolorMinimapBosses(flee: true)         // mirror it on the radar copies
        sound.startGoldDiscBass()
        frightenSecondsLeft = goldDiscDuration
        hud.showMessage(Strings.Message.goldDiscActivated, duration: 3)
        refreshHUD()
    }
    private func endGoldDiscMode() {
        goldDisc.deactivate()
        bossController.setGoldDiscActive(false)
        recolorMinimapBosses(flee: false)
        sound.stopGoldDiscBass()
        frightenSecondsLeft = 0
        hud.showMessage(Strings.Message.goldDiscEnded, duration: 2)
        refreshHUD()
    }

    // The radar bosses are mirror nodes (a node can't have two parents), so they
    // need the same flee palette BossController paints on the real nodes.
    private static let bossSkin = NSColor(calibratedRed: 0.96, green: 0.78, blue: 0.62, alpha: 1)
    private func recolorMinimapBosses(flee: Bool) {
        for e in bossController.entities {
            guard let mn = bossMapNodes[ObjectIdentifier(e.node)] else { continue }
            applyFleePalette(mn, flee: flee, blueprint: e.blueprintIndex)
        }
    }
    private func applyFleePalette(_ p: PixelPerson, flee: Bool, blueprint: Int) {
        if flee {
            p.setBodyColor(SpriteFactory.fleeBodyColor)
            p.setTieColor(SpriteFactory.fleeTieColor)
            p.setShirtOutlineColor(NSColor(calibratedWhite: 1, alpha: 0.75))
            p.setEyeColor(SpriteFactory.fleeEyeColor)
            p.setSkinColor(SpriteFactory.fleeSkinColor)
        } else {
            let c = BossBlueprint.colors[min(max(blueprint, 0), BossBlueprint.colors.count - 1)]
            p.setBodyColor(c.body); p.setTieColor(c.tie)
            p.setShirtOutlineColor(.white); p.setEyeColor(.black); p.setSkinColor(Self.bossSkin)
        }
    }

    // Caught: hold the REAL catching boss still in front of Pete for ~1.5s (no fake sprite),
    // then dock a life and respawn. update() skips step()/render() while dying, so the boss
    // stays frozen exactly where we place it here.
    private func startDeath(node: PixelPerson) {
        if dying { return }
        dying = true
        _ = sound.playCaughtByBoss()
        if goldDisc.isActive { endGoldDiscMode() }
        pete.stopWalking()
        node.stopWalking()
        // No fake close-up in iso: the overhead view already shows the boss right where it caught Pete,
        // so just freeze in place for a beat (update() skips step/render while dying) then respawn.
        deathFramesLeft = deathFrames
    }

    private func updateDeath() {
        deathFramesLeft -= 1                          // hold the catcher on screen, still, then respawn
        if deathFramesLeft <= 0 { finishDeath() }
    }

    private func finishDeath() {
        dying = false                                 // projectSprites re-scales/re-shows every billboard on resume
        for (_, l) in bossNames { l.isHidden = false }
        state.lives -= 1
        refreshHUD()
        if state.lives <= 0 { gameOver = true; showGameOver(); return }
        let spawnGrid = CGPoint(x: Int(spawnPx), y: rowsCount - 1 - Int(spawnPy))
        workerController.teleport(to: spawnGrid)     // real engine respawn (resets the mover + grid)
        workerController.resetMotion()
        workerController.applySpawnShield()
        pressed.removeAll()
        px = spawnPx; py = spawnPy                   // keep the derived coords in sync for the first frame
        bossController.teleportAllToSpawn()   // 3s spawnGrace; peteShielded follows isAnyBossSpawning
        pete.alpha = 1
        pete.startWalking()
        pete.removeAction(forKey: "shield")
        pete.run(.sequence([.repeat(.sequence([.fadeAlpha(to: 0.35, duration: 0.6), .fadeAlpha(to: 1.0, duration: 0.6)]), count: 3),
                            .run { [weak self] in self?.pete.alpha = 1 }]), withKey: "shield")
    }

    // Grid-space catch (DoomScene has no physics worker body, so same-tile is the
    // catch); honors spawnGrace immobilization + the shield, like GameScene.
    private func checkBossCatch() {
        let pgx = Int(px.rounded(.down)), pgy = rowsCount - 1 - Int(py.rounded(.down))
        for e in bossController.entities {
            let bg = e.mover?.grid ?? e.ai.grid
            guard Int(bg.x) == pgx, Int(bg.y) == pgy, !bossController.isImmobilized(boss: e.node) else { continue }
            if bossController.isInFleeMode(boss: e.node) { bossController.capture(boss: e.node) }
            else if !peteShielded { startDeath(node: e.node); return }
        }
    }

    // MARK: - BossControllerDelegate (Pete reported in GridMap's bottom-up coords)
    var workerGrid: CGPoint { CGPoint(x: CGFloat(Int(px.rounded(.down))), y: CGFloat(rowsCount - 1 - Int(py.rounded(.down)))) }
    var workerDirection: MoveDirection? {
        if moveDir.x > 0 { return .right }
        if moveDir.x < 0 { return .left }
        return moveDir.y > 0 ? .down : .up
    }
    var isGoldDiscMode: Bool { goldDisc.isActive }
    var isPeteShielded: Bool { peteShielded }
    func bossDidCatchWorker() { }   // bonus catches via grid checkBossCatch() after advance (no physics contact)
    func bossDidGetCaptured(name: String, points: Int, at position: CGPoint) {
        state.bumpScore(by: points); sound.playCaptureBoss(streak: max(1, points / 100)); popPoints(points); refreshHUD()
    }
    // Bosses dodge an incoming water pellet, same as the 2D modes: report the travel
    // AXIS of any shot bearing down on this boss; BossController steps it perpendicular.
    private let dropletDodgeRange = 8
    func dropletAxisThreatening(_ bossGrid: CGPoint) -> MoveDirection? {
        for s in shots where s.alive {
            let dGrid = CGPoint(x: CGFloat(Int(s.x.rounded(.down))), y: CGFloat(rowsCount - 1 - Int(s.y.rounded(.down))))
            let dir: MoveDirection = s.dir.x > 0 ? .right : s.dir.x < 0 ? .left : (s.dir.y > 0 ? .down : .up)
            if dropletThreatens(dropletGrid: dGrid, dir: dir, boss: bossGrid) { return dir }
        }
        return nil
    }
    private func dropletThreatens(dropletGrid d: CGPoint, dir: MoveDirection, boss b: CGPoint) -> Bool {
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
        guard dist <= dropletDodgeRange else { return false }
        var step = d
        for _ in 0..<dist {
            step = CGPoint(x: step.x + CGFloat(dx), y: step.y + CGFloat(dy))
            if !gridMap.isWalkable(step) { return false }
        }
        return true
    }

    private func togglePause() {
        isUserPaused.toggle()
        hud.showPaused(isUserPaused)   // same PAUSED text the 2D game uses
        isoWorld.isPaused = isUserPaused   // freeze every SKAction (boss walks, pickup throbs)
        if isUserPaused { pete.stopWalking(); sound.pauseAudio() }
        else { pete.startWalking(); sound.resumeAudio() }
    }

    private func mapKey(_ c: Int, _ r: Int) -> Int { r * colsCount + c }
    private func mapLocal(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x) * mapCell, y: (CGFloat(rowsCount) - CGFloat(y)) * mapCell)
    }
    private func buildMap() {
        let panel = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: radarH))
        panel.fillColor = SKColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        panel.strokeColor = .clear; panel.zPosition = 200   // above every 3D sprite/nameplate so nothing ever draws over the minimap
        addChild(panel)

        let mapW = CGFloat(colsCount) * mapCell, mapH = CGFloat(rowsCount) * mapCell
        let cubicle = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]

        // The maze floor and cubicle walls never change, so we bake them to ONE
        // texture and draw a single sprite — the MazeBuilder trick the 100% game
        // uses — instead of ~2000 per-cell SKShapeNodes (Apple pays a draw call per
        // shape). Pickups, Pete and the chasing bosses stay live on top.
        let bakeTree = SKNode()
        for r in 0..<rowsCount {
            for (c, ch) in map[r].enumerated() {
                let center = mapLocal(Double(c) + 0.5, Double(r) + 0.5)
                let floor = SpriteFactory.floorTile(size: mapCell, alternate: (c + r) % 2 == 0)
                floor.position = center; bakeTree.addChild(floor)
                if ch == Strings.Tile.wallChar {
                    let wall = SpriteFactory.wallTile(size: mapCell, color: cubicle)
                    wall.position = center; bakeTree.addChild(wall)
                }
            }
        }
        addBaked(bakeTree, to: mapLayer, z: 0)

        // Dots all share one baked texture so they batch into ~one draw call; gold
        // and water keep their own node so each can be hidden when collected.
        let dotTex = view?.texture(from: SpriteFactory.dotVisual(size: mapCell * 0.2))
        for r in 0..<rowsCount {
            for (c, ch) in map[r].enumerated() {
                let center = mapLocal(Double(c) + 0.5, Double(r) + 0.5)
                var pickup: SKNode?
                switch ch {
                case Strings.Tile.dotChar, Strings.Tile.hideoutChar:
                    pickup = dotTex.map { SKSpriteNode(texture: $0) } ?? SpriteFactory.dotVisual(size: mapCell * 0.2)
                case Strings.Tile.goldDiscChar:    pickup = SpriteFactory.goldDiscVisual(radius: mapCell * 0.28)
                case Strings.Tile.waterPelletChar: pickup = SpriteFactory.waterPelletVisual(radius: mapCell * 0.32)
                case Strings.Tile.waterGunChar:    pickup = emojiBillboard(Strings.Emoji.waterGun, mapCell * 0.7)
                case Strings.Tile.printerChar:     pickup = emojiBillboard(Strings.Emoji.printer, mapCell * 0.7)
                case Strings.Tile.faxChar:         pickup = emojiBillboard(Strings.Emoji.fax, mapCell * 0.7)
                case Strings.Tile.coverSheetChar:  pickup = emojiBillboard(Strings.Emoji.coverSheet, mapCell * 0.7)
                case Strings.Tile.bookBinderChar:  pickup = emojiBillboard(Strings.Emoji.bookBinder, mapCell * 0.7)
                case Strings.Tile.brownBoxChar:    pickup = emojiBillboard(Strings.Emoji.brownBox, mapCell * 0.7)
                default: break
                }
                if let pickup {
                    pickup.position = center; pickup.zPosition = 2; mapLayer.addChild(pickup)
                    mapPickups[mapKey(c, r)] = pickup
                    switch ch {
                    case Strings.Tile.goldDiscChar, Strings.Tile.waterGunChar:
                        pickup.run(.repeatForever(.sequence([.scale(to: 1.25, duration: 0.35), .scale(to: 1.0, duration: 0.35)])))
                    case Strings.Tile.waterPelletChar:
                        pickup.run(.repeatForever(.sequence([.scale(to: 1.3, duration: 0.4), .scale(to: 1.0, duration: 0.4)])))
                    default: break
                    }
                }
            }
        }
        mapPete = SpriteFactory.petePerson(walkExaggeration: 1)
        mapPete.zPosition = 5
        mapLayer.addChild(mapPete)
        mapPete.startWalking()

        mapScale = (radarH - 8) / mapH
        mapLayer.setScale(mapScale)
        mapLayer.position = CGPoint(x: (size.width - mapW * mapScale) / 2, y: 4)
        mapLayer.zPosition = 201
        addChild(mapLayer)
    }

    private func setupBossController() {
        let rows = LevelStore.loadLevel(index: max(0, min(state.level - 1, Levels.levelNames.count - 1)))
        gridMap = GridMap(tileSize: 32, rows: rows)
        gridMap.xOffset = 0; gridMap.yOffset = 0
        pathfinder = Pathfinder(map: gridMap)
        // Pete's movement is the REAL WorkerController/TileMover (grid collision, tile-centring, tunnels) —
        // no hand-rolled px/py. It lives hidden; the iso view and the minimap both render from its position.
        let spawnGrid = CGPoint(x: Int(spawnPx), y: rowsCount - 1 - Int(spawnPy))
        workerController = WorkerController(spawnGrid: spawnGrid, gridMap: gridMap, sound: sound)
        workerController.delegate = self
        workerHost.addChild(workerController.node)
        workerController.applySpawnShield()
        bossController = BossController(scene: self, gridMap: gridMap, pathfinder: pathfinder, sound: sound, containerOriginX: 0)
        bossController.delegate = self
        // Spawn positions from the level data, in the bottom-up grid GridMap uses.
        var overrides: [(blueprintIndex: Int, position: CGPoint)] = []
        for (ri, row) in rows.reversed().enumerated() {
            for (ci, ch) in Array(row).enumerated() {
                switch ch {
                case Strings.Tile.boss1Char: overrides.append((0, CGPoint(x: ci, y: ri)))
                case Strings.Tile.boss2Char: overrides.append((1, CGPoint(x: ci, y: ri)))
                case Strings.Tile.boss3Char: overrides.append((2, CGPoint(x: ci, y: ri)))
                case Strings.Tile.boss4Char: overrides.append((3, CGPoint(x: ci, y: ri)))
                default: break
                }
            }
        }
        bossController.spawn(forLevel: 1, spawnOverrides: overrides)
        syncBossNodes()
        // The traveler (fish/treat) walks the maze and is caught for points, exactly as in 2D —
        // the spawner drives the tile walk; the 3D view projects it as a billboard (see projectSprites).
        travelerSpawner = TravelerSpawner(scene: self, gridMap: gridMap, sound: sound, containerOriginX: 0)
        travelerSpawner.scheduleVisits(of: levelTravelers[(state.level - 1) % levelTravelers.count]) { [weak self] in
            guard let self else { return false }
            return !self.gameOver && !self.isUserPaused && !self.dying
        }
    }

    // Re-parent controller boss nodes into the 3D sprite layer (driven as billboards,
    // no stray flat node / physics body) and mirror each on the radar. Re-run every
    // frame so splash/teleport respawns (fresh nodes) get adopted too.
    private func syncBossNodes() {
        let live = Set(bossController.entities.map { ObjectIdentifier($0.node) })
        for (id, mn) in bossMapNodes where !live.contains(id) {
            mn.removeFromParent(); bossMapNodes.removeValue(forKey: id)
            bossNativeH.removeValue(forKey: id); bossFeet.removeValue(forKey: id)
        }
        for (id, lbl) in bossNames where !live.contains(id) {
            lbl.removeFromParent(); bossNames.removeValue(forKey: id)
        }
        for e in bossController.entities {
            let id = ObjectIdentifier(e.node)
            if e.node.parent !== spriteLayer {
                e.tag.removeFromParent()                                              // drop the in-world tag (still inflates the frame even when hidden); 3D uses overlay nameplates
                let f = e.node.calculateAccumulatedFrame()                            // body-only frame now (tag gone)
                bossNativeH[id] = max(1, f.height)
                bossFeet[id] = f.minY - e.node.position.y                             // LOCAL bottom (frame is in parent coords incl. position; subtract it)
                e.node.removeFromParent(); e.node.physicsBody = nil; e.node.isHidden = true
                e.node.freezeLook()                                                   // 3D billboard: static eyes/tie (radar copy still tracks)
                spriteLayer.addChild(e.node)
            }
            if bossMapNodes[id] == nil {
                let mn = SpriteFactory.bossPersonForBlueprint(e.blueprintIndex)
                mn.zPosition = 4; mapLayer.addChild(mn); bossMapNodes[id] = mn
                if goldDisc.isActive { applyFleePalette(mn, flee: true, blueprint: e.blueprintIndex) }
            }
        }
    }

    // MARK: - Per-frame
    override func update(_ currentTime: TimeInterval) {
        if isUserPaused || gameOver { return }
        if dying { updateDeath(); return }
        step()
        if dying { return }   // step() just caught Pete: startDeath pinned the catcher — don't let render re-project it past Pete
        render()
    }

    private var camX = 0.0, camY = 0.0
    private func render() { renderIso() }

    private var isoNativeH: [ObjectIdentifier: CGFloat] = [:]
    private var isoFeet: [ObjectIdentifier: CGFloat] = [:]
    // Plant a sprite on tile (col,row) scaled to targetH; native height measured once. `lift` raises it
    // off the floor (0 = feet on floor for Pete/bosses; ~0.55 = mid-air for water-gun shots).
    private func placeIsoSprite(_ node: SKNode, _ col: CGFloat, _ row: CGFloat, _ targetH: CGFloat, _ lift: CGFloat = 0) {
        let id = ObjectIdentifier(node)
        let nh: CGFloat, bottom: CGFloat
        if let n = isoNativeH[id], let b = isoFeet[id] { nh = n; bottom = b }
        else {
            let prev = node.xScale
            node.setScale(1)
            let f = node.calculateAccumulatedFrame()
            nh = max(1, f.height); bottom = f.minY - node.position.y
            isoNativeH[id] = nh; isoFeet[id] = bottom
            node.setScale(prev)
        }
        let s = targetH * perspScale(Double(row)) / nh
        node.setScale(s)
        let pt = proj(Double(col), Double(row), lift)
        node.position = CGPoint(x: pt.x, y: pt.y - bottom * s)
    }

    private func renderIso() {
        throbClock += 1.0 / 60.0
        let anchorY = radarH + (size.height - radarH) * 0.50
        let foot = proj(Double(px), Double(py), 0)
        isoWorld.position = CGPoint(x: size.width / 2 - foot.x, y: anchorY - foot.y)   // scroll to follow Pete (ZOOM 2D style)

        let spriteH = isoTW * 0.95          // Pete/bosses ~ one tile tall in the overhead view
        placeIsoSprite(pete, CGFloat(px), CGFloat(py), spriteH)
        pete.position.y += 3                            // Pete up 3px
        pete.zPosition = CGFloat(py) * 4 + 0.6
        if !dying, let d = workerController.direction { pete.setFacing(d) }
        peteName.position = CGPoint(x: pete.position.x, y: pete.position.y + pete.calculateAccumulatedFrame().height + 2)
        peteName.zPosition = pete.zPosition + 0.1

        for e in bossController.entities {
            guard let g = bossGrid[ObjectIdentifier(e.node)] else { e.node.isHidden = true; continue }
            let bcol = g.0 + 0.5, brow = Double(rowsCount) - 0.5 - g.1
            e.node.isHidden = false
            placeIsoSprite(e.node, CGFloat(bcol), CGFloat(brow), spriteH)
            e.node.position.y += 3                      // bosses up 3px
            e.node.zPosition = CGFloat(brow) * 4 + 0.6
            if let d = e.mover?.dir { e.node.setFacing(d) }
            if !e.name.isEmpty {
                let label = bossNameplate(for: e.node, text: e.name); label.isHidden = false
                label.fontSize = max(10, 14 * perspScale(brow))
                label.position = CGPoint(x: e.node.position.x, y: e.node.position.y + e.node.calculateAccumulatedFrame().height + 2)
                label.zPosition = e.node.zPosition + 0.1
            }
        }

        // The real node's SKAction walk fights any position we set, so hide it and draw a SEPARATE mirror
        // at the SMOOTHED grid position (reliable + glides). travCol/travRow are updated in step().
        if travActive, let info = travelerSpawner?.activeTraveler {
            travelerSpawner?.node?.isHidden = true
            if isoTraveler == nil || isoTravelerEmoji != info.emoji {
                isoTraveler?.removeFromParent()
                let m = emojiBillboard(info.emoji, isoTW * 0.9); spriteLayer.addChild(m)
                isoTraveler = m; isoTravelerEmoji = info.emoji
            }
            if let m = isoTraveler {
                m.isHidden = false
                placeIsoSprite(m, CGFloat(travCol), CGFloat(travRow), isoTW * 0.9)
                m.xScale = abs(m.xScale) * travFlip            // face its travel direction (like the 2D traveler)
                m.zPosition = CGFloat(travRow) * 4 + 0.6
                // The traveler walks the maze edges, so the zoomed follow-camera usually scrolls it off
                // screen. Clamp the mirror to the viewport edge so you ALWAYS see it (an on-screen marker).
                let sx = m.position.x + isoWorld.position.x, sy = m.position.y + isoWorld.position.y
                let cx = min(max(sx, 26), size.width - 26), cy = min(max(sy, radarH + 26), size.height - 26)
                if cx != sx || cy != sy { m.position = CGPoint(x: cx - isoWorld.position.x, y: cy - isoWorld.position.y) }
            }
        } else {
            isoTraveler?.isHidden = true
        }

        let shotH = isoTW * 0.34            // water-gun pellets fly at mid-height (lift 0.55), not on the floor
        for s in shots where s.alive {
            if s.node.parent !== spriteLayer { s.node.removeFromParent(); spriteLayer.addChild(s.node) }
            s.node.isHidden = false
            placeIsoSprite(s.node, CGFloat(s.x), CGFloat(s.y), shotH, 0.55)
            s.node.zPosition = CGFloat(s.y) * 4 + 0.65
        }
    }

    private func render_unused_firstperson() {
        throbClock += 1.0 / 60.0
        let dirX = cos(angle), dirY = sin(angle)
        let planeX = -dirY * planeScale, planeY = dirX * planeScale
        // Camera trails behind Pete; pull in if it would sit inside a wall.
        var back = camBack
        while back > 0.05 && isWall(px - dirX * back, py - dirY * back) { back -= 0.1 }
        camX = px - dirX * back; camY = py - dirY * back
        castFloor()

        // Painter's voxel walls. Per column, march the WHOLE ray and record every wall as a FULL,
        // UNCLIPPED segment: an exposed FRONT face (open->wall) + the run's flat TOP cap. Adjacent
        // columns hitting the same face merge into one straight-edged quad (inverse depth is linear in
        // screen-x for a flat face, so the interpolation is exact — DOOM-quality, no seams/jaggies).
        // Because nothing is clipped, the edges never bend; occlusion comes purely from DRAW ORDER:
        // all quads are sorted far->near and the nearer ones paint over the farther, so the whole maze
        // reads deep AND clean.
        let cube = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]
        let w = size.width / CGFloat(columns)
        let half = wallHeightScale - eyeHeight    // negative: tops sit below the horizon (looking down)
        let floorClamp = radarH - viewH           // keep near-wall quads from running absurdly far off-screen
        struct VQuad { var p0, p1, p2, p3: CGPoint; var color: SKColor; var depth: Double }
        var quads: [VQuad] = []
        var openF: [Int: WallRun] = [:]           // FRONT faces (coalesced per face -> smooth straight quads)
        var tops = Set<Int>()                     // wall cells whose flat TOP is in view (projected per-cell)
        func emitFront(_ r: WallRun) {
            let xL = CGFloat(r.firstCol) * w, xR = CGFloat(r.lastCol + 1) * w + 0.6
            let cxA = (CGFloat(r.firstCol) + 0.5) * w, cxB = (CGFloat(r.lastCol) + 0.5) * w
            var yLoL = r.yLoA, yLoR = r.yLoB, yHiL = r.yHiA, yHiR = r.yHiB
            if r.lastCol > r.firstCol {
                let dx = cxB - cxA
                let sLo = (r.yLoB - r.yLoA) / dx, sHi = (r.yHiB - r.yHiA) / dx
                yLoL = r.yLoA + sLo * (xL - cxA); yLoR = r.yLoA + sLo * (xR - cxA)
                yHiL = r.yHiA + sHi * (xL - cxA); yHiR = r.yHiA + sHi * (xR - cxA)
            }
            let dAvg = r.depthSum / Double(r.n)
            let f = CGFloat(max(0.10, min(1.0, 1.0 - dAvg / maxVoxelDist)))
                    * (r.side == 1 ? 0.62 : 1.0) * (r.par == 1 ? 1.0 : 0.82)   // alternate cubicle blocks
            let color = cube.blended(withFraction: 1 - f, of: .black) ?? cube
            quads.append(VQuad(p0: CGPoint(x: xL, y: yLoL), p1: CGPoint(x: xL, y: yHiL),
                               p2: CGPoint(x: xR, y: yHiR), p3: CGPoint(x: xR, y: yLoR), color: color, depth: dAvg))
        }
        func addFront(_ key: Int, _ col: Int, _ yLo: CGFloat, _ yHi: CGFloat, _ d: Double, _ side: Int, _ par: Int) {
            if var r = openF[key], r.lastCol == col - 1 {
                r.lastCol = col; r.yLoB = yLo; r.yHiB = yHi; r.depthSum += d; r.n += 1; openF[key] = r
            } else {
                if let r = openF[key] { emitFront(r) }
                openF[key] = WallRun(firstCol: col, lastCol: col, yLoA: yLo, yHiA: yHi, yLoB: yLo, yHiB: yHi, depthSum: d, n: 1, side: side, par: par)
            }
        }
        for col in 0..<columns {
            let cameraX = 2.0 * (Double(col) + 0.5) / Double(columns) - 1.0
            let rdx = dirX + planeX * cameraX, rdy = dirY + planeY * cameraX
            var mapX = Int(camX.rounded(.down)), mapY = Int(camY.rounded(.down))
            let ddx = rdx == 0 ? 1e30 : abs(1 / rdx), ddy = rdy == 0 ? 1e30 : abs(1 / rdy)
            var stepX = 0, stepY = 0, sideX = 0.0, sideY = 0.0
            if rdx < 0 { stepX = -1; sideX = (camX - Double(mapX)) * ddx } else { stepX = 1; sideX = (Double(mapX) + 1 - camX) * ddx }
            if rdy < 0 { stepY = -1; sideY = (camY - Double(mapY)) * ddy } else { stepY = 1; sideY = (Double(mapY) + 1 - camY) * ddy }
            var firstHit = true
            var prevWall = false
            var guardN = 0
            while guardN < 160 {
                guardN += 1
                let dEntry: Double, side: Int
                if sideX < sideY { dEntry = sideX; sideX += ddx; mapX += stepX; side = 0 }
                else             { dEntry = sideY; sideY += ddy; mapY += stepY; side = 1 }
                if mapY < 0 || mapY >= rowsCount || mapX < 0 || mapX >= colsCount { break }
                if dEntry > maxVoxelDist { break }
                if map[mapY][mapX] != Strings.Tile.wallChar { prevWall = false; continue }   // floor: floor cast fills it
                let dN = max(0.05, dEntry)
                if firstHit { zbuf[col] = dN; firstHit = false }
                tops.insert(mapY * colsCount + mapX)                       // this cell's flat top is in view
                if !prevWall {                                            // exposed face -> coalesced front quad
                    let fid = side == 0 ? (stepX > 0 ? mapX : mapX + 1) * 2 : (stepY > 0 ? mapY : mapY + 1) * 2 + 1
                    let par = (mapX + mapY) & 1                            // break the run per cell so blocks alternate
                    let baseY = max(floorClamp, viewMidY - viewH * eyeHeight / CGFloat(dN))
                    let frontTopY = viewMidY + viewH * half / CGFloat(dN)
                    addFront(fid * 2 + par, col, baseY, frontTopY, dN, side, par)
                }
                prevWall = true
            }
            if firstHit { zbuf[col] = 1e9 }
            for fid in Array(openF.keys) where openF[fid]!.lastCol < col { emitFront(openF[fid]!); openF.removeValue(forKey: fid) }
        }
        for (_, r) in openF { emitFront(r) }
        // Wall TOPS: each cell's flat top is a real box face in 3D, so project its 4 corners with TRUE
        // 1-point perspective (corners projected independently, like the dots) — never distorts to a triangle.
        let invDet = 1.0 / (planeX * dirY - dirX * planeY)
        let capZ = wallHeightScale - eyeHeight
        let corners = [(0, 0), (1, 0), (1, 1), (0, 1)]
        for key in tops {
            let cx = Double(key % colsCount), cy = Double(key / colsCount)
            var pp = [CGPoint](); pp.reserveCapacity(4)
            var dsum = 0.0, ok = true
            for (ox, oy) in corners {
                let relX = (cx + Double(ox)) - camX, relY = (cy + Double(oy)) - camY
                let depth = invDet * (-planeY * relX + planeX * relY)
                if depth < 0.12 { ok = false; break }
                let transX = invDet * (dirY * relX - dirX * relY)
                pp.append(CGPoint(x: size.width / 2 * (1 + CGFloat(transX / depth)),
                                  y: viewMidY + viewH * CGFloat(capZ) / CGFloat(depth)))
                dsum += depth
            }
            if !ok { continue }
            let dAvg = dsum / 4
            if dAvg > maxVoxelDist { continue }
            let par = (Int(cx) + Int(cy)) & 1
            let f = CGFloat(max(0.10, min(1.0, 1.0 - dAvg / maxVoxelDist))) * (par == 1 ? 1.0 : 0.82)
            let base = cube.blended(withFraction: 1 - f, of: .black) ?? cube
            let color = base.blended(withFraction: 0.3, of: .white) ?? base
            quads.append(VQuad(p0: pp[0], p1: pp[1], p2: pp[2], p3: pp[3], color: color, depth: dAvg))
        }
        quads.sort { $0.depth > $1.depth }                                  // far -> near (painter's)
        var qi = 0
        for q in quads {
            let n: SKShapeNode
            if qi < wallQuads.count { n = wallQuads[qi] }
            else { n = SKShapeNode(); n.strokeColor = .clear; n.isAntialiased = false; addChild(n); wallQuads.append(n) }
            n.zPosition = CGFloat(qi) * 0.0002
            let p = CGMutablePath()
            p.move(to: q.p0); p.addLine(to: q.p1); p.addLine(to: q.p2); p.addLine(to: q.p3); p.closeSubpath()
            n.path = p; n.fillColor = q.color; n.isHidden = false
            qi += 1
        }
        for k in qi..<wallQuads.count { wallQuads[k].isHidden = true }
        projectSprites(dirX: dirX, dirY: dirY, planeX: planeX, planeY: planeY)
        updateMap()
    }

    private func projectSprites(dirX: Double, dirY: Double, planeX: Double, planeY: Double) {
        let invDet = 1.0 / (planeX * dirY - dirX * planeY)
        // `bottom` = the sprite's LOCAL frame.minY (feet offset from origin); centred sprites pass -nativeH/2.
        var all: [(node: SKNode, nativeH: CGFloat, worldH: CGFloat, x: Double, y: Double, maxH: CGFloat, name: String?, bottom: CGFloat)] = []
        for b in billboards where b.alive {
            all.append((b.node, b.nativeH, b.worldH, b.x, b.y, .greatestFiniteMagnitude, nil, -b.nativeH / 2))
        }
        for e in bossController.entities {
            guard let g = bossGrid[ObjectIdentifier(e.node)] else { continue }
            let id = ObjectIdentifier(e.node)
            let bx = g.0 + 0.5, by = Double(rowsCount) - 0.5 - g.1   // gridMap bottom-up -> raster top-down (smooth)
            let nh = bossNativeH[id] ?? 36
            all.append((e.node, nh, 0.3, bx, by, .greatestFiniteMagnitude, e.name, bossFeet[id] ?? -nh / 2))   // no size cap (cap made him sink); worldH 0.3 keeps him ~Pete-size at the catch
        }
        for s in shots where s.alive {
            all.append((s.node, s.nativeH, 0.32, s.x, s.y, .greatestFiniteMagnitude, nil, -s.nativeH / 2))
        }
        // The traveler walks in 2D scene coords; pull its node into the sprite layer and project it as a
        // billboard at its current grid tile (gridMap bottom-up -> raster top-down, same flip as bosses).
        if let tnode = travelerSpawner?.node, travelerSpawner?.activeTraveler != nil {
            if tnode.parent !== spriteLayer { tnode.removeFromParent(); spriteLayer.addChild(tnode) }
            let g = travelerSpawner.grid
            let nh = max(1, tnode.calculateAccumulatedFrame().height)
            all.append((tnode, nh, 0.42, Double(g.x) + 0.5, Double(rowsCount) - 0.5 - Double(g.y), .greatestFiniteMagnitude, nil, -nh / 2))
        }
        // Pass 1: project, far-cull and wall-occlude every sprite; keep the survivors with their depth.
        var vis: [(node: SKNode, nativeH: CGFloat, worldH: CGFloat, maxH: CGFloat, name: String?, bottom: CGFloat, tX: Double, tY: Double)] = []
        for item in all {
            let node = item.node
            item.name.map { bossNameplate(for: node, text: $0) }?.isHidden = true
            let relX = item.x - camX, relY = item.y - camY
            let tX = invDet * (dirY * relX - dirX * relY)
            let tY = invDet * (-planeY * relX + planeX * relY)   // depth
            guard tY > 0.15 else { node.isHidden = true; continue }
            let col = Int((size.width / 2) * CGFloat(1 + tX / tY) / (size.width / CGFloat(columns)))
            // Occlude against the NEAREST wall across the sprite's whole screen footprint, so a dot whose
            // body overlaps a wall a few columns from its centre is still hidden behind it.
            if col >= 0, col < columns {
                let footHalf = max(1, min(5, Int((viewH / CGFloat(tY) * item.worldH) / (size.width / CGFloat(columns)) * 0.5)))
                var wallZ = zbuf[col]
                for c in max(0, col - footHalf)...min(columns - 1, col + footHalf) { wallZ = min(wallZ, zbuf[c]) }
                if tY > wallZ + 0.3 { node.isHidden = true; continue }
            }
            if tY > 18 { node.isHidden = true; continue }       // far cull
            let screenX = (size.width / 2) * CGFloat(1 + tX / tY)
            guard screenX > -60, screenX < size.width + 60 else { node.isHidden = true; continue }
            vis.append((node, item.nativeH, item.worldH, item.maxH, item.name, item.bottom, tX, tY))
        }
        // Pass 2: draw strictly far -> near (assign rising zPositions) so a nearer sprite always paints
        // over a farther one — a dot and a machine at similar depth no longer tie and flip.
        vis.sort { $0.tY > $1.tY }
        let zStep = vis.count > 1 ? 80.0 / Double(vis.count - 1) : 0
        for (i, v) in vis.enumerated() {
            let node = v.node, tY = v.tY
            // TRUE 1-point perspective, identical to the dots: size = viewH/depth, feet planted on the
            // floor row at THIS depth. maxH only clamps the size at point-blank range; it never moves the floor.
            let targetH = min(viewH / CGFloat(tY) * v.worldH, v.maxH)
            var s = targetH / v.nativeH
            if v.name != nil, let boss = node as? PixelPerson, bossController.isImmobilized(boss: boss) {
                s *= 1 + 0.18 * abs(sin(throbClock * .pi * 3))   // post-spawn throb, feet planted (position uses s)
            }
            node.isHidden = false
            node.setScale(s)
            let screenX = (size.width / 2) * CGFloat(1 + v.tX / tY)
            let floorY = viewMidY - (viewH / CGFloat(tY)) * eyeHeight
            node.position = CGPoint(x: screenX, y: floorY - v.bottom * s)
            node.zPosition = 2 + CGFloat(Double(i) * zStep)     // 2..82, far->near; always below Pete (90)
            if let name = v.name {
                let label = bossNameplate(for: node, text: name)
                label.isHidden = false
                label.fontSize = max(13, min(24, targetH * 0.16))
                label.position = CGPoint(x: screenX, y: floorY + targetH + label.fontSize * 0.7)
            }
        }
    }

    private func bossNameplate(for node: SKNode, text: String) -> SKLabelNode {
        let id = ObjectIdentifier(node)
        if let l = bossNames[id] { return l }
        let l = makeNameplate(text)
        bossNames[id] = l
        nameLayer.addChild(l)
        return l
    }

    private func updateMap() {
        mapPete.position = mapLocal(px, py)
        if let d = workerController.direction { mapPete.setFacing(d) }
        for e in bossController.entities {
            guard let mn = bossMapNodes[ObjectIdentifier(e.node)], let g = bossGrid[ObjectIdentifier(e.node)] else { continue }
            mn.position = mapLocal(g.0 + 0.5, Double(rowsCount) - 0.5 - g.1)
            if let d = e.mover?.dir { mn.setFacing(d) }
        }
        for s in shots where s.alive { s.mapNode.position = mapLocal(s.x, s.y) }
        if travActive, let info = travelerSpawner?.activeTraveler {   // minimap traveler, same SMOOTHED position as iso
            if mapTraveler == nil || mapTravelerEmoji != info.emoji {
                mapTraveler?.removeFromParent()
                let t = emojiBillboard(info.emoji, mapCell * 0.7); t.zPosition = 5
                mapLayer.addChild(t); mapTraveler = t; mapTravelerEmoji = info.emoji
            }
            mapTraveler?.isHidden = false
            mapTraveler?.position = mapLocal(travCol, travRow)
        } else {
            mapTraveler?.isHidden = true
        }
    }

    private func facing(_ d: (x: Int, y: Int)) -> MoveDirection {
        d.x > 0 ? .right : d.x < 0 ? .left : d.y > 0 ? .down : .up
    }

    // MARK: - Lane movement (Pac-Man style: auto-forward, turn at junctions)
    private func step() {
        workerController.advance(1.0 / 60.0)        // REAL TileMover physics: grid collision, tile-centring, tunnels (no stuck)
        let wp = workerController.worldPosition      // derive raster grid coords that the iso view + minimap render from
        px = Double(wp.x) / 32.0
        py = Double(rowsCount) - Double(wp.y) / 32.0
        if let info = travelerSpawner?.activeTraveler, let tn = travelerSpawner?.node {   // SMOOTH: the node's SKAction.move interpolates continuously (same as 2D)
            let nc = Double(tn.position.x) / 32.0
            let dx = nc - travCol
            if travActive, abs(dx) > 0.001, abs(dx) < 2 {   // flip to face travel direction, same convention as TravelerSpawner
                travFlip = info.facesRight ? (dx < 0 ? -1 : 1) : (dx < 0 ? 1 : -1)
            }
            travCol = nc
            travRow = Double(rowsCount) - Double(tn.position.y) / 32.0
            travActive = true
        } else { travActive = false }
        bossController.advance(1.0 / 60.0)          // fixed dt = 100% game's per-frame step
        syncBossNodes()
        // Capture each boss's SMOOTH world position from the mover itself, not node.position:
        // projectSprites overwrites node.position with screen coords for the billboard, and on
        // square-mode dwell frames the mover doesn't rewrite it, so sampling node.position then
        // yields a stale screen coord -> a bogus map-edge cell (Bill blinked to a tunnel).
        bossGrid.removeAll(keepingCapacity: true)
        for e in bossController.entities {
            let p = e.mover?.worldPosition ?? e.node.position
            bossGrid[ObjectIdentifier(e.node)] = (Double(p.x) / 32.0 - 0.5, Double(p.y) / 32.0 - 0.5)
        }
        peteShielded = bossController.isAnyBossSpawning   // shielded exactly while bosses flash in (spawnGrace)
        workerController.setShielded(peteShielded)
        checkBossCatch()
        if let caught = travelerSpawner?.tryCatch(at: workerGrid) {   // walked onto the traveler's tile
            state.bumpScore(by: caught.traveler.points)
            sound.playFishOrTreat()
            popPoints(caught.traveler.points)
            refreshHUD()
            hud.showMessage(Strings.Message.travelerCaught(emoji: caught.traveler.emoji, points: caught.traveler.points), duration: 2)
        }
        if frightenSecondsLeft > 0 {                      // loop-driven (no Task.sleep on wasm)
            frightenSecondsLeft -= 1.0 / 60.0
            if frightenSecondsLeft <= 0 { endGoldDiscMode() }
        }
        if workerController.direction != nil { pete.startWalking() } else { pete.stopWalking() }
        moveShots()                          // water-gun pellets: advance, splash bosses, cull (loop-driven, no Task.sleep)
        updateMap()                          // keep the 2D minimap in sync with the real worker + bosses
    }

    // MARK: - WorkerControllerDelegate (real engine drives Pete; pickups fire here, not a per-frame scan)
    var isGameOver: Bool { gameOver }
    func workerDidEnterTile(_ grid: CGPoint) {
        let c = Int(grid.x), r = rowsCount - 1 - Int(grid.y)   // gridMap (bottom-up) -> raster (top-down)
        guard r >= 0, r < rowsCount, c >= 0, c < map[r].count else { return }
        let key = mapKey(c, r), ch = map[r][c]
        if isDotTile(ch) {                                     // plain dots: raised blocks
            guard !isoDotCollected.contains(key) else { return }
            isoDotCollected.insert(key); isoDotsLeft -= 1
            rebuildDotRow(r); mapPickups[key]?.isHidden = true
            sound.playDotBlip(); state.collectedDots += 1; state.bumpScore(by: 1)
            refreshHUD(); return
        }
        switch ch {                                            // power-ups, machines, brown box (TPS turn-in)
        case Strings.Tile.goldDiscChar:
            guard !collected.contains(key) else { return }
            collected.insert(key); sound.playGoldDisc(); state.collectedGoldDiscs += 1
            state.bumpScore(by: 5); popPoints(5); hidePickup(c, r); startGoldDiscMode(); refreshHUD()
        case Strings.Tile.waterGunChar:
            guard !collected.contains(key) else { return }
            collected.insert(key); waterGun.activate(); waterGunPickedUp = true
            sound.playWaterGunPickup(); state.bumpScore(by: 75); popPoints(75); hidePickup(c, r); refreshHUD()
        case Strings.Tile.waterPelletChar:
            guard !collected.contains(key) else { return }
            collected.insert(key); state.bumpScore(by: 50); sound.playWaterGunPickup(); popPoints(50)
            if waterGunPickedUp { waterGun.reloadPellets(8) }
            hidePickup(c, r); refreshHUD()
        case Strings.Tile.printerChar:    collectMachine(Strings.Machine.printer, key, c, r)
        case Strings.Tile.faxChar:        collectMachine(Strings.Machine.fax, key, c, r)
        case Strings.Tile.coverSheetChar: collectMachine(Strings.Machine.coverSheet, key, c, r)
        case Strings.Tile.bookBinderChar: collectMachine(Strings.Machine.bookBinder, key, c, r)
        case Strings.Tile.brownBoxChar:   collectTPSReport()
        default: break
        }
    }

    private func collectIsoDot() {
        let c = Int(px.rounded(.down)), r = Int(py.rounded(.down))
        guard r >= 0, r < rowsCount, c >= 0, c < map[r].count else { return }
        let key = mapKey(c, r)
        guard isDotTile(map[r][c]), !isoDotCollected.contains(key) else { return }
        guard abs(px - (Double(c) + 0.5)) < 0.45, abs(py - (Double(r) + 0.5)) < 0.45 else { return }
        isoDotCollected.insert(key); isoDotsLeft -= 1; rebuildDotRow(r)
        switch map[r][c] {
        case Strings.Tile.goldDiscChar: sound.playGoldDisc(); state.collectedGoldDiscs += 1; state.bumpScore(by: 5); popPoints(5); startGoldDiscMode()
        default:                        sound.playDotBlip(); state.collectedDots += 1; state.bumpScore(by: 1)
        }
        refreshHUD()
    }

    private func moveShots() {
        let speed = 0.22
        for i in shots.indices where shots[i].alive {
            shots[i].x += Double(shots[i].dir.x) * speed
            shots[i].y += Double(shots[i].dir.y) * speed
            if isWall(shots[i].x, shots[i].y) { shots[i].alive = false; continue }
            let sgx = Int(shots[i].x.rounded(.down)), sgy = rowsCount - 1 - Int(shots[i].y.rounded(.down))
            for e in bossController.entities {
                let bg = e.mover?.grid ?? e.ai.grid
                if Int(bg.x) == sgx, Int(bg.y) == sgy {
                    bossController.splash(boss: e.node)   // real splash + loop-driven 5s respawn
                    shots[i].alive = false
                    sound.playWaterGunSplash(); state.bumpScore(by: 50); popPoints(50); refreshHUD()
                    break
                }
            }
        }
        for s in shots where !s.alive { s.node.removeFromParent(); s.mapNode.removeFromParent() }
        shots.removeAll { !$0.alive }
    }

    private func fire() {
        guard let faceDir = workerController.direction else { return }   // real driver's heading (raster cardinal)
        guard waterGun.consumePellet() else { return }
        sound.playWaterGunShoot()
        refreshHUD()
        let dir = (x: faceDir == .left ? -1 : faceDir == .right ? 1 : 0,
                   y: faceDir == .up ? -1 : faceDir == .down ? 1 : 0)
        let pellet = SpriteFactory.waterPelletVisual(radius: 12)   // detailed blue pellet from the level art
        pellet.isHidden = true; spriteLayer.addChild(pellet)
        let mapNode = SpriteFactory.waterPelletVisual(radius: mapCell * 0.22)
        mapNode.position = mapLocal(px, py); mapNode.zPosition = 3; mapLayer.addChild(mapNode)
        shots.append(Shot(x: px, y: py, dir: dir, node: pellet,
                          nativeH: max(1, pellet.calculateAccumulatedFrame().height), mapNode: mapNode, alive: true))
    }

    // Tile-based pickup of the stationary items (water-gun power-up + TPS machines),
    // mirroring the 100% game's collect rules through the shared RoundState/WaterGunState.
    private func collectStationary() {
        let pcol = Int(px.rounded(.down)), prow = Int(py.rounded(.down))
        guard prow >= 0, prow < rowsCount, pcol >= 0, pcol < map[prow].count else { return }
        let ch = map[prow][pcol]
        // Brown box = the TPS drop-off (repeatable, never "collected"). Fire once per entry.
        if ch == Strings.Tile.brownBoxChar {
            if !onBrownBox { onBrownBox = true; collectTPSReport() }
            return
        }
        onBrownBox = false
        let key = mapKey(pcol, prow)
        guard !collected.contains(key) else { return }
        switch ch {
        case Strings.Tile.waterGunChar:
            collected.insert(key); waterGun.activate(); waterGunPickedUp = true; sound.playWaterGunPickup()
            hidePickup(pcol, prow); refreshHUD()
        case Strings.Tile.printerChar:    collectMachine(Strings.Machine.printer, key, pcol, prow)
        case Strings.Tile.faxChar:        collectMachine(Strings.Machine.fax, key, pcol, prow)
        case Strings.Tile.coverSheetChar: collectMachine(Strings.Machine.coverSheet, key, pcol, prow)
        case Strings.Tile.bookBinderChar: collectMachine(Strings.Machine.bookBinder, key, pcol, prow)
        default: break
        }
    }
    private func collectMachine(_ name: String, _ key: Int, _ col: Int, _ row: Int) {
        guard Strings.Machine.required.contains(name), !state.reportItems.contains(name) else { return }
        collected.insert(key)
        state.reportItems.insert(name)
        let itemIndex = state.reportItems.count - 1   // points ramp 10/25/50/100, like GameScene.handleMachine
        if itemIndex < reportItemPoints.count {
            let pts = reportItemPoints[itemIndex]
            state.bumpScore(by: pts); state.currentReportScore += pts; popPoints(pts)
        }
        sound.playMachine(named: name)
        grayPickup(col, row); refreshHUD()   // dim it like the 100% 2D maze, don't remove it
    }
    // +point popup, same as the 100% game's ScorePopup, in BOTH views: on Pete in
    // the 3D corridor, and on Pete in the mini-map (a matching rise+fade label).
    private func popPoints(_ n: Int) {
        ScorePopup.show(n, at: CGPoint(x: size.width / 2, y: peteBaseY + viewH * 0.30), in: self, fontSize: 54)   // big in the 3D view, above Pete
        let mini = SKLabelNode(fontNamed: Strings.Font.menloBold)
        mini.text = Strings.Score.popup(n)
        mini.fontSize = 40; mini.fontColor = .systemYellow
        mini.position = mapPete.position; mini.zPosition = 6
        mapLayer.addChild(mini)
        mini.run(.sequence([.group([.moveBy(x: 0, y: 42, duration: 0.7), .fadeOut(withDuration: 0.7)]), .removeFromParent()]))
    }

    // Turn in a completed TPS report at the brown box (mirrors GameScene.collectTPSReport).
    private func collectTPSReport() {
        guard state.reportItems.count == Strings.Machine.required.count else {
            let missing = Strings.Machine.required.filter { !state.reportItems.contains($0) }
            hud.showMessage(Strings.Message.tpsMissingItems(missing), duration: 5)
            sound.playTpsMissingItems(missing)
            return
        }
        state.tpsReportsDelivered += 1
        state.reportItems.removeAll()
        let tpsPoints = state.level * 100 + 100
        state.bumpScore(by: tpsPoints); state.currentReportScore = 0
        popPoints(tpsPoints)
        sound.playTpsDeliver()
        let gainedLife = state.lives < HUD.maxLives
        if gainedLife { state.lives += 1 }
        resetCollectedMachines()   // un-gray so a fresh report can be gathered (GameScene.resetGrayedMachines)
        refreshHUD()
        hud.showMessage(Strings.Message.tpsTurnedIn(points: tpsPoints, gainedLife: gainedLife), duration: 3)
    }
    private func resetCollectedMachines() {
        for r in 0..<rowsCount {
            for (c, ch) in map[r].enumerated() {
                switch ch {
                case Strings.Tile.printerChar, Strings.Tile.faxChar, Strings.Tile.coverSheetChar, Strings.Tile.bookBinderChar:
                    let key = mapKey(c, r); collected.remove(key)
                    isoPickups[key]?.alpha = 1
                    mapPickups[key]?.alpha = 1
                default: break
                }
            }
        }
    }
    private func hidePickup(_ col: Int, _ row: Int) {
        let key = mapKey(col, row)
        isoPickups[key]?.isHidden = true
        mapPickups[key]?.isHidden = true
    }
    private func grayPickup(_ col: Int, _ row: Int) {
        let key = mapKey(col, row)
        isoPickups[key]?.alpha = 0.55
        mapPickups[key]?.alpha = 0.55
    }

    private func exit() {
        sound.stopAllAudio()
        // A practice session (launched from the editor) returns to the editor at the
        // level under test, matching GameScene.returnToTitleScene().
        if state.practiceMode {
            let editor = LevelEditorScene(size: size)
            editor.scaleMode = .aspectFit
            editor.currentLevelIndex = max(0, state.level - 1)
            view?.presentScene(editor, transition: .fade(withDuration: 0.5))
            return
        }
        view?.presentScene(TitleScene(size: size), transition: .fade(withDuration: 0.5))
    }

    // Same game-over screen as the 2D levels, with name entry when the score qualifies.
    private func showGameOver() {
        sound.stopAllAudio()
        let screen = GameOverScreen(
            size: size, font: Strings.Font.menloBold,
            score: state.score, highScore: state.highScore,
            defaultName: LocalHighScores.savedUsername ?? "", allowEntry: !state.practiceMode,
            onPlay: { [weak self] in self?.restartDoom() },
            onEsc:  { [weak self] in self?.exit() })
        screen.zPosition = 2000
        addChild(screen)
        gameOverScreen = screen
    }
    private func restartDoom() {
        gameOverScreen?.removeFromParent(); gameOverScreen = nil
        let bonus = IsoScene(size: size)
        bonus.scaleMode = scaleMode
        bonus.practiceMode = practiceMode
        bonus.startingLevel = startingLevel
        view?.presentScene(bonus, transition: .fade(withDuration: 0.5))
    }

    // MARK: - Input (steer at junctions, relative to facing)
    override func keyDown(with event: NSEvent) {
        let code = Int(event.keyCode)
        if let s = gameOverScreen {                   // type the name (when qualified); PLAY/ESC otherwise
            #if os(macOS)
            s.handleKey(usernameKeyCode(for: event), shift: event.modifierFlags.contains(.shift))
            #else
            s.handleKey(code, shift: false)
            #endif
            return
        }
        switch code {
        case KeyCode.esc:                       exit()
        case KeyCode.keyP:                      togglePause()
        case KeyCode.space:                     if !event.isARepeat { fire() }
        case KeyCode.arrowUp,    KeyCode.keyW:  workerController.queueDirection(.up)
        case KeyCode.arrowRight, KeyCode.keyD:  workerController.queueDirection(.right)
        case KeyCode.arrowDown,  KeyCode.keyS:  workerController.queueDirection(.down)
        case KeyCode.arrowLeft,  KeyCode.keyA:  workerController.queueDirection(.left)
        default:                                break
        }
    }
    override func keyUp(with event: NSEvent) { pressed.remove(Int(event.keyCode)) }

    // MARK: - On-screen joystick + fire button (drive the same tank input)
    private func buildControls() {
        if UserDefaults.standard.bool(forKey: Strings.DefaultsKey.waterGunHide) { return }
        controlsShown = true
        let fireOnLeft = UserDefaults.standard.bool(forKey: Strings.DefaultsKey.waterGunLeft)
        fireButtonCenter = CGPoint(x: fireOnLeft ? fireButtonRadius : size.width - fireButtonRadius, y: fireButtonRadius + 15)
        let ring = SKShapeNode(circleOfRadius: fireButtonRadius)
        ring.position = fireButtonCenter
        ring.fillColor = SKColor(white: 1, alpha: 0.14); ring.strokeColor = SKColor(white: 1, alpha: 0.5)
        ring.lineWidth = 2; ring.zPosition = 300   // above the radar panel (200/201) so the controls are never cropped
        addChild(ring)

        joystickCenter = CGPoint(x: fireOnLeft ? size.width - joystickRadius : joystickRadius, y: joystickRadius + 15)
        let base = SKShapeNode(circleOfRadius: joystickRadius)
        base.position = joystickCenter
        base.fillColor = SKColor(white: 1, alpha: 0.06); base.strokeColor = SKColor(white: 1, alpha: 0.5)
        base.lineWidth = 2; base.zPosition = 300
        addChild(base)
        // Four ring-sector wedges split by an X = the D-pad buttons. A diagonal press
        // lights two and steers forward + a turn together. Arrow glyph in each wedge.
        let dirs: [(String, CGFloat, String)] = [("up", .pi / 2, "\u{25B2}"), ("left", .pi, "\u{25C0}"),
                                                 ("down", -.pi / 2, "\u{25BC}"), ("right", 0, "\u{25B6}")]
        for (name, ang, glyph) in dirs {
            let w = SKShapeNode(path: dpadWedgePath(centerAngle: ang))
            w.position = joystickCenter
            w.fillColor = SKColor(white: 1, alpha: 0.12); w.strokeColor = .clear
            w.lineWidth = 0; w.zPosition = 301
            addChild(w); dpadWedges[name] = w
            let arrow = SKLabelNode(text: glyph)
            arrow.fontSize = 24; arrow.fontColor = SKColor(white: 1, alpha: 0.7)
            arrow.verticalAlignmentMode = .center; arrow.horizontalAlignmentMode = .center
            let r = (joystickDeadzone + joystickRadius) / 2
            arrow.position = CGPoint(x: joystickCenter.x + cos(ang) * r, y: joystickCenter.y + sin(ang) * r)
            arrow.zPosition = 302
            addChild(arrow)
        }
        // X boundary lines (the four diagonals) only — no centre ring.
        let xPath = CGMutablePath()
        for k in 0..<4 {
            let t = CGFloat.pi / 4 + CGFloat(k) * CGFloat.pi / 2
            xPath.move(to: CGPoint(x: cos(t) * joystickDeadzone, y: sin(t) * joystickDeadzone))
            xPath.addLine(to: CGPoint(x: cos(t) * joystickRadius, y: sin(t) * joystickRadius))
        }
        let xlines = SKShapeNode(path: xPath)
        xlines.position = joystickCenter
        xlines.strokeColor = SKColor(white: 1, alpha: 0.5); xlines.lineWidth = 2
        xlines.zPosition = 301
        addChild(xlines)
    }

    // Ring-sector wedge (deadzone radius -> outer radius), a full 90° so the four
    // wedges MEET at the diagonals (no dead gaps); the X reads as the stroked boundary
    // between neighbours, and the diagonal corner sits on the edge of both wedges so a
    // corner press fires both. Polygon (move/addLine only) so it renders on WASM too.
    private func dpadWedgePath(centerAngle: CGFloat) -> CGPath {
        let inner = joystickDeadzone, outer = joystickRadius
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

    private func radius(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y; return (dx * dx + dy * dy).squareRoot()
    }

    // Desktop mouse = a single finger (the on-screen D-pad is really for phones).
    // Once any true touch arrives, ignore this synthetic pointer so we don't
    // double-drive the D-pad on a phone (the host emits BOTH for finger 0).
    override func mouseDown(with event: NSEvent) {
        if let s = gameOverScreen { s.handleTap(at: s.convert(event.location(in: self), from: self)); return }
        if usingTouch { return }
        pointerBegan(finger: 0, at: event.location(in: self))
    }
    override func mouseDragged(with event: NSEvent) {
        if usingTouch { return }
        if dpadFinger[0] != nil { dpadSet(finger: 0, phase: 1, at: event.location(in: self)) }
    }
    override func mouseUp(with event: NSEvent) {
        if usingTouch { return }
        if dpadFinger[0] != nil { dpadSet(finger: 0, phase: 2, at: event.location(in: self)) }
    }

    // MARK: - Multi-touch D-pad (phone). Each finger lights at most one wedge, so
    // forward + a turn happen only when two fingers are physically down at once.
    func touchBegan(finger: Int, at p: CGPoint) {
        if gameOverScreen != nil { return }   // game-over menu rides the synthetic mouse pointer (no double-fire)
        usingTouch = true
        pointerBegan(finger: finger, at: p)
    }
    func touchMoved(finger: Int, at p: CGPoint) {
        if dpadFinger[finger] != nil { dpadSet(finger: finger, phase: 1, at: p) }
    }
    func touchEnded(finger: Int, at p: CGPoint) {
        if dpadFinger[finger] != nil { dpadSet(finger: finger, phase: 2, at: p) }
    }

    private func pointerBegan(finger: Int, at p: CGPoint) {
        guard !isUserPaused, !dying else { return }
        if !controlsShown { fire(); return }   // water gun hidden: a tap anywhere fires
        if radius(p, joystickCenter) <= joystickRadius { dpadSet(finger: finger, phase: 0, at: p); return }
        if radius(p, fireButtonCenter) <= fireButtonRadius { fire() }
    }

    // Which single wedge a point is in ("" = centre hole / outside the ring).
    private func dpadWedgeAt(_ p: CGPoint) -> String {
        let dx = p.x - joystickCenter.x, dy = p.y - joystickCenter.y
        let mag = (dx * dx + dy * dy).squareRoot()
        if mag < joystickDeadzone || mag > joystickRadius { return "" }
        if abs(dy) >= abs(dx) { return dy > 0 ? "up" : "down" }   // scene y-up: up = forward
        return dx > 0 ? "right" : "left"
    }

    private func dpadSet(finger: Int, phase: Int, at p: CGPoint) {
        let prev = dpadFinger[finger] ?? ""
        let w = phase == 2 ? "" : dpadWedgeAt(p)
        if w.isEmpty { dpadFinger[finger] = nil } else { dpadFinger[finger] = w }
        // Queue an absolute grid heading the moment a finger ENTERS a wedge (Pete auto-moves, Pac-Man style).
        if !w.isEmpty, w != prev {
            switch w {
            case "up":    workerController.queueDirection(.up)
            case "right": workerController.queueDirection(.right)
            case "down":  workerController.queueDirection(.down)
            case "left":  workerController.queueDirection(.left)
            default:      break
            }
        }
        applyDpad()
    }

    private func applyDpad() {
        var up = false, down = false, left = false, right = false
        for (_, w) in dpadFinger {
            switch w {
            case "up": up = true; case "down": down = true
            case "left": left = true; case "right": right = true
            default: break
            }
        }
        highlightDPad(up: up, down: down, left: left, right: right)
    }
    private func highlightDPad(up: Bool, down: Bool, left: Bool, right: Bool) {
        let on: [String: Bool] = ["up": up, "down": down, "left": left, "right": right]
        for (k, v) in on { dpadWedges[k]?.fillColor = SKColor(white: 1, alpha: v ? 0.34 : 0.12) }
    }

    required init?(coder: NSCoder) { fatalError(Strings.System.initCoderUnsupported) }
    override init(size: CGSize) { super.init(size: size) }
}
