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

// MARK: - Tile ↔ Character Mapping
struct EditorTile: Equatable {
    let character: Character
    let displayName: String
    let color: NSColor
    
    static let empty     = EditorTile(character: " ", displayName: "Floor",   color: NSColor(white: 0.22, alpha: 1.0))
    static let dot       = EditorTile(character: ".", displayName: "Dot",     color: NSColor(calibratedRed: 0.85, green: 0.75, blue: 0.55, alpha: 1.0))
    static let wall      = EditorTile(character: "#", displayName: "Wall",    color: NSColor(white: 0.50, alpha: 1.0))
    static let player    = EditorTile(character: "P", displayName: "Player",  color: NSColor.cyan)
    static let boss      = EditorTile(character: "B", displayName: "Boss",    color: NSColor.red)
    static let door      = EditorTile(character: "D", displayName: "Door",    color: NSColor(calibratedRed: 0.6, green: 0.4, blue: 0.2, alpha: 1.0))
    static let hideout   = EditorTile(character: "H", displayName: "Hideout", color: NSColor(calibratedRed: 0.3, green: 0.1, blue: 0.5, alpha: 1.0))
    static let machine   = EditorTile(character: "M", displayName: "Machine", color: NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.1, alpha: 1.0))
    static let coffee    = EditorTile(character: "C", displayName: "Coffee",  color: NSColor(calibratedRed: 0.4, green: 0.2, blue: 0.1, alpha: 1.0))
    static let files     = EditorTile(character: "F", displayName: "Files",   color: NSColor.gray)
    
    static let all: [EditorTile] = [
        .empty, .dot, .wall, .door, .hideout, .machine, .coffee, .files
    ]
}

// MARK: - Level Store (saves custom levels to UserDefaults as string maps)
class LevelStore {
    static let shared = LevelStore()
    private let defaults = UserDefaults.standard
    private let key = "BossMan.CustomLevels"
    
