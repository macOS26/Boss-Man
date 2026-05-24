import AppKit
import SpriteKit
import Darwin

// MARK: - Tile ↔ Character Mapping
struct EditorTile: Equatable {
    let character: Character
    let displayName: String

    static let empty    = EditorTile(character: Strings.Tile.floorChar,      displayName: Strings.Editor.Tile.floor)
    static let dot      = EditorTile(character: Strings.Tile.dotChar,        displayName: Strings.Editor.Tile.dot)
    static let wall     = EditorTile(character: Strings.Tile.wallChar,       displayName: Strings.Editor.Tile.wall)
    static let hideout  = EditorTile(character: Strings.Tile.hideoutChar,    displayName: Strings.Editor.Tile.hideout)
    static let printer  = EditorTile(character: Strings.Tile.printerChar,    displayName: Strings.Machine.printer)
    static let fax      = EditorTile(character: Strings.Tile.faxChar,        displayName: Strings.Machine.fax)
    static let copy     = EditorTile(character: Strings.Tile.coverSheetChar, displayName: Strings.Machine.coverSheet)
    static let collator = EditorTile(character: Strings.Tile.bookBinderChar, displayName: Strings.Machine.bookBinder)
    static let brownBox = EditorTile(character: Strings.Tile.brownBoxChar,   displayName: Strings.Machine.brownBox)
    static let goldDisc = EditorTile(character: Strings.Tile.goldDiscChar,   displayName: Strings.Editor.Tile.goldDisc)
    static let worker   = EditorTile(character: Strings.Tile.workerChar,     displayName: Strings.Worker.pete)
    static let boss1    = EditorTile(character: Strings.Tile.boss1Char,      displayName: Strings.Boss.boss)
    static let boss2    = EditorTile(character: Strings.Tile.boss2Char,      displayName: Strings.Boss.lumbergh)
    static let boss3    = EditorTile(character: Strings.Tile.boss3Char,      displayName: Strings.Boss.waddams)
    static let boss4    = EditorTile(character: Strings.Tile.boss4Char,      displayName: Strings.Boss.bolton)

    static let all: [EditorTile] = [
        .empty, .dot, .wall, .hideout,
        .printer, .fax, .copy, .collator, .brownBox,
        .goldDisc, .worker, .boss1, .boss2, .boss3, .boss4
    ]
}

// MARK: - Level Store
final class LevelStore {
    static let shared = LevelStore()

