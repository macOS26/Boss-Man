import AppKit
import SpriteKit

// Full-screen GAME OVER combo, shared by both ports (wasm is master for the
// leaderboard / name-entry flow). Replaces the small game-over card + the
// separate UsernameDialog with one mobile-friendly screen:
//   - GAME OVER + final/high score
//   - the local leaderboard (top 10)
//   - when the score qualifies: a name field + an on-screen A-Z/0-9 keyboard so a
//     name can be entered with taps (mobile) or the physical keyboard (desktop)
//   - big [PLAY] (restart) and [ESC] (title) buttons
// Laid out in scene coordinates (the node sits at the origin), so the stored hit
// rects compare directly against tap points. Input is routed here by GameScene
// while the screen is shown.
@MainActor
final class GameOverScreen: SKNode {

    static let nodeName = "gameOverScreen"

    private let screen: CGSize
    private let font: String
    private let qualified: Bool
    private let onPlay: () -> Void
    private let onEsc: () -> Void

    private var typed: String = ""
    private let maxLength = 16
    private var committed = false

    private let nameLabel = SKLabelNode()
    private let caretLabel = SKLabelNode()
    private var keyRects: [(rect: CGRect, ch: Character)] = []
    private var backspaceRect = CGRect.zero
    private var spaceRect = CGRect.zero
    private var playRect = CGRect.zero
    private var escRect = CGRect.zero
    private let finalScore: Int

