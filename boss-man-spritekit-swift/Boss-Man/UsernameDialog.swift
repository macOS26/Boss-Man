import AppKit
import SpriteKit

// Game-over username entry dialog, shared by both ports (wasm is the master for
// the leaderboard / initials flow). Pure SpriteKit — no NSTextField — so it
// renders and types identically on macOS and wasm:
//
//   - White panel with a blue Save button + outlined Skip button.
//   - SKLabelNode shows the typed username with a blinking caret.
//   - A-Z, 0-9, Space append characters (max 16, no leading whitespace).
//   - Backspace removes the last character.
//   - Return commits (or skips if empty) — calls onConfirm.
//   - Escape calls onSkip.
//
// The dialog absorbs all input while open; GameScene checks the active
// dialog before routing keys to the gameplay handler.
@MainActor
final class UsernameDialog: SKNode {

    static let nodeName = "usernameDialog"

    private let panelSize: CGSize
    private let fontName: String
    private let onConfirm: (String) -> Void
    private let onSkip: () -> Void

    private let inputLabel  = SKLabelNode()
    private let caretLabel  = SKLabelNode()
    private(set) var typed: String = ""
    private let maxLength = 16

    init(size: CGSize, fontName: String, onConfirm: @escaping (String) -> Void, onSkip: @escaping () -> Void) {
        self.panelSize  = size
        self.fontName   = fontName
        self.onConfirm  = onConfirm
        self.onSkip     = onSkip
        super.init()
        self.name = Self.nodeName
        self.typed = LocalHighScores.savedUsername ?? ""
        buildUI()
        refreshInput()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        let overlay = SKShapeNode(rect: CGRect(x: -2000, y: -2000, width: 4000, height: 4000))
        overlay.fillColor = SKColor(white: 0, alpha: 0.55)
        overlay.strokeColor = .clear
        overlay.zPosition = 999
        addChild(overlay)

        let bg = SKShapeNode(rect: CGRect(x: -panelSize.width / 2, y: -panelSize.height / 2,
                                          width: panelSize.width, height: panelSize.height),
                             cornerRadius: 12)
        bg.fillColor = SKColor(white: 1, alpha: 0.96)
        bg.strokeColor = SKColor(white: 0.7, alpha: 1)
        bg.lineWidth = 2
        bg.zPosition = 1000
        addChild(bg)

        let title = SKLabelNode(fontNamed: fontName)
        title.text = Strings.Leaderboard.newHighScoreTitle
        title.fontSize = 22
        title.fontColor = SKColor(red: 0.18, green: 0.10, blue: 0.04, alpha: 1)
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: panelSize.height / 2 - 38)
        title.zPosition = 1001
        addChild(title)

        let prompt = SKLabelNode(fontNamed: fontName)
        prompt.text = Strings.Leaderboard.enterUsernamePrompt
        prompt.fontSize = 16
        prompt.fontColor = SKColor(white: 0.35, alpha: 1)
        prompt.horizontalAlignmentMode = .center
        prompt.verticalAlignmentMode = .center
        prompt.position = CGPoint(x: 0, y: panelSize.height / 2 - 64)
        prompt.zPosition = 1001
        addChild(prompt)

        // Input field rectangle (purely cosmetic — the SKLabelNode below
        // renders the typed text).
        let fieldRect = SKShapeNode(rect: CGRect(x: -panelSize.width / 2 + 30, y: 0,
                                                  width: panelSize.width - 60, height: 36),
                                     cornerRadius: 6)
        fieldRect.fillColor = SKColor(white: 0.96, alpha: 1)
        fieldRect.strokeColor = SKColor(white: 0.6, alpha: 1)
        fieldRect.lineWidth = 1
        fieldRect.zPosition = 1001
        addChild(fieldRect)