    func loadCustomLevels() -> [String: [String]]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([String: [String]].self, from: data)
    }
    
    func saveCustomLevels(_ levels: [String: [String]]) {
        if let data = try? JSONEncoder().encode(levels) {
            defaults.set(data, forKey: key)
        }
    }
    
    func loadLevel(name: String) -> [String]? {
        if let custom = loadCustomLevels()?[name] { return custom }
        guard let idx = Levels.levelNames.firstIndex(of: name) else { return nil }
        return officeMaps[idx]
    }
    
    func saveLevel(name: String, rows: [String]) {
        var custom = loadCustomLevels() ?? [:]
        custom[name] = rows
        saveCustomLevels(custom)
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
    var tileNodes: [[SKShapeNode]] = []
    var paletteNodes: [SKShapeNode] = []
    var uiContainer = SKNode()
    var levelLabel: SKLabelNode!
    var statusLabel: SKLabelNode!
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
        
        // Level name
        levelLabel = SKLabelNode(text: "")
        levelLabel.fontName = "Menlo-Bold"
        levelLabel.fontSize = 11
        levelLabel.fontColor = NSColor.cyan
        levelLabel.position = CGPoint(x: cx, y: frame.height - 46)
        levelLabel.zPosition = 101
        uiContainer.addChild(levelLabel)
        
        // Status
        statusLabel = SKLabelNode(text: "Tile: Wall")
        statusLabel.fontName = "Menlo"
        statusLabel.fontSize = 10
        statusLabel.fontColor = NSColor.yellow
        statusLabel.position = CGPoint(x: cx, y: frame.height - 64)
        statusLabel.zPosition = 101
        uiContainer.addChild(statusLabel)
        
        // Palette
        paletteNodes = []
        let palStartY = frame.height - 88
        let palSpacing: CGFloat = 24
        
        let palTitle = SKLabelNode(text: "— TILES —")
        palTitle.fontName = "Menlo-Bold"
        palTitle.fontSize = 10
        palTitle.fontColor = NSColor(white: 0.55, alpha: 1.0)
        palTitle.position = CGPoint(x: cx, y: palStartY)
        palTitle.zPosition = 101
        uiContainer.addChild(palTitle)
        
        for (i, tile) in EditorTile.all.enumerated() {
            let y = palStartY - 18 - CGFloat(i) * palSpacing
            let rect = SKShapeNode(rect: CGRect(x: panelX + 8, y: y, width: panelWidth - 12, height: palSpacing - 2))
            rect.fillColor = tile.color
            rect.strokeColor = NSColor(white: 0.4, alpha: 1.0)
            rect.lineWidth = 1
            rect.zPosition = 101
            rect.name = "pal_\(tile.character)"
            uiContainer.addChild(rect)
            paletteNodes.append(rect)
            
            let lbl = SKLabelNode(text: tile.displayName)
            lbl.fontName = "Menlo-Bold"
            lbl.fontSize = 10
            lbl.fontColor = (tile == .empty || tile == .hideout) ? NSColor.white : NSColor.black
            lbl.position = CGPoint(x: cx, y: y + 5)
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
            ("PLAY",       NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.55, alpha: 1.0), "btn_play"),
            ("BACK (ESC)", NSColor(calibratedRed: 0.45, green: 0.4, blue: 0.15, alpha: 1.0),  "btn_back"),
        ]
        let btnStartY = palStartY - 18 - CGFloat(EditorTile.all.count) * palSpacing - 16
        
        for (i, (title, color, name)) in btnData.enumerated() {
            let by = btnStartY - CGFloat(i) * 36
            let btn = SKShapeNode(rect: CGRect(x: panelX + 8, y: by, width: panelWidth - 12, height: 28))
            btn.fillColor = color
            btn.strokeColor = NSColor(white: 0.5, alpha: 1.0)
            btn.lineWidth = 2
            btn.zPosition = 101
            btn.name = name
            uiContainer.addChild(btn)
            
            let lbl = SKLabelNode(text: title)
            lbl.fontName = "Menlo-Bold"
            lbl.fontSize = 10
            lbl.fontColor = NSColor.white
            lbl.position = CGPoint(x: cx, y: by + 7)
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
            var rowNodes: [SKShapeNode] = []
            for col in 0..<gridCols {
                let x = offsetX + CGFloat(col) * tileSize
                let y = offsetY + CGFloat(row) * tileSize
                let ch = charAt(row: row, col: col)
                let tile = tileForChar(ch)
                
                let node = SKShapeNode(rect: CGRect(x: 0, y: 0, width: tileSize - 1, height: tileSize - 1))
                node.position = CGPoint(x: x, y: y)
                node.fillColor = tile.color
                node.strokeColor = NSColor(white: 0.20, alpha: 1.0)
                node.lineWidth = 0.5
                node.zPosition = 10
                node.name = "tile_\(row)_\(col)"
                gridContainer.addChild(node)
                rowNodes.append(node)
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
    
    func tileForChar(_ ch: Character) -> EditorTile {
        switch ch {
        case "#": return .wall
        case ".": return .dot
        case "P": return .player
        case "B": return .boss
        case "D": return .door
        case "H": return .hideout
        case "M": return .machine
        case "C": return .coffee
        case "F": return .files
        default:  return .empty
        }
    }
    
    func updateTileVisual(row: Int, col: Int) {
        guard row < tileNodes.count, col < tileNodes[row].count else { return }
        let ch = charAt(row: row, col: col)
        tileNodes[row][col].fillColor = tileForChar(ch).color
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
        if currentLevelIndex < names.count {
            levelLabel?.text = "\(names[currentLevelIndex]) (\(currentLevelIndex + 1)/\(names.count))"
        }
    }
    
    func updatePaletteHighlight() {
        for (i, node) in paletteNodes.enumerated() {
            if i < EditorTile.all.count && EditorTile.all[i] == selectedTile {
                node.lineWidth = 3
                node.strokeColor = NSColor.yellow
            } else {
                node.lineWidth = 1
                node.strokeColor = NSColor(white: 0.4, alpha: 1.0)
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
                if currentLevelIndex > 0 { currentLevelIndex -= 1; loadCurrentLevel() }
                return
            case "btn_next":
                if currentLevelIndex < Levels.levelNames.count - 1 { currentLevelIndex += 1; loadCurrentLevel() }
                return
            case "btn_clear":
                mapRows = mapRows.map { _ in String(repeating: " ", count: gridCols) }
                rebuildGrid()
                return
            case "btn_save":
                saveCurrentLevel()
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
        let row = Int((loc.y - gridOffsetY) / tileSize)
        
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
            case "3": selectedTile = .door
            case "4": selectedTile = .hideout
            case "5": selectedTile = .machine
            case "6": selectedTile = .coffee
            case "7": selectedTile = .files
            case "0": selectedTile = .empty
            case "s" where event.modifierFlags.contains(.command):
                saveCurrentLevel()
            default: break
            }
        }
        updatePaletteHighlight()
    }
}
