//
//  LevelEditorScene.swift
//  Boss-Man
//
//  2D Minecraft-like Level Editor for BossMan
//  Uses the EXACT same characters as the real ASCII levels:
//    '#' = wall, ' ' = floor, '.' = dot/pellet, 'P' = player, 'B' = boss spawn,
//    'D' = door, 'H' = hideout, 'M' = coffee machine,
//    'C' = coffee pickup, 'F' = filing cabinet
//

import AppKit
import SpriteKit
import Darwin // removexattr — strips macOS quarantine flag from saved files

// MARK: - Tile ↔ Character Mapping
//
// Editor tiles map 1:1 to the chars used by Levels.swift / MazeBuilder
// and render with the SAME visuals the game uses in-play: real cubicle
// walls (per-level color), yellow pellet dots, machine emojis from
// MazeBuilder.emoji(forSymbol:), a Brown-Box icon for `D`, etc.
struct EditorTile: Equatable {
    let character: Character
    let displayName: String

    static let empty    = EditorTile(character: " ", displayName: "Floor")
    static let dot      = EditorTile(character: ".", displayName: "Dot")
    static let wall     = EditorTile(character: "#", displayName: "Wall")
    static let hideout  = EditorTile(character: "H", displayName: "Hideout")
    static let printer  = EditorTile(character: "P", displayName: "Printer")
    static let fax      = EditorTile(character: "F", displayName: "Fax")
    static let copy     = EditorTile(character: "C", displayName: "Cover Sheet")
    static let collator = EditorTile(character: "M", displayName: "Book Binder")
    static let brownBox = EditorTile(character: "D", displayName: "Brown Box")
    static let goldDisc = EditorTile(character: "O", displayName: "Gold Disc")
    static let worker   = EditorTile(character: "W", displayName: "PETE")
    static let boss1    = EditorTile(character: "1", displayName: "BOSS")
    static let boss2    = EditorTile(character: "2", displayName: "LUMBERGH")
    static let boss3    = EditorTile(character: "3", displayName: "WADDAMS")
    static let boss4    = EditorTile(character: "4", displayName: "BOLTON")

    static let all: [EditorTile] = [
        .empty, .dot, .wall, .hideout,
        .printer, .fax, .copy, .collator, .brownBox,
        .goldDisc, .worker, .boss1, .boss2, .boss3, .boss4
    ]
}

// MARK: - Level Store
//
// User-edited levels live in ~/Library/Application Support/Boss-Man/levels.json
// as a flat name → [rows] dictionary. The bundled defaults in `officeMaps`
// are used as a fallback for any level not in the file, so the user only
// pays the storage cost for floors they've actually edited.
//
// Why Application Support and not the bundle: the .app bundle is read-only
// at runtime (and writing to it invalidates the code signature). The user
// can still find / hand-edit / version-control the JSON externally.
final class LevelStore {
    static let shared = LevelStore()