    init(size: CGSize, font: String, score: Int, highScore: Int,
         defaultName: String, allowEntry: Bool,
         onPlay: @escaping () -> Void, onEsc: @escaping () -> Void) {
        self.screen = size
        self.font = font
        self.finalScore = score
        self.qualified = allowEntry && LocalHighScores.qualifiesForBoard(score: score)
        self.onPlay = onPlay
        self.onEsc = onEsc
        super.init()
        self.name = Self.nodeName
        self.zPosition = 5000
        self.typed = defaultName
        build(score: score, highScore: highScore)
        refreshName()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    private func label(_ text: String, _ size: CGFloat, _ color: SKColor, x: CGFloat, y: CGFloat,
                       align: SKLabelHorizontalAlignmentMode = .center, bold: Bool = true) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: bold ? Strings.Font.markerFeltWide : font)
        l.text = text
        l.fontSize = size
        l.fontColor = color
        l.horizontalAlignmentMode = align
        l.verticalAlignmentMode = .center
        l.position = CGPoint(x: x, y: y)
        l.zPosition = zPosition + 2
        addChild(l)
        return l
    }

    private func box(_ rect: CGRect, fill: SKColor, stroke: SKColor = .clear, line: CGFloat = 0, radius: CGFloat = 8) {
        let s = SKShapeNode(rect: rect, cornerRadius: radius)
        s.fillColor = fill
        s.strokeColor = stroke
        s.lineWidth = line
        s.zPosition = zPosition + 1
        addChild(s)
    }

    private func build(score: Int, highScore: Int) {
        let W = screen.width, H = screen.height
        // Dim full-screen backdrop + near-full panel.
        box(CGRect(x: 0, y: 0, width: W, height: H), fill: SKColor(white: 0, alpha: 0.78), radius: 0)
        let m = min(W, H) * 0.03
        box(CGRect(x: m, y: m, width: W - 2 * m, height: H - 2 * m),
            fill: SKColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 0.98),
            stroke: SKColor(red: 1, green: 0.55, blue: 0.0, alpha: 0.9), line: 3, radius: 16)

        _ = label("GAME OVER", H * (qualified ? 0.075 : 0.085), SKColor(red: 0.95, green: 0.20, blue: 0.18, alpha: 1),
                  x: W / 2, y: H * (qualified ? 0.93 : 0.91))
        _ = label("FINAL \(score)    HIGH \(highScore)", H * (qualified ? 0.030 : 0.034), .white,
                  x: W / 2, y: H * (qualified ? 0.875 : 0.845))

        // The leaderboard is the least important element: it is shown only when
        // there is no name entry, and is otherwise yielded to the keyboard.
        if qualified {
            buildNameEntry()
        } else {
            _ = label(Strings.Leaderboard.header, H * 0.038, SKColor(red: 1, green: 0.92, blue: 0.42, alpha: 1), x: W / 2, y: H * 0.79)
            let entries = LocalHighScores.load()
            let rowH = H * 0.035, topY = H * 0.745
            let leftX = W * 0.30, rightX = W * 0.70
            if entries.isEmpty {
                _ = label(Strings.Leaderboard.noScores, H * 0.030, SKColor(white: 0.7, alpha: 1), x: W / 2, y: topY)
            } else {
                for (i, e) in entries.prefix(10).enumerated() {
                    let y = topY - CGFloat(i) * rowH
                    _ = label("\(i + 1). \(e.name)", H * 0.030, .white, x: leftX, y: y, align: .left, bold: false)
                    _ = label("\(e.score)", H * 0.030, .white, x: rightX, y: y, align: .right, bold: false)
                }
            }
        }
        buildButtons()
    }

    private func buildNameEntry() {
        let W = screen.width, H = screen.height
        _ = label(Strings.Leaderboard.newHighScoreTitle + "  " + Strings.Leaderboard.enterUsernamePrompt,
                  H * 0.030, SKColor(red: 0.3, green: 0.85, blue: 1, alpha: 1), x: W / 2, y: H * 0.80)

        let fieldW = W * 0.6, fieldH = H * 0.065, fieldY = H * 0.73
        box(CGRect(x: (W - fieldW) / 2, y: fieldY - fieldH / 2, width: fieldW, height: fieldH),
            fill: SKColor(white: 0.96, alpha: 1), stroke: SKColor(white: 0.6, alpha: 1), line: 1, radius: 6)
        nameLabel.fontName = font
        nameLabel.fontSize = H * 0.036
        nameLabel.fontColor = SKColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1)
        nameLabel.horizontalAlignmentMode = .left
        nameLabel.verticalAlignmentMode = .center
        nameLabel.position = CGPoint(x: (W - fieldW) / 2 + 14, y: fieldY)
        nameLabel.zPosition = zPosition + 3
        addChild(nameLabel)
        caretLabel.text = "|"
        caretLabel.fontName = font
        caretLabel.fontSize = H * 0.036
        caretLabel.fontColor = nameLabel.fontColor
        caretLabel.horizontalAlignmentMode = .left
        caretLabel.verticalAlignmentMode = .center
        caretLabel.zPosition = zPosition + 3
        caretLabel.run(.repeatForever(.sequence([.fadeAlpha(to: 0, duration: 0.45), .fadeAlpha(to: 1, duration: 0.45)])))
        addChild(caretLabel)

        // On-screen keyboard.
        let rows = ["1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
        let keyW = min(W * 0.072, (W * 0.86) / 10)
        let gap = keyW * 0.14
        let keyH = keyW * 0.62
        var y = H * 0.63
        for row in rows {
            let chars = Array(row)
            let rowW = CGFloat(chars.count) * keyW + CGFloat(chars.count - 1) * gap
            var x = (W - rowW) / 2
            for ch in chars {
                let r = CGRect(x: x, y: y - keyH / 2, width: keyW, height: keyH)
                box(r, fill: SKColor(white: 0.22, alpha: 1), stroke: SKColor(white: 0.45, alpha: 1), line: 1, radius: 6)
                _ = label(String(ch), keyH * 0.5, .white, x: x + keyW / 2, y: y, bold: false)
                keyRects.append((r, ch))
                x += keyW + gap
            }
            y -= keyH + gap
        }
        // Bottom row: backspace + space.
        let bsW = keyW * 2, spW = keyW * 6
        let rowW = bsW + gap + spW
        var x = (W - rowW) / 2
        backspaceRect = CGRect(x: x, y: y - keyH / 2, width: bsW, height: keyH)
        box(backspaceRect, fill: SKColor(white: 0.30, alpha: 1), stroke: SKColor(white: 0.45, alpha: 1), line: 1, radius: 6)
        _ = label("DEL", keyH * 0.42, .white, x: x + bsW / 2, y: y, bold: false)
        x += bsW + gap
        spaceRect = CGRect(x: x, y: y - keyH / 2, width: spW, height: keyH)
        box(spaceRect, fill: SKColor(white: 0.22, alpha: 1), stroke: SKColor(white: 0.45, alpha: 1), line: 1, radius: 6)
        _ = label("SPACE", keyH * 0.42, .white, x: x + spW / 2, y: y, bold: false)
    }

    private func buildButtons() {
        let W = screen.width, H = screen.height
        // Taller buttons, lifted off the panel edge. When there is no name entry
        // they ride up into the open space below the leaderboard; with the
        // keyboard present they sit just inside the bottom border, below it.
        let bw = W * 0.30
        let bh = H * (qualified ? 0.095 : 0.13)
        let by = H * (qualified ? 0.085 : 0.25)
        playRect = CGRect(x: W * 0.16, y: by - bh / 2, width: bw, height: bh)
        box(playRect, fill: SKColor(red: 0.12, green: 0.5, blue: 0.18, alpha: 1), radius: 14)
        _ = label("PLAY", bh * 0.42, .white, x: playRect.midX, y: by)
        escRect = CGRect(x: W * 0.54, y: by - bh / 2, width: bw, height: bh)
        box(escRect, fill: SKColor(red: 0.5, green: 0.18, blue: 0.18, alpha: 1), radius: 14)
        _ = label("ESC", bh * 0.42, .white, x: escRect.midX, y: by)
    }

    private func refreshName() {
        guard qualified else { return }
        nameLabel.text = typed
        caretLabel.position = CGPoint(x: nameLabel.position.x + nameLabel.frame.width + 2, y: nameLabel.position.y)
    }

    private func commitName() {
        guard qualified, !committed else { return }
        var name = typed
        while name.first == " " { name.removeFirst() }
        while name.last == " " { name.removeLast() }
        guard !name.isEmpty else { return }
        committed = true
        LocalHighScores.savedUsername = name
        LocalHighScores.record(name: name, score: finalScore)
    }

    private func append(_ ch: Character) {
        guard qualified, typed.count < maxLength else { return }
        if ch == " " && typed.isEmpty { return }
        typed.append(ch)
        refreshName()
    }

    // MARK: - Input (routed by GameScene while shown)
    func handleTap(at p: CGPoint) {
        if playRect.contains(p) { commitName(); onPlay(); return }
        if escRect.contains(p)  { commitName(); onEsc();  return }
        guard qualified else { return }
        if backspaceRect.contains(p) { if !typed.isEmpty { typed.removeLast(); refreshName() }; return }
        if spaceRect.contains(p)     { append(" "); return }
        for k in keyRects where k.rect.contains(p) { append(k.ch); return }
    }

    // Unified key scheme (UsernameDialog's): A-Z 0..25, 0-9 26..35, Space 57,
    // Backspace 59, Enter 58, Esc 36, P 15. macOS maps NSEvent codes to this first.
    func handleKey(_ key: Int, shift: Bool) {
        if !qualified {
            if key == 15 || key == 58 { onPlay() } else if key == 36 { onEsc() }
            return
        }
        switch key {
        case 58: commitName(); onPlay()
        case 36: commitName(); onEsc()
        case 59: if !typed.isEmpty { typed.removeLast(); refreshName() }
        case 57: append(" ")
        case 0...25: append(Character(UnicodeScalar(UInt8(65 + key))))
        case 26...35: append(Character(UnicodeScalar(UInt8(48 + (key - 26)))))
        default: break
        }
    }
}
