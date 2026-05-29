import SpriteKit

// Level editor, wasm port. A faithful port of the macOS SpriteKit
// LevelEditorScene (boss-man-spritekit-swift), the master source of truth.
// 37x17 grid, a right-hand panel with a 17-tile palette + 11 action buttons,
// left-drag painting, undo/redo/copy/paste/clear, per-level PREV/NEXT with a
// persisted index, autosave, and a PLAY button that launches GameScene in
// practice mode on the edited level.
//
// macOS-only facilities are remapped to the wasm substrate:
//   - NSColor            -> SKColor (system colours that the kit lacks are
//                          replaced by SpriteFactory visuals or literals)
//   - UserDefaults       -> Persistence (localStorage)
//   - LevelStore JSON    -> LevelStore over Persistence (one key per level,
//                          rows joined by "\n"); browser storage, no file
//   - DispatchQueue      -> keyed SKActions (the kit's clock is the action runner)
//   - NSAlert confirm    -> immediate clear, undoable via the pushed snapshot
//   - NSWorkspace reveal -> a "Saved to browser storage" toast
//   - right-mouse / drag -> mouseMoved drag-paint; right-click toggle is a kit gap
//   - Cmd-modified keys  -> bare letters (the runtime drops modifier flags)

// MARK: - Tile <-> Character mapping
struct EditorTile: Equatable {
    let character: Character
    let displayName: String

    static let empty       = EditorTile(character: Strings.Tile.floorChar,       displayName: Strings.Editor.Tile.floor)
    static let dot         = EditorTile(character: Strings.Tile.dotChar,          displayName: Strings.Editor.Tile.dot)
    static let wall        = EditorTile(character: Strings.Tile.wallChar,         displayName: Strings.Editor.Tile.wall)
    static let hideout     = EditorTile(character: Strings.Tile.hideoutChar,      displayName: Strings.Editor.Tile.hideout)
    static let printer     = EditorTile(character: Strings.Tile.printerChar,      displayName: Strings.Machine.printer)
    static let fax         = EditorTile(character: Strings.Tile.faxChar,          displayName: Strings.Machine.fax)
    static let copy        = EditorTile(character: Strings.Tile.coverSheetChar,   displayName: Strings.Machine.coverSheet)
    static let collator    = EditorTile(character: Strings.Tile.bookBinderChar,   displayName: Strings.Machine.bookBinder)
    static let brownBox    = EditorTile(character: Strings.Tile.brownBoxChar,     displayName: Strings.Machine.brownBox)
    static let goldDisc    = EditorTile(character: Strings.Tile.goldDiscChar,     displayName: Strings.Editor.Tile.goldDisc)
    static let worker      = EditorTile(character: Strings.Tile.workerChar,       displayName: "Hero Pete")
    static let boss1       = EditorTile(character: Strings.Tile.boss1Char,        displayName: "Boss Bill")
    static let boss2       = EditorTile(character: Strings.Tile.boss2Char,        displayName: "Boss Dom")
    static let boss3       = EditorTile(character: Strings.Tile.boss3Char,        displayName: "Boss Bob")
    static let boss4       = EditorTile(character: Strings.Tile.boss4Char,        displayName: "Boss Stan")
    static let waterGun    = EditorTile(character: Strings.Tile.waterGunChar,     displayName: Strings.Editor.Tile.waterGun)
    static let waterPellet = EditorTile(character: Strings.Tile.waterPelletChar,  displayName: Strings.Editor.Tile.waterPellet)

    static let all: [EditorTile] = [
        .empty, .dot, .wall, .hideout,
        .printer, .fax, .copy, .collator, .brownBox,
        .goldDisc, .worker, .boss1, .boss2, .boss3, .boss4, .waterGun, .waterPellet
    ]
}

// MARK: - Level store (localStorage)
// The macOS editor persisted a levels.json dict in Application Support. The
// web port has no filesystem write, so each edited level is stored under its
// own localStorage key as the rows joined by newlines. Built-in levels seed
// from the read-only Levels.officeMaps asset. GameScene reads through this too
// so PLAY (and subsequent levels) load the edited maps.
enum LevelStore {
    static let mapCols = 37
    static let mapRows = 17

    static func key(_ index: Int) -> String { Strings.DefaultsKey.editorLevelPrefix + String(index) }