        inputLabel.fontName = fontName
        inputLabel.fontSize = 18
        inputLabel.fontColor = SKColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1)
        inputLabel.horizontalAlignmentMode = .left
        inputLabel.verticalAlignmentMode = .center
        inputLabel.position = CGPoint(x: -panelSize.width / 2 + 42, y: 18)
        inputLabel.zPosition = 1002
        addChild(inputLabel)

        caretLabel.text = "|"
        caretLabel.fontName = fontName
        caretLabel.fontSize = 18
        caretLabel.fontColor = SKColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1)
        caretLabel.horizontalAlignmentMode = .left
        caretLabel.verticalAlignmentMode = .center
        caretLabel.zPosition = 1002
        caretLabel.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.0, duration: 0.45),
            .fadeAlpha(to: 1.0, duration: 0.45),
        ])))
        addChild(caretLabel)

        let confirmBtn = SKShapeNode(rect: CGRect(x: -100, y: -panelSize.height / 2 + 18,
                                                   width: 200, height: 34),
                                      cornerRadius: 8)
        confirmBtn.fillColor = SKColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1)
        confirmBtn.strokeColor = .clear
        confirmBtn.zPosition = 1001
        addChild(confirmBtn)

        let confirmLabel = SKLabelNode(fontNamed: fontName)
        confirmLabel.text = Strings.Leaderboard.saveButton
        confirmLabel.fontSize = 16
        confirmLabel.fontColor = .white
        confirmLabel.horizontalAlignmentMode = .center
        confirmLabel.verticalAlignmentMode = .center
        confirmLabel.position = CGPoint(x: 0, y: -panelSize.height / 2 + 35)
        confirmLabel.zPosition = 1002
        addChild(confirmLabel)

        let skipLabel = SKLabelNode(fontNamed: fontName)
        skipLabel.text = Strings.Leaderboard.skipButton
        skipLabel.fontSize = 13
        skipLabel.fontColor = SKColor(white: 0.5, alpha: 1)
        skipLabel.horizontalAlignmentMode = .center
        skipLabel.verticalAlignmentMode = .center
        skipLabel.position = CGPoint(x: 0, y: -panelSize.height / 2 + 64)
        skipLabel.zPosition = 1002
        addChild(skipLabel)
    }

    // MARK: - Input

    // Returns true when the dialog consumed the keystroke so GameScene
    // knows not to forward it to gameplay handlers.
    @discardableResult
    func handleKey(_ key: Int, shift: Bool) -> Bool {
        switch key {
        case 58: handleConfirm(); return true            // Return / Enter
        case 36: handleSkip();    return true            // Escape
        case 59:                                          // Backspace
            if !typed.isEmpty { typed.removeLast(); refreshInput() }
            return true
        case 57:                                          // Space
            if !typed.isEmpty && typed.count < maxLength {
                typed.append(" ")
                refreshInput()
            }
            return true
        case 0...25:                                      // A..Z
            guard typed.count < maxLength else { return true }
            let scalar = UnicodeScalar(UInt8(65 + key))   // always uppercase
            typed.append(Character(scalar))
            refreshInput()
            return true
        case 26...35:                                     // 0..9
            guard typed.count < maxLength else { return true }
            let scalar = UnicodeScalar(UInt8(48 + (key - 26)))
            typed.append(Character(scalar))
            refreshInput()
            return true
        default:
            return true                                    // swallow other keys
        }
    }

    private func handleConfirm() {
        let trimmed = typed.drop(while: { $0 == " " })
        var name = String(trimmed)
        while name.last == " " { name.removeLast() }
        guard !name.isEmpty else { return }
        LocalHighScores.savedUsername = name
        onConfirm(name)
    }

    private func handleSkip() {
        onSkip()
    }

    private func refreshInput() {
        inputLabel.text = typed
        // frame.width is the measured glyph-run width on both ports (real
        // SKLabelNode on macOS; the kit's measured frame on wasm), so the caret
        // sits flush after the last character.
        let w = inputLabel.frame.width
        caretLabel.position = CGPoint(x: inputLabel.position.x + w + 2,
                                      y: inputLabel.position.y)
    }

    // bossman-apple wires Save/Skip to NSButton click handlers; on wasm we
    // hit-test the button rects ourselves on a scene mouseDown. Returns
    // true when the click landed on a button (consumed); false otherwise.
    @discardableResult
    func handleMouseDown(at scenePoint: CGPoint) -> Bool {
        let local = convert(scenePoint, from: scene!)
        // Save button rect (in panel-local coords): same geometry the
        // buildUI lays down for the blue rounded button.
        let saveRect = CGRect(x: -100, y: -panelSize.height / 2 + 18,
                              width: 200, height: 34)
        if saveRect.contains(local) {
            handleConfirm()
            return true
        }
        // Skip label area — a generous 200x24 strip around the text so
        // any click on or near "Skip (Esc)" counts.
        let skipRect = CGRect(x: -100, y: -panelSize.height / 2 + 52,
                              width: 200, height: 24)
        if skipRect.contains(local) {
            handleSkip()
            return true
        }
        return false
    }
}
