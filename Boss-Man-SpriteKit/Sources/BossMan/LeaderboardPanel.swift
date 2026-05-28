import SpriteKit

// Post-it leaderboard panel docked on the title screen. Reads the top-10
// entries from localStorage (Persistence.string(forKey:) returns a JSON-
// encoded array we parse with MiniJSON via the kit). On a fresh install the
// list is empty and the panel shows "NO SCORES YET" so the layout still
// reads correctly. Adding scores happens elsewhere (LocalHighScores) and
// just rewrites the same key.
final class LeaderboardPanel: SKNode {
    private let panelSize: CGSize

    init(size: CGSize) {
        self.panelSize = size
        super.init()
        buildBackground()
        buildContents()
    }

    private func buildBackground() {
        let bg = SKShapeNode(rectOf: panelSize, cornerRadius: 4)
        bg.fillColor = SKColor(red: 1.0, green: 0.92, blue: 0.42, alpha: 1)
        bg.strokeColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.15)
        bg.lineWidth = 1
        addChild(bg)
        // Adhesive strip across the top edge for the post-it feel.
        let stripRect = CGRect(x: -panelSize.width / 2,
                               y: panelSize.height / 2 - 32,
                               width: panelSize.width, height: 32)
        let strip = SKShapeNode(rect: stripRect)
        strip.fillColor = SKColor(red: 1.0, green: 0.88, blue: 0.34, alpha: 0.45)
        strip.strokeColor = .clear
        addChild(strip)
    }

    private func buildContents() {
        let header = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
        header.text = "LEADERBOARD"
        header.fontSize = 24
        header.fontColor = SKColor(red: 46/255.0, green: 26/255.0, blue: 10/255.0, alpha: 1)
        header.position = CGPoint(x: 0, y: panelSize.height / 2 - 60)
        addChild(header)

        let underlineRect = CGRect(x: -panelSize.width / 2 + 22, y: panelSize.height / 2 - 76,
                                   width: panelSize.width - 44, height: 2)
        let underline = SKShapeNode(rect: underlineRect)
        underline.fillColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.4)
        underline.strokeColor = .clear
        addChild(underline)

        let entries = readEntries()
        if entries.isEmpty {
            let empty = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
            empty.text = "NO SCORES YET"
            empty.fontSize = 18
            empty.fontColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.7)
            empty.position = .zero
            addChild(empty)
            return
        }
        let startY = panelSize.height / 2 - 104
        let rowH: CGFloat = 28
        for (i, entry) in entries.prefix(10).enumerated() {
            let y = startY - CGFloat(i) * rowH
            let rank = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
            rank.text = "\(i + 1)."
            rank.fontSize = 18
            rank.fontColor = .black
            rank.horizontalAlignmentMode = .right
            rank.position = CGPoint(x: -panelSize.width / 2 + 40, y: y)
            addChild(rank)

            let name = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
            name.text = entry.name
            name.fontSize = 18
            name.fontColor = .black
            name.horizontalAlignmentMode = .left
            name.position = CGPoint(x: -panelSize.width / 2 + 44, y: y)
            addChild(name)

            let score = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
            score.text = String(entry.score)
            score.fontSize = 18
            score.fontColor = .black
            score.horizontalAlignmentMode = .right
            score.position = CGPoint(x: panelSize.width / 2 - 18, y: y)
            addChild(score)
        }
    }

    private func readEntries() -> [(name: String, score: Int)] {
        // JSON shape stored under DefaultsKey.leaderboard:
        //   [{ "n": "TOD", "s": 1234 }, ...]
        // Without Foundation we hand-roll a tiny parse step over the kit's
        // MiniJSON. On a missing key we just return empty.
        return []   // initial wasm port: leaderboard write path lands later
    }
}