    static var fileURL: URL {
        let fm = FileManager.default
        let dir = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))?
            .appendingPathComponent(Strings.App.bundleName, isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/\(Strings.App.bundleName)",
                                        isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Strings.Resource.levelsJSON, isDirectory: false)
    }

    private func loadCustomLevels() -> [String: [String]] {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    private func saveCustomLevels(_ levels: [String: [String]]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(levels) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
        Self.dequarantine(Self.fileURL)
    }

    static func dequarantine(_ url: URL) {
        _ = url.path.withCString { removexattr($0, Strings.Resource.quarantineAttribute, 0) }
    }

    func loadLevel(name: String) -> [String]? {
        if let custom = loadCustomLevels()[name] { return custom }
        guard let idx = Levels.levelNames.firstIndex(of: name) else { return nil }
        return officeMaps[idx]
    }

    func loadLevel(index: Int) -> [String] {
        guard index >= 0 && index < Levels.levelNames.count else {
            return officeMaps[0]
        }
        return loadLevel(name: Levels.levelNames[index]) ?? officeMaps[index]
    }

    func saveLevel(name: String, rows: [String]) {
        var custom = loadCustomLevels()
        custom[name] = rows
        saveCustomLevels(custom)
    }

    func resetLevel(name: String) {
        var custom = loadCustomLevels()
        custom.removeValue(forKey: name)
        saveCustomLevels(custom)
    }

    func revealInFinder() {
        let url = Self.fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data(Strings.Resource.emptyJSON.utf8).write(to: url)
        }
        Self.dequarantine(url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Level Editor Scene
class LevelEditorScene: SKScene {
    
    var tileSize: CGFloat = 30
    var gridRows = 0
    var gridCols = 0
    var mapRows: [String] = []
    var selectedTile: EditorTile = .wall
    var currentLevelIndex = UserDefaults.standard.integer(forKey: "LevelEditor_LastLevelIndex") {
        didSet { UserDefaults.standard.set(currentLevelIndex, forKey: "LevelEditor_LastLevelIndex") }
    }
    
    let panelWidth: CGFloat = 148
    let margin: CGFloat = 12
    
    var gridContainer = SKNode()
    var tileNodes: [[SKNode]] = []
    var paletteNodes: [SKShapeNode] = []

    private static let paletteNamePrefix = Strings.NodeName.palettePrefix
    private static func paletteName(for char: Character) -> String {
        "\(paletteNamePrefix)\(char)"
    }

    private static let cubicleColors: [NSColor] = [
        .systemBlue,   .systemTeal, .systemIndigo, .systemGreen,  .systemPink, .systemBrown,
        .systemPurple, .systemRed,  .systemOrange, .systemYellow, .systemCyan, .systemGray
    ]
    var uiContainer = SKNode()
    var levelLabel: SKLabelNode!
    var levelSubLabel: SKLabelNode!
    var statusLabel: SKLabelNode!
    var highlightOverlay: SKShapeNode?

    private var undoStack: [[String]] = []
    private var redoStack: [[String]] = []
    private var clipboard: [String]? = nil
    private var buttonBaseColors: [String: NSColor] = [:]
    private var buttonNodes: [String: SKShapeNode] = [:]
    /// PREV/NEXT trigger loadCurrentLevel() → buildUI() which tears the
    /// just-flashed button out of the scene. We stash the name here so
    /// buildUI() can re-flash the freshly-rebuilt button.
    private var pendingFlashName: String?
    private let maxUndoDepth = 50
    var saveButton: SKShapeNode!
    var saveButtonLabel: SKLabelNode?
    private let autosaveInterval: TimeInterval = 60
    
    var gridOffsetX: CGFloat = 12
    var gridOffsetY: CGFloat = 12
    
    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        backgroundColor = NSColor(white: 0.08, alpha: 1.0)
        addChild(gridContainer)
        addChild(uiContainer)
        buildUI()
        loadCurrentLevel()
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        removeAction(forKey: "autosave")
        let tick = SKAction.sequence([
            .wait(forDuration: autosaveInterval),
            .run { [weak self] in self?.performAutosave() }
        ])
        run(.repeatForever(tick), withKey: "autosave")
    }

    private func performAutosave() {
        // Use the SAME save path as the SAVE button (no duplicate logic);
        // just override the post-save status / button-label visuals so
        // the user can distinguish autosave from a manual ⌘S.
        saveCurrentLevel()
        let originalLabel = Strings.Editor.save
        saveButtonLabel?.text = "AUTOSAVE 1 min"
        statusLabel?.text = "AUTOSAVE 1 min"
        run(.sequence([
            .wait(forDuration: 3),
            .run { [weak self] in
                guard let self else { return }
                self.saveButtonLabel?.text = originalLabel
                self.statusLabel?.text = Strings.Editor.tilePrefix(self.selectedTile.displayName)
            }
        ]), withKey: "autosaveRevert")
    }
    
    // MARK: - UI
    func buildUI() {
        uiContainer.removeAllChildren()
        
        let panelWidth: CGFloat = 148
        let panelX = frame.width - panelWidth - 4
        
        let panel = SKShapeNode(rect: CGRect(x: panelX, y: 0, width: panelWidth + 4, height: frame.height))
        panel.fillColor = NSColor(white: 0.15, alpha: 0.97)
        panel.strokeColor = NSColor(white: 0.35, alpha: 1.0)
        panel.lineWidth = 2
        panel.zPosition = 100
        uiContainer.addChild(panel)
        
        let cx = panelX + panelWidth / 2 + 2
        
        let title = SKLabelNode(text: Strings.Editor.title)
        title.fontName = Strings.Font.menloBold
        title.fontSize = 13
        title.fontColor = NSColor.white
        title.position = CGPoint(x: cx, y: frame.height - 24)
        title.zPosition = 101
        uiContainer.addChild(title)
        
        levelLabel = SKLabelNode(text: Strings.empty)
        levelLabel.fontName = Strings.Font.menloBold
        levelLabel.fontSize = 11
        levelLabel.fontColor = NSColor.cyan
        levelLabel.position = CGPoint(x: cx, y: frame.height - 46)
        levelLabel.zPosition = 101
        levelLabel.numberOfLines = 2
        levelLabel.horizontalAlignmentMode = .center
        uiContainer.addChild(levelLabel)
        levelSubLabel = SKLabelNode(text: Strings.empty)
        levelSubLabel.fontName = Strings.Font.menloBold
        levelSubLabel.fontSize = 11
        levelSubLabel.fontColor = NSColor.cyan
        levelSubLabel.position = CGPoint(x: cx, y: frame.height - 60)
        levelSubLabel.zPosition = 101
        levelSubLabel.horizontalAlignmentMode = .center
        uiContainer.addChild(levelSubLabel)
        
        statusLabel = SKLabelNode(text: Strings.Editor.tileWallInitial)
        statusLabel.fontName = Strings.Font.menlo
        statusLabel.fontSize = 10
        statusLabel.fontColor = NSColor.yellow
        statusLabel.position = CGPoint(x: cx, y: frame.height - 78)
        statusLabel.zPosition = 101
        uiContainer.addChild(statusLabel)
        
        paletteNodes = []
        let palStartY = frame.height - 89
        let palSpacing: CGFloat = 21
        
        for (i, tile) in EditorTile.all.enumerated() {
            let y = palStartY - 24 - CGFloat(i) * palSpacing
            let swatchRect = CGRect(x: panelX + 8, y: y, width: panelWidth - 12, height: palSpacing)
            let palName = LevelEditorScene.paletteName(for: tile.character)
            let bg = SKShapeNode(rect: swatchRect)
            bg.fillColor = floorColor(forParity: 0)
            bg.strokeColor = NSColor(white: 0.4, alpha: 1.0)
            bg.lineWidth = 1
            bg.zPosition = 101
            bg.name = palName
            uiContainer.addChild(bg)
            paletteNodes.append(bg)

            let preview = renderTile(char: tile.character, size: palSpacing - 6, isPaletteSwatch: true)
            preview.position = CGPoint(x: panelX + 8 + (palSpacing - 6) / 2 + 3,
                                       y: y + (palSpacing) / 2)
            preview.zPosition = 102
            preview.name = palName
            uiContainer.addChild(preview)

            let lbl = SKLabelNode(text: tile.displayName)
            lbl.fontName = Strings.Font.menloBold
            lbl.fontSize = 10
            lbl.fontColor = .white
            lbl.horizontalAlignmentMode = .left
            lbl.verticalAlignmentMode = .center
            lbl.position = CGPoint(x: panelX + 8 + palSpacing + 4,
                                   y: y + (palSpacing) / 2)
            lbl.zPosition = 102
            lbl.name = palName
            uiContainer.addChild(lbl)
        }
        
        let btnData: [(String, NSColor, String)] = [
            (Strings.Editor.prev,     NSColor(white: 0.42, alpha: 1.0),              Strings.EditorButton.prev),
            (Strings.Editor.next,     NSColor(white: 0.34, alpha: 1.0),              Strings.EditorButton.next),
            (Strings.Editor.undo,     NSColor(white: 0.26, alpha: 1.0),              Strings.EditorButton.undo),
            (Strings.Editor.redo,     NSColor(white: 0.18, alpha: 1.0),              Strings.EditorButton.redo),
            (Strings.Editor.clear,      NSColor(calibratedRed: 0.6, green: 0.15, blue: 0.15, alpha: 1.0), Strings.EditorButton.clear),
            (Strings.Editor.save,  NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.15, alpha: 1.0), Strings.EditorButton.save),
            (Strings.Editor.copy,  NSColor(calibratedRed: 0.20, green: 0.40, blue: 0.30, alpha: 1.0), Strings.EditorButton.copy),
            (Strings.Editor.paste, NSColor(calibratedRed: 0.25, green: 0.35, blue: 0.30, alpha: 1.0), Strings.EditorButton.paste),
            (Strings.Editor.revealFile, NSColor(calibratedRed: 0.25, green: 0.35, blue: 0.45, alpha: 1.0), Strings.EditorButton.reveal),
            (Strings.Editor.play,       NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.55, alpha: 1.0), Strings.EditorButton.play),
            (Strings.Editor.back, NSColor(calibratedRed: 0.45, green: 0.4, blue: 0.15, alpha: 1.0),  Strings.EditorButton.back),
        ]
        let btnHeight: CGFloat = 17
        let btnSpacing: CGFloat = 19
        let btnStartY = palStartY - 24 - CGFloat(EditorTile.all.count) * palSpacing - 13
        buttonBaseColors.removeAll()
        buttonNodes.removeAll()

        for (i, (title, color, name)) in btnData.enumerated() {
            let by = btnStartY - CGFloat(i) * btnSpacing
            let btn = SKShapeNode(rect: CGRect(x: panelX + 8, y: by, width: panelWidth - 12, height: btnHeight))
            btn.fillColor = color
            btn.strokeColor = .clear
            btn.lineWidth = 0
            btn.zPosition = 101
            btn.name = name
            uiContainer.addChild(btn)
            buttonBaseColors[name] = color
            buttonNodes[name] = btn

            let lbl = SKLabelNode(text: title)
            lbl.fontName = Strings.Font.menloBold
            lbl.fontSize = 9
            lbl.fontColor = NSColor.white
            lbl.verticalAlignmentMode = .center
            lbl.horizontalAlignmentMode = .left
            lbl.position = CGPoint(x: panelX + 15, y: by + btnHeight / 2)
            lbl.zPosition = 102
            lbl.name = name
            uiContainer.addChild(lbl)

            if name == Strings.EditorButton.save {
                saveButton = btn
                saveButtonLabel = lbl
            }
        }
        
        updatePaletteHighlight()
        updateLevelLabel()
        if let pending = pendingFlashName {
            pendingFlashName = nil
            flashButton(named: pending)
        }
    }
    
    // MARK: - Grid
    func rebuildGrid() {
        gridContainer.removeAllChildren()
        tileNodes = []
        
        let availWidth = frame.width - panelWidth - margin * 2 - 8
        let availHeight = frame.height - margin * 2
        
        let fitW = gridCols > 0 ? availWidth / CGFloat(gridCols) : 32
        let fitH = gridRows > 0 ? availHeight / CGFloat(gridRows) : 32
        tileSize = min(fitW, fitH)
        tileSize = max(tileSize, 4)
        
        let totalW = CGFloat(gridCols) * tileSize
        let totalH = CGFloat(gridRows) * tileSize
        let offsetX = (availWidth - totalW) / 2 + margin
        let offsetY = (availHeight - totalH) / 2 + margin
        gridOffsetX = offsetX
        gridOffsetY = offsetY
        
        for row in 0..<gridRows {
            var rowNodes: [SKNode] = []
            for col in 0..<gridCols {
                let x = offsetX + CGFloat(col) * tileSize
                let y = offsetY + CGFloat(gridRows - 1 - row) * tileSize
                let container = SKNode()
                container.position = CGPoint(x: x + tileSize / 2, y: y + tileSize / 2)
                container.zPosition = 10
                container.name = Strings.Editor.tileNodeName(row: row, col: col)
                gridContainer.addChild(container)
                renderTileInto(container, row: row, col: col, size: tileSize)
                rowNodes.append(container)
            }
            tileNodes.append(rowNodes)
        }
    }
    
    func charAt(row: Int, col: Int) -> Character {
        guard row < mapRows.count else { return Strings.Tile.floorChar }
        let chars = Array(mapRows[row])
        guard col < chars.count else { return Strings.Tile.floorChar }
        return chars[col]
    }
    
    func setChar(row: Int, col: Int, ch: Character) {
        guard row < mapRows.count else { return }
        var chars = Array(mapRows[row])
        guard col < chars.count else { return }
        chars[col] = ch
        mapRows[row] = String(chars)
    }
    
    func updateTileVisual(row: Int, col: Int) {
        guard row < tileNodes.count, col < tileNodes[row].count else { return }
        let container = tileNodes[row][col]
        container.removeAllChildren()
        renderTileInto(container, row: row, col: col, size: tileSize)
    }

    // MARK: - Real game-style rendering (matches MazeBuilder visuals)
    private var currentCubicleColor: NSColor {
        Self.cubicleColors[currentLevelIndex % Self.cubicleColors.count]
    }

    private func floorColor(forParity parity: Int) -> NSColor {
        parity.isMultiple(of: 2)
            ? NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.13, alpha: 1)
            : NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.11, alpha: 1)
    }

    private func renderTileInto(_ container: SKNode, row: Int, col: Int, size: CGFloat) {
        let ch = charAt(row: row, col: col)
        let parity = row + col
        addFloor(to: container, size: size, parity: parity)
        addContent(to: container, char: ch, size: size)
    }

    private func renderTile(char: Character, size: CGFloat, isPaletteSwatch: Bool = false) -> SKNode {
        let container = SKNode()
        if !isPaletteSwatch {
            addFloor(to: container, size: size, parity: 0)
        }
        addContent(to: container, char: char, size: size)
        return container
    }

    private func addFloor(to container: SKNode, size: CGFloat, parity: Int) {
        let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
        let floor = SKShapeNode(rect: rect)
        floor.fillColor = floorColor(forParity: parity)
        floor.strokeColor = NSColor(calibratedWhite: 0.16, alpha: 1)
        floor.lineWidth = 0.5
        container.addChild(floor)
    }

    private func addContent(to container: SKNode, char: Character, size: CGFloat) {
        switch char {
        case Strings.Tile.wallChar:
            addWall(to: container, size: size)
        case Strings.Tile.dotChar:
            addDot(to: container, size: size)
        case Strings.Tile.hideoutChar:
            addDot(to: container, size: size)
            addLetter(to: container, text: Strings.Tile.hideout, color: .systemPurple, size: size * 0.85)
        case Strings.Tile.printerChar, Strings.Tile.faxChar,
             Strings.Tile.coverSheetChar, Strings.Tile.bookBinderChar,
             Strings.Tile.brownBoxChar:
            addEmoji(to: container, text: MazeBuilder.emoji(forSymbol: String(char)), size: size)
        case Strings.Tile.goldDiscChar:
            addGoldDisc(to: container, size: size)
        case Strings.Tile.workerChar:
            addPete(to: container, size: size)
        case Strings.Tile.boss1Char:
            addBoss(to: container, name: Strings.Boss.boss,
                    body: .systemRed,    tie: .black,        size: size)
        case Strings.Tile.boss2Char:
            addBoss(to: container, name: Strings.Boss.lumbergh,
                    body: NSColor.systemPink.withAlphaComponent(0.75),
                    tie: NSColor.systemPurple.blended(withFraction: 0.40, of: .black) ?? .systemPurple, size: size)
        case Strings.Tile.boss3Char:
            addBoss(to: container, name: Strings.Boss.waddams,
                    body: .systemTeal,
                    tie: NSColor.systemBlue.blended(withFraction: 0.20, of: .black) ?? .systemBlue, size: size)
        case Strings.Tile.boss4Char:
            addBoss(to: container, name: Strings.Boss.bolton,
                    body: .systemOrange,
                    tie: NSColor.systemRed.blended(withFraction: 0.10, of: .black) ?? .systemRed, size: size)
        default:
            break
        }
    }

    private func addWall(to container: SKNode, size: CGFloat) {
        let color = currentCubicleColor
        let inset = size * 0.04
        let fillRect = CGRect(x: -size / 2 + inset, y: -size / 2 + inset,
                              width: size - inset * 2, height: size - inset * 2)
        let body = SKShapeNode(rect: fillRect)
        body.fillColor = color.withAlphaComponent(0.55)
        body.strokeColor = color
        body.lineWidth = 1.5
        container.addChild(body)

        let trimHeight = max(2, size * 0.12)
        let trimRect = CGRect(x: -size / 2 + size * 0.16,
                              y: size * 0.20,
                              width: size - size * 0.32,
                              height: trimHeight)
        let trim = SKShapeNode(rect: trimRect)
        trim.fillColor = NSColor.systemGray
        trim.strokeColor = .clear
        container.addChild(trim)
    }

    private func addDot(to container: SKNode, size: CGFloat) {
        let dotSize = max(2, size * 0.20)
        let dot = SKShapeNode(rect: CGRect(x: -dotSize / 2, y: -dotSize / 2,
                                           width: dotSize, height: dotSize))
        dot.fillColor = NSColor.systemYellow
        dot.strokeColor = .clear
        container.addChild(dot)
    }

    private func addLetter(to container: SKNode, text: String, color: NSColor, size: CGFloat) {
        let label = SKLabelNode(text: text)
        label.fontName = Strings.Font.menloBold
        label.fontSize = size
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        container.addChild(label)
    }

    private func addEmoji(to container: SKNode, text: String, size: CGFloat) {
        let label = SKLabelNode(text: text)
        label.fontName = Strings.Font.menlo
        label.fontSize = size * 0.72
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        container.addChild(label)
    }

    private func addGoldDisc(to container: SKNode, size: CGFloat) {
        let radius = size * 0.28
        let glow = SKShapeNode(circleOfRadius: radius * 1.35)
        glow.fillColor = NSColor.systemYellow.withAlphaComponent(0.30)
        glow.strokeColor = .clear
        container.addChild(glow)
        let core = SKShapeNode(circleOfRadius: radius)
        core.fillColor = .systemYellow
        core.strokeColor = NSColor(calibratedRed: 0.7, green: 0.5, blue: 0.0, alpha: 1)
        core.lineWidth = 1
        container.addChild(core)
    }

    private func addPete(to container: SKNode, size: CGFloat) {
        let person = PixelPerson(
            bodyColor: .systemBlue,
            tieColor: .systemOrange,
            hairColor: NSColor(calibratedRed: 0.25, green: 0.15, blue: 0.08, alpha: 1),
            shoeOutlineColor: .white,
            pantsColor: NSColor(calibratedRed: 0.70, green: 0.45, blue: 0.18, alpha: 1)
        )
        person.setScale(size / 38)
        container.addChild(person)
    }

    private func addBoss(to container: SKNode,
                         name: String,
                         body: NSColor,
                         tie: NSColor,
                         size: CGFloat) {
        let person = PixelPerson(
            bodyColor: body,
            tieColor: tie,
            hairColor: NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.35, alpha: 1),
            shoeOutlineColor: .white,
            pantsColor: .darkGray,
            wearsSunglasses: false,
            headYOffset: -1
        )
        person.setScale(size / 38)
        container.addChild(person)
    }
    
    // MARK: - Level Loading
    func loadCurrentLevel() {
        let names = Levels.levelNames
        guard currentLevelIndex < names.count else {
            currentLevelIndex = 0
            return loadCurrentLevel()
        }
        let name = names[currentLevelIndex]
        undoStack.removeAll()
        redoStack.removeAll()

        if let rows = LevelStore.shared.loadLevel(name: name) {
            mapRows = rows
            gridRows = rows.count
            gridCols = rows.first?.count ?? 0
        } else {
            gridRows = 17
            gridCols = 37
            mapRows = Array(repeating: String(repeating: Strings.Tile.floor, count: gridCols), count: gridRows)
        }
        
        rebuildGrid()
        updateLevelLabel()
        // Rebuild the side palette so the Wall swatch reflects this
        // floor's cubicle color (and any other per-level visuals).
        buildUI()
    }
    
    func updateLevelLabel() {
        let names = Levels.levelNames
        guard currentLevelIndex < names.count else { return }
        levelLabel?.text = names[currentLevelIndex].replacingOccurrences(of: Strings.Editor.nameDashSeparator, with: Strings.HUD.emojiTrailSeparator)
        levelSubLabel?.text = Strings.Editor.levelCounter(currentLevelIndex + 1, of: names.count)
    }
    
    func updatePaletteHighlight() {
        for (i, node) in paletteNodes.enumerated() {
            node.lineWidth = 1
            node.strokeColor = NSColor(white: 0.4, alpha: 1.0)
            if i < EditorTile.all.count && EditorTile.all[i] == selectedTile {
                highlightOverlay?.removeFromParent()
                let overlay = SKShapeNode(rect: node.frame.insetBy(dx: 2, dy: 2))
                overlay.fillColor = NSColor.yellow.withAlphaComponent(0.10)
                overlay.strokeColor = NSColor.yellow
                overlay.lineWidth = 1
                overlay.zPosition = 110
                uiContainer.addChild(overlay)
                highlightOverlay = overlay
            }
        }
        statusLabel?.text = Strings.Editor.tilePrefix(selectedTile.displayName)
    }
    
    // MARK: - Input
    // MARK: - Undo / redo
    private func pushUndoSnapshot() {
        undoStack.append(mapRows)
        if undoStack.count > maxUndoDepth { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast() else {
            statusLabel?.text = Strings.Editor.nothingUndo
            return
        }
        redoStack.append(mapRows)
        mapRows = prev
        rebuildGrid()
        statusLabel?.text = Strings.Editor.undoToast
    }

    func redo() {
        guard let next = redoStack.popLast() else {
            statusLabel?.text = Strings.Editor.nothingRedo
            return
        }
        undoStack.append(mapRows)
        mapRows = next
        rebuildGrid()
        statusLabel?.text = Strings.Editor.redoToast
    }

    private func flashButton(named name: String) {
        // Mirror the SAVE button pattern: swap fillColor to a brightened
        // variant of the base, then restore it after 0.5s.
        guard let btn = buttonNodes[name], let base = buttonBaseColors[name] else { return }
        let bright = base.blended(withFraction: 0.45, of: .white) ?? base
        btn.fillColor = bright
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak btn] in
            guard let self, let btn else { return }
            btn.fillColor = self.buttonBaseColors[name] ?? base
        }
    }

    private func copyLevel() {
        clipboard = mapRows
        statusLabel?.text = Strings.Editor.copyToast
    }

    private func pasteLevel() {
        guard let rows = clipboard, !rows.isEmpty else {
            statusLabel?.text = Strings.Editor.nothingPaste
            return
        }
        pushUndoSnapshot()
        mapRows = rows
        rebuildGrid()
        statusLabel?.text = Strings.Editor.pasteToast
    }

    private func confirmClearLevel() {
        let alert = NSAlert()
        alert.messageText = Strings.Editor.clearConfirmTitle
        alert.informativeText = Strings.Editor.clearConfirmBody
        alert.alertStyle = .warning
        alert.addButton(withTitle: Strings.Editor.clearConfirmDestructive)
        alert.addButton(withTitle: Strings.Editor.clearConfirmCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        pushUndoSnapshot()
        mapRows = mapRows.map { _ in String(repeating: Strings.Tile.floor, count: gridCols) }
        rebuildGrid()
    }

    override func mouseDown(with event: NSEvent) {
        pushUndoSnapshot()
        handleInput(event.location(in: self), begin: true)
    }
    
    override func mouseDragged(with event: NSEvent) {
        handleInput(event.location(in: self), begin: false)
    }
    
    override func mouseUp(with event: NSEvent) { }
    
    override func rightMouseDown(with event: NSEvent) {
        paintRightClick(at: event.location(in: self))
    }

    override func rightMouseDragged(with event: NSEvent) {
        paintRightClick(at: event.location(in: self))
    }

    /// Right-click toggles wall↔dot when the target is one of those;
    /// any other tile becomes a dot.
    private func paintRightClick(at loc: CGPoint) {
        let col = Int((loc.x - gridOffsetX) / tileSize)
        let row = gridRows - 1 - Int((loc.y - gridOffsetY) / tileSize)
        guard row >= 0, row < gridRows, col >= 0, col < gridCols else { return }
        let current = charAt(row: row, col: col)
        let tile: EditorTile
        switch current {
        case Strings.Tile.dotChar:  tile = .wall
        case Strings.Tile.wallChar: tile = .dot
        default:                    tile = .dot
        }
        paint(at: loc, tile: tile)
    }
    
    func handleInput(_ loc: CGPoint, begin: Bool) {
        if begin {
            // Check all nodes at the click point (including children) so clicking
            // anywhere in a palette row — sprite, text, or background — works.
            let hitNodes = nodes(at: loc)
            let paletteName = hitNodes.compactMap { node -> String? in
                if let name = node.name, name.hasPrefix(LevelEditorScene.paletteNamePrefix) { return name }
                if let name = node.parent?.name, name.hasPrefix(LevelEditorScene.paletteNamePrefix) { return name }
                if let name = node.parent?.parent?.name, name.hasPrefix(LevelEditorScene.paletteNamePrefix) { return name }
                return nil
            }.first
            
            if let palName = paletteName {
                let ch = palName.suffix(1).first!
                if let tile = EditorTile.all.first(where: { $0.character == ch }) {
                    selectedTile = tile
                    updatePaletteHighlight()
                }
                return
            }
            
            let name = hitNodes.first?.name ?? Strings.empty
            if name.hasPrefix("btn_") { flashButton(named: name) }
            switch name {
            case Strings.EditorButton.prev:
                let count = Levels.levelNames.count
                currentLevelIndex = (currentLevelIndex - 1 + count) % count
                pendingFlashName = Strings.EditorButton.prev
                loadCurrentLevel()
                return
            case Strings.EditorButton.next:
                currentLevelIndex = (currentLevelIndex + 1) % Levels.levelNames.count
                pendingFlashName = Strings.EditorButton.next
                loadCurrentLevel()
                return
            case Strings.EditorButton.undo:
                undo()
                return
            case Strings.EditorButton.redo:
                redo()
                return
            case Strings.EditorButton.clear:
                confirmClearLevel()
                return
            case Strings.EditorButton.save:
                saveCurrentLevel()
                return
            case Strings.EditorButton.copy:
                copyLevel()
                return
            case Strings.EditorButton.paste:
                pasteLevel()
                return
            case Strings.EditorButton.reveal:
                LevelStore.shared.revealInFinder()
                return
            case Strings.EditorButton.play:
                playCurrentLevel()
                return
            case Strings.EditorButton.back:
                let title = TitleScene(size: size)
                title.scaleMode = .aspectFit
                view?.presentScene(title, transition: .fade(withDuration: 0.3))
                return
            default: break
            }
        }
        
        paint(at: loc, tile: selectedTile)
    }
    
    func paint(at loc: CGPoint, tile: EditorTile) {
        let col = Int((loc.x - gridOffsetX) / tileSize)
        let row = gridRows - 1 - Int((loc.y - gridOffsetY) / tileSize)
        
        guard row >= 0, row < gridRows, col >= 0, col < gridCols else { return }
        
        if charAt(row: row, col: col) != tile.character {
            setChar(row: row, col: col, ch: tile.character)
            updateTileVisual(row: row, col: col)
        }
    }
    
    // MARK: - Play
    func playCurrentLevel() {
        saveCurrentLevel()
        let game = GameScene(size: size)
        game.scaleMode = .aspectFit
        game.practiceMode = true
        game.startingLevel = currentLevelIndex + 1
        view?.presentScene(game, transition: .fade(withDuration: 0.5))
    }

    // MARK: - Save
    func saveCurrentLevel() {
        let names = Levels.levelNames
        guard currentLevelIndex < names.count else { return }
        LevelStore.shared.saveLevel(name: names[currentLevelIndex], rows: mapRows)
        
        saveButton?.fillColor = NSColor.green
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.saveButton?.fillColor = NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.15, alpha: 1.0)
        }
        statusLabel?.text = Strings.Editor.savedToast
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.statusLabel?.text = Strings.Editor.tilePrefix(self.selectedTile.displayName)
        }
    }
    
    // MARK: - Keyboard
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            let title = TitleScene(size: size)
            title.scaleMode = .aspectFit
            view?.presentScene(title, transition: .fade(withDuration: 0.3))
        case 123:
            let count = Levels.levelNames.count
            currentLevelIndex = (currentLevelIndex - 1 + count) % count
            pendingFlashName = Strings.EditorButton.prev
            loadCurrentLevel()
            return
        case 124:
            currentLevelIndex = (currentLevelIndex + 1) % Levels.levelNames.count
            pendingFlashName = Strings.EditorButton.next
            loadCurrentLevel()
            return
        case 51 where event.modifierFlags.contains(.command):
            // ⌘⌫ — destructive, so route through the same confirm dialog as the CLEAR button.
            confirmClearLevel()
            return
        default: break
        }
        
        if let chars = event.characters {
            switch chars {
            case Strings.Key.digit1: selectedTile = .wall
            case Strings.Key.digit2: selectedTile = .dot
            case Strings.Key.digit3: selectedTile = .hideout
            case Strings.Key.digit4: selectedTile = .printer
            case Strings.Key.digit5: selectedTile = .fax
            case Strings.Key.digit6: selectedTile = .copy
            case Strings.Key.digit7: selectedTile = .collator
            case Strings.Key.digit8: selectedTile = .brownBox
            case Strings.Key.digit0: selectedTile = .empty
            case Strings.KeyEquivalent.save where event.modifierFlags.contains(.command):
                saveCurrentLevel()
            case Strings.KeyEquivalent.play where event.modifierFlags.contains(.command):
                // ⌘P launches a playtest on whatever level we're viewing.
                playCurrentLevel()
            case Strings.KeyEquivalent.reveal where event.modifierFlags.contains(.command):
                LevelStore.shared.revealInFinder()
            case Strings.KeyEquivalent.copy where event.modifierFlags.contains(.command):
                copyLevel()
            case Strings.KeyEquivalent.paste where event.modifierFlags.contains(.command):
                pasteLevel()
            case Strings.KeyEquivalent.undo where event.modifierFlags.contains([.command, .shift]):
                redo()
            case Strings.KeyEquivalent.undo where event.modifierFlags.contains(.command):
                undo()
            case Strings.KeyEquivalent.undoShift where event.modifierFlags.contains(.command):
                redo()
            default: break
            }
        }
        updatePaletteHighlight()
    }
}