    /// `~/Library/Application Support/Boss-Man/levels.json`. Created on
    /// first save; missing file is treated as "no overrides".
    static var fileURL: URL {
        let fm = FileManager.default
        let dir = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))?
            .appendingPathComponent("Boss-Man", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/Boss-Man",
                                        isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("levels.json", isDirectory: false)
    }

    private func loadCustomLevels() -> [String: [String]] {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    private func saveCustomLevels(_ levels: [String: [String]]) {
        // Pretty-print so the file is human-editable in Notes/VS Code/etc.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(levels) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
        Self.dequarantine(Self.fileURL)
    }

    /// Drops the com.apple.quarantine extended attribute that App
    /// Sandbox stamps onto every file this app writes. Without this,
    /// double-clicking the JSON in Finder triggers Gatekeeper's
    /// "damaged app" warning instead of opening it in Xcode/TextEdit.
    static func dequarantine(_ url: URL) {
        _ = url.path.withCString { removexattr($0, "com.apple.quarantine", 0) }
    }

    /// Look up a level by name. Returns the user's edited copy if one
    /// exists, otherwise the bundled default.
    func loadLevel(name: String) -> [String]? {
        if let custom = loadCustomLevels()[name] { return custom }
        guard let idx = Levels.levelNames.firstIndex(of: name) else { return nil }
        return officeMaps[idx]
    }

    /// Look up by zero-based level index — used by GameScene.
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

    /// Wipe the user's edit for one level so it falls back to the bundled
    /// default again. Useful if the editor saves something unplayable.
    func resetLevel(name: String) {
        var custom = loadCustomLevels()
        custom.removeValue(forKey: name)
        saveCustomLevels(custom)
    }

    /// Open the containing folder in Finder so the user can hand-edit
    /// or back up `levels.json` directly.
    func revealInFinder() {
        let url = Self.fileURL
        // If the file doesn't exist yet, write an empty stub so Finder
        // selects something meaningful.
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data("{}".utf8).write(to: url)
        }
        Self.dequarantine(url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Level Editor Scene
class LevelEditorScene: SKScene {
    
    var tileSize: CGFloat = 32   // computed dynamically in rebuildGrid
    var gridRows = 0
    var gridCols = 0
    var mapRows: [String] = []          // The actual level data
    var selectedTile: EditorTile = .wall
    var currentLevelIndex = 0
    
    let panelWidth: CGFloat = 148
    let margin: CGFloat = 12
    
    var gridContainer = SKNode()
    var tileNodes: [[SKNode]] = []
    var paletteNodes: [SKShapeNode] = []

    // Same cubicle palette GameScene uses; index by level so the
    // editor wall color matches what the player will see in-play.
    private static let cubicleColors: [NSColor] = [
        .systemBlue,   .systemTeal, .systemIndigo, .systemGreen,  .systemPink, .systemBrown,
        .systemPurple, .systemRed,  .systemOrange, .systemYellow, .systemCyan, .systemGray // MIB level 12
    ]
    var uiContainer = SKNode()
    var levelLabel: SKLabelNode!
    var levelSubLabel: SKLabelNode!
    var statusLabel: SKLabelNode!
    /// Stroke-only overlay drawn on top of the currently-selected palette
    /// swatch. Drawn separately so the swatch's own fill stays behind its
    /// preview icon + label.
    var highlightOverlay: SKShapeNode?
    var saveButton: SKShapeNode!
    
    var gridOffsetX: CGFloat = 12
    var gridOffsetY: CGFloat = 12
    
    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        backgroundColor = NSColor(white: 0.08, alpha: 1.0)
        addChild(gridContainer)
        addChild(uiContainer)
        buildUI()
        loadCurrentLevel()
    }
    
    // MARK: - UI
    func buildUI() {
        uiContainer.removeAllChildren()
        
        let panelWidth: CGFloat = 148
        let panelX = frame.width - panelWidth - 4
        
        // Panel bg
        let panel = SKShapeNode(rect: CGRect(x: panelX, y: 0, width: panelWidth + 4, height: frame.height))
        panel.fillColor = NSColor(white: 0.15, alpha: 0.97)
        panel.strokeColor = NSColor(white: 0.35, alpha: 1.0)
        panel.lineWidth = 2
        panel.zPosition = 100
        uiContainer.addChild(panel)
        
        let cx = panelX + panelWidth / 2 + 2
        
        // Title
        let title = SKLabelNode(text: "LEVEL EDITOR")
        title.fontName = "Menlo-Bold"
        title.fontSize = 13
        title.fontColor = NSColor.white
        title.position = CGPoint(x: cx, y: frame.height - 24)
        title.zPosition = 101
        uiContainer.addChild(title)
        
        // Level name — line 1 ("Level N <traveler emoji>"), line 2 ("Name (N/12)")
        levelLabel = SKLabelNode(text: "")
        levelLabel.fontName = "Menlo-Bold"
        levelLabel.fontSize = 11
        levelLabel.fontColor = NSColor.cyan
        levelLabel.position = CGPoint(x: cx, y: frame.height - 46)
        levelLabel.zPosition = 101
        levelLabel.numberOfLines = 2
        levelLabel.horizontalAlignmentMode = .center
        uiContainer.addChild(levelLabel)
        levelSubLabel = SKLabelNode(text: "")
        levelSubLabel.fontName = "Menlo-Bold"
        levelSubLabel.fontSize = 11
        levelSubLabel.fontColor = NSColor.cyan
        levelSubLabel.position = CGPoint(x: cx, y: frame.height - 60)
        levelSubLabel.zPosition = 101
        levelSubLabel.horizontalAlignmentMode = .center
        uiContainer.addChild(levelSubLabel)
        
        // Status
        statusLabel = SKLabelNode(text: "Tile: Wall")
        statusLabel.fontName = "Menlo"
        statusLabel.fontSize = 10
        statusLabel.fontColor = NSColor.yellow
        statusLabel.position = CGPoint(x: cx, y: frame.height - 78)
        statusLabel.zPosition = 101
        uiContainer.addChild(statusLabel)
        
        // Palette
        paletteNodes = []
        let palStartY = frame.height - 92
        let palSpacing: CGFloat = 21
        
        for (i, tile) in EditorTile.all.enumerated() {
            let y = palStartY - 24 - CGFloat(i) * palSpacing
            let swatchRect = CGRect(x: panelX + 8, y: y, width: panelWidth - 12, height: palSpacing)
            // Dark floor background under the swatch so the wall/dot
            // overlays read the same as in the live grid.
            let bg = SKShapeNode(rect: swatchRect)
            bg.fillColor = floorColor(forParity: 0)
            bg.strokeColor = NSColor(white: 0.4, alpha: 1.0)
            bg.lineWidth = 1
            bg.zPosition = 101
            bg.name = "pal_\(tile.character)"
            uiContainer.addChild(bg)
            paletteNodes.append(bg)

            // Tiny preview node — same renderer as the grid, scaled to
            // fit on the left side of the swatch.
            let preview = renderTile(char: tile.character, size: palSpacing - 6, isPaletteSwatch: true)
            preview.position = CGPoint(x: panelX + 8 + (palSpacing - 6) / 2 + 3,
                                       y: y + (palSpacing) / 2)
            preview.zPosition = 102
            preview.name = "pal_\(tile.character)"
            uiContainer.addChild(preview)

            let lbl = SKLabelNode(text: tile.displayName)
            lbl.fontName = "Menlo-Bold"
            lbl.fontSize = 10
            lbl.fontColor = .white
            lbl.horizontalAlignmentMode = .left
            lbl.verticalAlignmentMode = .center
            // Left-justified, sitting just to the right of the preview icon.
            lbl.position = CGPoint(x: panelX + 8 + palSpacing + 4,
                                   y: y + (palSpacing) / 2)
            lbl.zPosition = 102
            lbl.name = "pal_\(tile.character)"
            uiContainer.addChild(lbl)
        }
        
        // Buttons
        let btnData: [(String, NSColor, String)] = [
            ("< PREV",     NSColor(white: 0.28, alpha: 1.0),              "btn_prev"),
            ("NEXT >",     NSColor(white: 0.28, alpha: 1.0),              "btn_next"),
            ("CLEAR",      NSColor(calibratedRed: 0.6, green: 0.15, blue: 0.15, alpha: 1.0), "btn_clear"),
            ("SAVE (⌘S)",  NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.15, alpha: 1.0), "btn_save"),
            ("REVEAL FILE", NSColor(calibratedRed: 0.25, green: 0.35, blue: 0.45, alpha: 1.0), "btn_reveal"),
            ("PLAY",       NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.55, alpha: 1.0), "btn_play"),
            ("BACK (ESC)", NSColor(calibratedRed: 0.45, green: 0.4, blue: 0.15, alpha: 1.0),  "btn_back"),
        ]
        let btnHeight: CGFloat = 20
        let btnSpacing: CGFloat = 22
        let btnStartY = palStartY - 24 - CGFloat(EditorTile.all.count) * palSpacing - 18

        for (i, (title, color, name)) in btnData.enumerated() {
            let by = btnStartY - CGFloat(i) * btnSpacing
            let btn = SKShapeNode(rect: CGRect(x: panelX + 8, y: by, width: panelWidth - 12, height: btnHeight))
            btn.fillColor = color
            btn.strokeColor = .clear
            btn.lineWidth = 0
            btn.zPosition = 101
            btn.name = name
            uiContainer.addChild(btn)

            let lbl = SKLabelNode(text: title)
            lbl.fontName = "Menlo-Bold"
            lbl.fontSize = 9
            lbl.fontColor = NSColor.white
            lbl.verticalAlignmentMode = .center
            lbl.horizontalAlignmentMode = .center
            lbl.position = CGPoint(x: cx, y: by + btnHeight / 2)
            lbl.zPosition = 102
            lbl.name = name
            uiContainer.addChild(lbl)

            if name == "btn_save" { saveButton = btn }
        }
        
        updatePaletteHighlight()
        updateLevelLabel()
    }
    
    // MARK: - Grid
    func rebuildGrid() {
        gridContainer.removeAllChildren()
        tileNodes = []
        
        // Auto-calculate tile size so the full grid fits left of the panel
        let availWidth = frame.width - panelWidth - margin * 2 - 8
        let availHeight = frame.height - margin * 2
        
        let fitW = gridCols > 0 ? availWidth / CGFloat(gridCols) : 32
        let fitH = gridRows > 0 ? availHeight / CGFloat(gridRows) : 32
        tileSize = min(fitW, fitH)
        tileSize = max(tileSize, 4) // minimum 4px per tile
        
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
                // File / array row 0 is the TOP row of the level. SpriteKit
                // y grows upward, so flip the visual Y so mapRows[0] draws
                // at the top of the canvas — otherwise the editor and the
                // game (which iterates `map.rows.reversed()`) disagree
                // about which side is up.
                let y = offsetY + CGFloat(gridRows - 1 - row) * tileSize
                let container = SKNode()
                container.position = CGPoint(x: x + tileSize / 2, y: y + tileSize / 2)
                container.zPosition = 10
                container.name = "tile_\(row)_\(col)"
                gridContainer.addChild(container)
                renderTileInto(container, row: row, col: col, size: tileSize)
                rowNodes.append(container)
            }
            tileNodes.append(rowNodes)
        }
    }
    
    func charAt(row: Int, col: Int) -> Character {
        // mapRows[0] is the TOP row of the visual grid (highest Y)
        guard row < mapRows.count else { return " " }
        let chars = Array(mapRows[row])
        guard col < chars.count else { return " " }
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

    /// Cubicle color for the floor currently being edited — matches the
    /// GameScene palette so wall color in the editor == wall color in
    /// play for that level.
    private var currentCubicleColor: NSColor {
        Self.cubicleColors[currentLevelIndex % Self.cubicleColors.count]
    }

    /// Subtle floor checkerboard like MazeBuilder.makeBackground draws.
    private func floorColor(forParity parity: Int) -> NSColor {
        parity.isMultiple(of: 2)
            ? NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.13, alpha: 1)
            : NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.11, alpha: 1)
    }

    /// Render the visuals for `ch` into `container`, centered on
    /// (0, 0) and sized `size` × `size`. Mirrors MazeBuilder's wall,
    /// dot, and machine output so the editor reads exactly like the
    /// game floor.
    private func renderTileInto(_ container: SKNode, row: Int, col: Int, size: CGFloat) {
        let ch = charAt(row: row, col: col)
        let parity = row + col
        addFloor(to: container, size: size, parity: parity)
        addContent(to: container, char: ch, size: size)
    }

    /// Standalone tile renderer used by the palette swatches. Falls back
    /// to the checkerboard parity 0.
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
        case "#":
            addWall(to: container, size: size)
        case ".":
            addDot(to: container, size: size)
        case "H":
            // Hideouts render as dots in the live game; in the editor
            // we draw the dot plus a small purple "H" so the designer
            // can see and validate alcove placement.
            addDot(to: container, size: size)
            addLetter(to: container, text: "H", color: .systemPurple, size: size * 0.85)
        case "P", "F", "C", "M", "D":
            // Same emoji the live MazeBuilder draws.
            addEmoji(to: container, text: MazeBuilder.emoji(forSymbol: String(char)), size: size)
        case "O":
            // Gold disc — same yellow sphere look as the live pickup.
            addGoldDisc(to: container, size: size)
        case "W":
            // PETE worker — the live PixelPerson, miniaturized.
            addPete(to: container, size: size)
        case "1":
            addBoss(to: container, name: "BOSS",
                    body: .systemRed,    tie: .black,        size: size)
        case "2":
            addBoss(to: container, name: "LUMBERGH",
                    body: .systemPurple, tie: .systemYellow, size: size)
        case "3":
            addBoss(to: container, name: "WADDAMS",
                    body: .systemOrange, tie: .systemRed,    size: size)
        case "4":
            addBoss(to: container, name: "BOLTON",
                    body: .systemPink,   tie: .systemTeal,   size: size)
        default:
            break
        }
    }

    /// Wall = cubicleColor block with edge stroke and the gray "trim"
    /// rectangle near the top, same as MazeBuilder.makeBackground.
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
        label.fontName = "Menlo-Bold"
        label.fontSize = size
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        container.addChild(label)
    }

    private func addEmoji(to container: SKNode, text: String, size: CGFloat) {
        let label = SKLabelNode(text: text)
        // Emojis render in any font but Menlo gives a consistent size.
        label.fontName = "Menlo"
        label.fontSize = size * 0.72
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        container.addChild(label)
    }

    /// Glowing yellow sphere identical in spirit to MazeBuilder's gold
    /// disc sprite. Slightly faked because the live sprite uses a
    /// texture; here we composite two circles.
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

    /// PETE — the live PixelPerson, scaled to fit the editor cell.
    private func addPete(to container: SKNode, size: CGFloat) {
        let person = PixelPerson(
            bodyColor: .systemTeal,
            tieColor: .systemBlue,
            hairColor: NSColor(calibratedRed: 0.25, green: 0.15, blue: 0.08, alpha: 1),
            shoeOutlineColor: .white,
            pantsColor: NSColor(calibratedRed: 0.70, green: 0.45, blue: 0.18, alpha: 1)
        )
        // The PixelPerson body is ~32pt tall in-game; scale to fit the
        // editor tile.
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
            pantsColor: .darkGray
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
        
        if let rows = LevelStore.shared.loadLevel(name: name) {
            mapRows = rows
            gridRows = rows.count
            gridCols = rows.first?.count ?? 0
        } else {
            gridRows = 17
            gridCols = 36
            mapRows = Array(repeating: String(repeating: " ", count: gridCols), count: gridRows)
        }
        
        rebuildGrid()
        updateLevelLabel()
    }
    
    func updateLevelLabel() {
        let names = Levels.levelNames
        guard currentLevelIndex < names.count else { return }
        // Level names already encode the traveler emoji, e.g.
        // "Level 1 - 🐟". Just display them verbatim, with the position
        // counter on the second line.
        // JSON keys are "Level N - emoji"; drop the " -" for display.
        levelLabel?.text = names[currentLevelIndex].replacingOccurrences(of: " - ", with: " ")
        levelSubLabel?.text = "(\(currentLevelIndex + 1)/\(names.count))"
    }
    
    func updatePaletteHighlight() {
        for (i, node) in paletteNodes.enumerated() {
            node.lineWidth = 1
            node.strokeColor = NSColor(white: 0.4, alpha: 1.0)
            if i < EditorTile.all.count && EditorTile.all[i] == selectedTile {
                // Stroke-only overlay sitting on top of everything in
                // the palette column so the yellow ring is never clipped
                // and the preview icon + label stay visible.
                highlightOverlay?.removeFromParent()
                let overlay = SKShapeNode(rect: node.frame.insetBy(dx: 1, dy: 1))
                overlay.fillColor = .clear
                overlay.strokeColor = NSColor.yellow
                overlay.lineWidth = 1.5
                overlay.zPosition = 110
                uiContainer.addChild(overlay)
                highlightOverlay = overlay
            }
        }
        statusLabel?.text = "Tile: \(selectedTile.displayName)"
    }
    
    // MARK: - Input
    override func mouseDown(with event: NSEvent) {
        handleInput(event.location(in: self), begin: true)
    }
    
    override func mouseDragged(with event: NSEvent) {
        handleInput(event.location(in: self), begin: false)
    }
    
    override func mouseUp(with event: NSEvent) { }
    
    override func rightMouseDown(with event: NSEvent) {
        paint(at: event.location(in: self), tile: .empty)
    }
    
    override func rightMouseDragged(with event: NSEvent) {
        paint(at: event.location(in: self), tile: .empty)
    }
    
    func handleInput(_ loc: CGPoint, begin: Bool) {
        if begin {
            let node = atPoint(loc)
            let name = node.name ?? ""
            
            // Palette click
            if name.hasPrefix("pal_") {
                let ch = name.suffix(1).first!
                if let tile = EditorTile.all.first(where: { $0.character == ch }) {
                    selectedTile = tile
                    updatePaletteHighlight()
                }
                return
            }
            
            switch name {
            case "btn_prev":
                // Wrap: level 1's PREV jumps to the last level.
                let count = Levels.levelNames.count
                currentLevelIndex = (currentLevelIndex - 1 + count) % count
                loadCurrentLevel()
                return
            case "btn_next":
                // Wrap: last level's NEXT jumps back to level 1.
                currentLevelIndex = (currentLevelIndex + 1) % Levels.levelNames.count
                loadCurrentLevel()
                return
            case "btn_clear":
                mapRows = mapRows.map { _ in String(repeating: " ", count: gridCols) }
                rebuildGrid()
                return
            case "btn_save":
                saveCurrentLevel()
                return
            case "btn_reveal":
                LevelStore.shared.revealInFinder()
                return
            case "btn_play":
                saveCurrentLevel()
                let game = GameScene(size: size)
                game.scaleMode = .aspectFit
                view?.presentScene(game, transition: .fade(withDuration: 0.5))
                return
            case "btn_back":
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
    
    // MARK: - Save
    func saveCurrentLevel() {
        let names = Levels.levelNames
        guard currentLevelIndex < names.count else { return }
        LevelStore.shared.saveLevel(name: names[currentLevelIndex], rows: mapRows)
        
        saveButton?.fillColor = NSColor.green
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.saveButton?.fillColor = NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.15, alpha: 1.0)
        }
        statusLabel?.text = "SAVED!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.statusLabel?.text = "Tile: \(self.selectedTile.displayName)"
        }
    }
    
    // MARK: - Keyboard
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // ESC
            let title = TitleScene(size: size)
            title.scaleMode = .aspectFit
            view?.presentScene(title, transition: .fade(withDuration: 0.3))
        default: break
        }
        
        if let chars = event.characters {
            switch chars {
            case "1": selectedTile = .wall
            case "2": selectedTile = .dot
            case "3": selectedTile = .hideout
            case "4": selectedTile = .printer
            case "5": selectedTile = .fax
            case "6": selectedTile = .copy
            case "7": selectedTile = .collator
            case "8": selectedTile = .brownBox
            case "0": selectedTile = .empty
            case "s" where event.modifierFlags.contains(.command):
                saveCurrentLevel()
            default: break
            }
        }
        updatePaletteHighlight()
    }
}