    static func normalize(_ rows: [String]) -> [String] {
        var out = rows.map { row -> String in
            if row.count == mapCols { return row }
            if row.count <  mapCols { return row + String(repeating: Strings.Tile.floor, count: mapCols - row.count) }
            return String(row.prefix(mapCols))
        }
        while out.count < mapRows { out.append(String(repeating: Strings.Tile.floor, count: mapCols)) }
        if out.count > mapRows { out = Array(out.prefix(mapRows)) }
        return out
    }

    static func hasOverride(index: Int) -> Bool {
        !(Persistence.string(forKey: key(index)) ?? "").isEmpty
    }

    static func loadLevel(index: Int) -> [String] {
        if let stored = Persistence.string(forKey: key(index)), !stored.isEmpty {
            return normalize(stored.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        }
        let maps = Levels.officeMaps
        let safe = (index >= 0 && index < maps.count) ? maps[index] : (maps.first ?? [])
        return normalize(safe)
    }

    static func saveLevel(index: Int, rows: [String]) {
        Persistence.setString(rows.joined(separator: "\n"), forKey: key(index))
    }

    static func resetLevel(index: Int) {
        Persistence.setString("", forKey: key(index))
    }
}

// MARK: - Level editor scene
final class LevelEditorScene: SKScene {

    var tileSize: CGFloat = 32
    var gridRows = 0
    var gridCols = 0
    var mapRows: [String] = []
    var selectedTile: EditorTile = .wall
    var currentLevelIndex = Persistence.int(forKey: Strings.DefaultsKey.editorLastLevelIndex) {
        didSet { Persistence.set(currentLevelIndex, forKey: Strings.DefaultsKey.editorLastLevelIndex) }
    }

    let panelWidth: CGFloat = 148
    let margin: CGFloat = 12

    var gridContainer = SKNode()
    var uiContainer = SKNode()
    var tileNodes: [[SKNode]] = []
    var paletteNodes: [SKShapeNode] = []
    var paletteRects: [CGRect] = []
    var buttonRects: [(rect: CGRect, name: String)] = []

    var levelLabel: SKLabelNode!
    var levelSubLabel: SKLabelNode!
    var statusLabel: SKLabelNode!
    var highlightOverlay: SKShapeNode?

    private var undoStack: [[String]] = []
    private var redoStack: [[String]] = []
    private var clipboard: [String]? = nil
    private var lastSavedHash: Int = 0
    private var buttonBaseColors: [String: SKColor] = [:]
    private var buttonNodes: [String: SKShapeNode] = [:]
    private var pendingFlashName: String?
    private var levelHeadingGlyph: SKNode?
    private let maxUndoDepth = 50
    var saveButton: SKShapeNode!
    var saveButtonLabel: SKLabelNode?
    private let autosaveInterval: TimeInterval = 60
    private var isPainting = false

    var gridOffsetX: CGFloat = 12
    var gridOffsetY: CGFloat = 12

    private static func paletteName(for char: Character) -> String {
        "\(Strings.NodeName.palettePrefix)\(char)"
    }

    private var currentCubicleColor: SKColor {
        SpriteFactory.cubicleColors[currentLevelIndex % SpriteFactory.cubicleColors.count]
    }

    // MARK: - Lifecycle
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(white: 0.08, alpha: 1.0)
        anchorPoint = .zero
        addChild(gridContainer)
        addChild(uiContainer)
        buildUI()
        loadCurrentLevel()
        scheduleAutosave()
    }

    override func willMove(from view: SKView) {
        autosaveIfDirty()
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
        saveCurrentLevel()
        saveButtonLabel?.text = Strings.Editor.autosaveToast
        statusLabel?.text = Strings.Editor.autosaveToast
        run(.sequence([
            .wait(forDuration: 3),
            .run { [weak self] in
                guard let self else { return }
                self.saveButtonLabel?.text = Strings.Editor.save
                self.statusLabel?.text = Strings.Editor.tilePrefix(self.selectedTile.displayName)
            }
        ]), withKey: "autosaveRevert")
    }

    // MARK: - UI
    func buildUI() {
        uiContainer.removeAllChildren()
        buttonRects.removeAll()

        let panelW: CGFloat = 148
        let panelX = size.width - panelW - 4

        let panel = SKShapeNode(rect: CGRect(x: panelX, y: 0, width: panelW + 4, height: size.height))
        panel.fillColor = SKColor(white: 0.15, alpha: 0.97)
        panel.strokeColor = SKColor(white: 0.35, alpha: 1.0)
        panel.lineWidth = 2
        panel.zPosition = 100
        uiContainer.addChild(panel)

        let cx = panelX + panelW / 2 + 2

        let title = SKLabelNode(fontNamed: Strings.Font.menloBold)
        title.text = Strings.Editor.title
        title.fontSize = 13
        title.fontColor = .white
        title.position = CGPoint(x: cx, y: size.height - 24)
        title.zPosition = 101
        uiContainer.addChild(title)

        levelLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
        levelLabel.text = ""
        levelLabel.fontSize = 11
        levelLabel.fontColor = .systemBlue
        levelLabel.position = CGPoint(x: cx, y: size.height - 46)
        levelLabel.zPosition = 101
        levelLabel.numberOfLines = 2
        levelLabel.horizontalAlignmentMode = .center
        uiContainer.addChild(levelLabel)

        levelSubLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
        levelSubLabel.text = ""
        levelSubLabel.fontSize = 11
        levelSubLabel.fontColor = .systemBlue
        levelSubLabel.position = CGPoint(x: cx, y: size.height - 60)
        levelSubLabel.zPosition = 101
        levelSubLabel.horizontalAlignmentMode = .center
        uiContainer.addChild(levelSubLabel)

        statusLabel = SKLabelNode(fontNamed: Strings.Font.menlo)
        statusLabel.text = Strings.Editor.tileWallInitial
        statusLabel.fontSize = 10
        statusLabel.fontColor = .yellow
        statusLabel.position = CGPoint(x: cx, y: size.height - 78)
        statusLabel.zPosition = 101
        uiContainer.addChild(statusLabel)

        paletteNodes = []
        paletteRects = []
        let palStartY = size.height - 89
        let palSpacing: CGFloat = 17

        for (i, tile) in EditorTile.all.enumerated() {
            let y = palStartY - 24 - CGFloat(i) * palSpacing
            let swatchRect = CGRect(x: panelX + 8, y: y, width: panelW - 12, height: palSpacing)
            let palName = LevelEditorScene.paletteName(for: tile.character)

            let bg = SKShapeNode(rect: swatchRect)
            bg.fillColor = floorColor(forParity: 0)
            bg.strokeColor = SKColor(white: 0.4, alpha: 1.0)
            bg.lineWidth = 1
            bg.zPosition = 101
            bg.name = palName
            uiContainer.addChild(bg)
            paletteNodes.append(bg)
            paletteRects.append(swatchRect)

            let preview = renderTile(char: tile.character, size: palSpacing - 6, isPaletteSwatch: true)
            preview.position = CGPoint(x: panelX + 8 + (palSpacing - 6) / 2 + 3, y: y + palSpacing / 2)
            preview.zPosition = 102
            uiContainer.addChild(preview)

            let lbl = SKLabelNode(fontNamed: Strings.Font.menloBold)
            lbl.text = tile.displayName
            lbl.fontSize = 10
            lbl.fontColor = .white
            lbl.horizontalAlignmentMode = .left
            lbl.verticalAlignmentMode = .center
            lbl.position = CGPoint(x: panelX + 8 + palSpacing + 4, y: y + palSpacing / 2)
            lbl.zPosition = 102
            uiContainer.addChild(lbl)
        }

        let btnData: [(String, SKColor, String)] = [
            (Strings.Editor.prev,       SKColor(white: 0.42, alpha: 1.0),                        Strings.EditorButton.prev),
            (Strings.Editor.next,       SKColor(white: 0.34, alpha: 1.0),                        Strings.EditorButton.next),
            (Strings.Editor.undo,       SKColor(white: 0.26, alpha: 1.0),                        Strings.EditorButton.undo),
            (Strings.Editor.redo,       SKColor(white: 0.18, alpha: 1.0),                        Strings.EditorButton.redo),
            (Strings.Editor.clear,      SKColor(red: 0.6,  green: 0.15, blue: 0.15, alpha: 1.0), Strings.EditorButton.clear),
            (Strings.Editor.save,       SKColor(red: 0.15, green: 0.45, blue: 0.15, alpha: 1.0), Strings.EditorButton.save),
            (Strings.Editor.copy,       SKColor(red: 0.20, green: 0.40, blue: 0.30, alpha: 1.0), Strings.EditorButton.copy),
            (Strings.Editor.paste,      SKColor(red: 0.25, green: 0.35, blue: 0.30, alpha: 1.0), Strings.EditorButton.paste),
            (Strings.Editor.revealFile, SKColor(red: 0.25, green: 0.35, blue: 0.45, alpha: 1.0), Strings.EditorButton.reveal),
            (Strings.Editor.play,       SKColor(red: 0.15, green: 0.15, blue: 0.55, alpha: 1.0), Strings.EditorButton.play),
            (Strings.Editor.back,       SKColor(red: 0.45, green: 0.4,  blue: 0.15, alpha: 1.0), Strings.EditorButton.back),
        ]
        let btnHeight: CGFloat = 17
        let btnSpacing: CGFloat = 19
        let btnStartY = palStartY - 24 - CGFloat(EditorTile.all.count) * palSpacing - 13
        buttonBaseColors.removeAll()
        buttonNodes.removeAll()

        for (i, item) in btnData.enumerated() {
            let (titleText, color, name) = item
            let by = btnStartY - CGFloat(i) * btnSpacing
            let rect = CGRect(x: panelX + 8, y: by, width: panelW - 12, height: btnHeight)
            let btn = SKShapeNode(rect: rect)
            btn.fillColor = color
            btn.strokeColor = .clear
            btn.lineWidth = 0
            btn.zPosition = 101
            btn.name = name
            uiContainer.addChild(btn)
            buttonBaseColors[name] = color
            buttonNodes[name] = btn
            buttonRects.append((rect: rect, name: name))

            let lbl = SKLabelNode(fontNamed: Strings.Font.menloBold)
            lbl.text = titleText
            lbl.fontSize = 9
            lbl.fontColor = .white
            lbl.verticalAlignmentMode = .center
            lbl.horizontalAlignmentMode = .left
            lbl.position = CGPoint(x: panelX + 15, y: by + btnHeight / 2)
            lbl.zPosition = 102
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

        let availWidth = size.width - panelWidth - margin * 2 - 8
        let availHeight = size.height - margin * 2

        let fitW = gridCols > 0 ? availWidth / CGFloat(gridCols) : 32
        let fitH = gridRows > 0 ? availHeight / CGFloat(gridRows) : 32
        tileSize = max(min(fitW, fitH), 4)

        let totalW = CGFloat(gridCols) * tileSize
        let totalH = CGFloat(gridRows) * tileSize
        gridOffsetX = (availWidth - totalW) / 2 + margin
        gridOffsetY = (availHeight - totalH) / 2 + margin

        for row in 0..<gridRows {
            var rowNodes: [SKNode] = []
            for col in 0..<gridCols {
                let x = gridOffsetX + CGFloat(col) * tileSize
                let y = gridOffsetY + CGFloat(gridRows - 1 - row) * tileSize
                let container = SKNode()
                container.position = CGPoint(x: x + tileSize / 2, y: y + tileSize / 2)
                container.zPosition = 10
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

    // MARK: - Rendering (matches the in-game MazeBuilder visuals)
    private func floorColor(forParity parity: Int) -> SKColor {
        parity.isMultiple(of: 2) ? SpriteFactory.floorTileA : SpriteFactory.floorTileB
    }

    private func renderTileInto(_ container: SKNode, row: Int, col: Int, size: CGFloat) {
        let ch = charAt(row: row, col: col)
        addFloor(to: container, size: size, parity: row + col)
        addContent(to: container, char: ch, size: size)
    }

    private func renderTile(char: Character, size: CGFloat, isPaletteSwatch: Bool = false) -> SKNode {
        let container = SKNode()
        if !isPaletteSwatch { addFloor(to: container, size: size, parity: 0) }
        addContent(to: container, char: char, size: size)
        return container
    }

    private func addFloor(to container: SKNode, size: CGFloat, parity: Int) {
        let floor = SKShapeNode(rect: CGRect(x: -size / 2, y: -size / 2, width: size, height: size))
        floor.fillColor = floorColor(forParity: parity)
        floor.strokeColor = SpriteFactory.floorTileStroke
        floor.lineWidth = 0.5
        floor.isAntialiased = false
        container.addChild(floor)
    }

    private func addContent(to container: SKNode, char: Character, size: CGFloat) {
        switch char {
        case Strings.Tile.wallChar:        addWall(to: container, size: size)
        case Strings.Tile.dotChar:         addDot(to: container, size: size)
        case Strings.Tile.hideoutChar:     addLetter(to: container, text: Strings.Tile.hideout,
                                                      color: SKColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1),
                                                      size: size * 0.85)
        case Strings.Tile.waterPelletChar: container.addChild(SpriteFactory.waterPelletVisual(radius: size * 0.32))
        case Strings.Tile.printerChar:     addEmoji(to: container, text: Strings.Emoji.printer,    size: size)
        case Strings.Tile.faxChar:         addEmoji(to: container, text: Strings.Emoji.fax,        size: size)
        case Strings.Tile.coverSheetChar:  addEmoji(to: container, text: Strings.Emoji.coverSheet, size: size)
        case Strings.Tile.bookBinderChar:  addEmoji(to: container, text: Strings.Emoji.bookBinder, size: size)
        case Strings.Tile.brownBoxChar:    addEmoji(to: container, text: Strings.Emoji.brownBox,   size: size)
        case Strings.Tile.waterGunChar:    addEmoji(to: container, text: Strings.Emoji.waterGun,   size: size)
        case Strings.Tile.goldDiscChar:    container.addChild(SpriteFactory.goldDiscVisual(radius: size * 0.28))
        case Strings.Tile.workerChar:      addPerson(to: container, SpriteFactory.petePerson(), size: size)
        case Strings.Tile.boss1Char:       addPerson(to: container, SpriteFactory.bossPersonForBlueprint(0), size: size)
        case Strings.Tile.boss2Char:       addPerson(to: container, SpriteFactory.bossPersonForBlueprint(1), size: size)
        case Strings.Tile.boss3Char:       addPerson(to: container, SpriteFactory.bossPersonForBlueprint(2), size: size)
        case Strings.Tile.boss4Char:       addPerson(to: container, SpriteFactory.bossPersonForBlueprint(3), size: size)
        default: break
        }
    }

    private func addWall(to container: SKNode, size: CGFloat) {
        container.addChild(SpriteFactory.wallTile(size: size, color: currentCubicleColor))
    }

    private func addDot(to container: SKNode, size: CGFloat) {
        container.addChild(SpriteFactory.dotVisual(size: max(2, size * 0.20)))
    }

    private func addLetter(to container: SKNode, text: String, color: SKColor, size: CGFloat) {
        let label = SKLabelNode(fontNamed: Strings.Font.menloBold)
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        container.addChild(label)
    }

    private func addEmoji(to container: SKNode, text: String, size: CGFloat) {
        let label = SKLabelNode(fontNamed: Strings.Font.menlo)
        label.text = text
        label.fontSize = size * 0.72
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        container.addChild(label)
    }

    private func addPerson(to container: SKNode, _ person: PixelPerson, size: CGFloat) {
        person.setScale(size / 38)
        container.addChild(person)
    }

    // MARK: - Level loading
    func loadCurrentLevel() {
        let names = Levels.names
        guard currentLevelIndex < names.count else {
            currentLevelIndex = 0
            return loadCurrentLevel()
        }
        undoStack.removeAll()
        redoStack.removeAll()
        mapRows = LevelStore.loadLevel(index: currentLevelIndex)
        gridRows = LevelStore.mapRows
        gridCols = LevelStore.mapCols
        rebuildGrid()
        updateLevelLabel()
        buildUI()
        lastSavedHash = mapHash()
    }

    private func mapHash() -> Int {
        mapRows.joined(separator: "\n").hashValue
    }

    private func autosaveIfDirty() {
        if mapHash() != lastSavedHash {
            saveCurrentLevel()
            lastSavedHash = mapHash()
        }
    }

    func updateLevelLabel() {
        let names = Levels.names
        guard currentLevelIndex < names.count else { return }
        levelLabel?.text = names[currentLevelIndex]
        levelSubLabel?.text = Strings.Editor.levelCounter(currentLevelIndex + 1, of: names.count)

        levelHeadingGlyph?.removeFromParent()
        guard let lbl = levelLabel else { return }
        let traveler = levelTravelers[currentLevelIndex % levelTravelers.count]
        let glyph = SKLabelNode(fontNamed: Strings.Font.menlo)
        glyph.text = traveler.emoji
        glyph.fontSize = lbl.fontSize
        glyph.verticalAlignmentMode = .center
        glyph.horizontalAlignmentMode = .center
        glyph.position = CGPoint(x: lbl.position.x + lbl.measuredWidth() / 2 + 14, y: lbl.position.y)
        glyph.zPosition = lbl.zPosition
        uiContainer.addChild(glyph)
        levelHeadingGlyph = glyph
    }

    func updatePaletteHighlight() {
        for (i, node) in paletteNodes.enumerated() {
            node.lineWidth = 1
            node.strokeColor = SKColor(white: 0.4, alpha: 1.0)
            if i < EditorTile.all.count && EditorTile.all[i] == selectedTile && i < paletteRects.count {
                highlightOverlay?.removeFromParent()
                let r = paletteRects[i]
                let overlay = SKShapeNode(rect: CGRect(x: r.minX + 2, y: r.minY + 2,
                                                       width: r.width - 4, height: r.height - 4))
                overlay.fillColor = SKColor.yellow.withAlphaComponent(0.10)
                overlay.strokeColor = .yellow
                overlay.lineWidth = 1
                overlay.zPosition = 110
                uiContainer.addChild(overlay)
                highlightOverlay = overlay
            }
        }
        statusLabel?.text = Strings.Editor.tilePrefix(selectedTile.displayName)
    }

    // MARK: - Undo / redo / clipboard
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

    // No modal dialog on web: clear immediately, undoable via the pushed snapshot.
    private func confirmClearLevel() {
        pushUndoSnapshot()
        mapRows = mapRows.map { _ in String(repeating: Strings.Tile.floor, count: gridCols) }
        rebuildGrid()
        statusLabel?.text = Strings.Editor.clearedToast
    }

    private func revealStorage() {
        statusLabel?.text = Strings.Editor.revealToast
    }

    private func brightened(_ c: SKColor, _ f: CGFloat = 0.45) -> SKColor {
        SKColor(red: c.r + (1 - c.r) * f, green: c.g + (1 - c.g) * f,
                blue: c.b + (1 - c.b) * f, alpha: c.a)
    }

    private func flashButton(named name: String) {
        guard let btn = buttonNodes[name], let base = buttonBaseColors[name] else { return }
        btn.fillColor = brightened(base)
        btn.run(.sequence([
            .wait(forDuration: 0.5),
            .run { [weak self, weak btn] in btn?.fillColor = self?.buttonBaseColors[name] ?? base }
        ]), withKey: "btnflash")
    }

    // MARK: - Input
    override func mouseDown(at p: CGPoint) {
        if handleUITap(p) { return }
        pushUndoSnapshot()
        isPainting = true
        paint(at: p, tile: selectedTile)
    }

    override func mouseMoved(to p: CGPoint) {
        guard isPainting else { return }
        paint(at: p, tile: selectedTile)
    }

    override func mouseUp(at p: CGPoint) {
        isPainting = false
    }

    private func handleUITap(_ p: CGPoint) -> Bool {
        for (i, rect) in paletteRects.enumerated() where rect.contains(p) {
            if i < EditorTile.all.count {
                selectedTile = EditorTile.all[i]
                updatePaletteHighlight()
            }
            return true
        }
        for entry in buttonRects where entry.rect.contains(p) {
            flashButton(named: entry.name)
            runButtonAction(entry.name)
            return true
        }
        return false
    }

    private func runButtonAction(_ name: String) {
        switch name {
        case Strings.EditorButton.prev:
            autosaveIfDirty()
            let count = Levels.names.count
            currentLevelIndex = (currentLevelIndex - 1 + count) % count
            pendingFlashName = Strings.EditorButton.prev
            loadCurrentLevel()
        case Strings.EditorButton.next:
            autosaveIfDirty()
            currentLevelIndex = (currentLevelIndex + 1) % Levels.names.count
            pendingFlashName = Strings.EditorButton.next
            loadCurrentLevel()
        case Strings.EditorButton.undo:   undo()
        case Strings.EditorButton.redo:   redo()
        case Strings.EditorButton.clear:  confirmClearLevel()
        case Strings.EditorButton.save:   saveCurrentLevel()
        case Strings.EditorButton.copy:   copyLevel()
        case Strings.EditorButton.paste:  pasteLevel()
        case Strings.EditorButton.reveal: revealStorage()
        case Strings.EditorButton.play:   playCurrentLevel()
        case Strings.EditorButton.back:
            autosaveIfDirty()
            let title = TitleScene(size: size)
            title.scaleMode = .aspectFit
            view?.presentScene(title, transition: .fade(withDuration: 0.3))
        default: break
        }
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

    // MARK: - Play / save
    func playCurrentLevel() {
        autosaveIfDirty()
        let game = GameScene(size: size)
        game.scaleMode = .aspectFit
        game.practiceMode = true
        game.startingLevel = currentLevelIndex + 1
        view?.presentScene(game, transition: .fade(withDuration: 0.5))
    }

    func saveCurrentLevel() {
        let names = Levels.names
        guard currentLevelIndex < names.count else { return }
        LevelStore.saveLevel(index: currentLevelIndex, rows: mapRows)
        lastSavedHash = mapHash()
        saveButton?.fillColor = .green
        saveButton?.run(.sequence([
            .wait(forDuration: 0.5),
            .run { [weak self] in self?.saveButton?.fillColor = SKColor(red: 0.15, green: 0.45, blue: 0.15, alpha: 1.0) }
        ]), withKey: "savegreen")
        statusLabel?.text = Strings.Editor.savedToast
        run(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in
                guard let self else { return }
                self.statusLabel?.text = Strings.Editor.tilePrefix(self.selectedTile.displayName)
            }
        ]), withKey: "savetoast")
    }

    // MARK: - Keyboard (SF keycodes; Cmd combos are bare letters on the web)
    override func keyDown(_ key: Int) {
        switch key {
        case 36:                                   // Escape -> back to title
            autosaveIfDirty()
            let title = TitleScene(size: size)
            title.scaleMode = .aspectFit
            view?.presentScene(title, transition: .fade(withDuration: 0.3))
            return
        case 71:                                   // ArrowLeft -> prev
            autosaveIfDirty()
            let count = Levels.names.count
            currentLevelIndex = (currentLevelIndex - 1 + count) % count
            pendingFlashName = Strings.EditorButton.prev
            loadCurrentLevel()
            return
        case 72:                                   // ArrowRight -> next
            autosaveIfDirty()
            currentLevelIndex = (currentLevelIndex + 1) % Levels.names.count
            pendingFlashName = Strings.EditorButton.next
            loadCurrentLevel()
            return
        // Tile shortcuts (top-row digits + numpad)
        case 27, 76: selectedTile = .wall;     updatePaletteHighlight(); return   // 1
        case 28, 77: selectedTile = .dot;      updatePaletteHighlight(); return   // 2
        case 29, 78: selectedTile = .hideout;  updatePaletteHighlight(); return   // 3
        case 30, 79: selectedTile = .printer;  updatePaletteHighlight(); return   // 4
        case 31, 80: selectedTile = .fax;      updatePaletteHighlight(); return   // 5
        case 32, 81: selectedTile = .copy;     updatePaletteHighlight(); return   // 6
        case 33, 82: selectedTile = .collator; updatePaletteHighlight(); return   // 7
        case 34, 83: selectedTile = .brownBox; updatePaletteHighlight(); return   // 8
        case 26, 75: selectedTile = .empty;    updatePaletteHighlight(); return   // 0
        // Action shortcuts (bare letters stand in for the macOS Cmd combos)
        case 18: flashButton(named: Strings.EditorButton.save);   saveCurrentLevel()   // S
        case 15: flashButton(named: Strings.EditorButton.play);   playCurrentLevel()   // P
        case 2:  flashButton(named: Strings.EditorButton.copy);   copyLevel()          // C
        case 21: flashButton(named: Strings.EditorButton.paste);  pasteLevel()         // V
        case 25: flashButton(named: Strings.EditorButton.undo);   undo()               // Z
        case 24: flashButton(named: Strings.EditorButton.redo);   redo()               // Y
        case 17: flashButton(named: Strings.EditorButton.reveal); revealStorage()      // R
        case 59: flashButton(named: Strings.EditorButton.clear);  confirmClearLevel()  // Backspace
        default: break
        }
    }
}
