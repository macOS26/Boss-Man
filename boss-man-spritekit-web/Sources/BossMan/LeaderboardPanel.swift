import SpriteKit

// Post-it leaderboard panel docked on the title screen.
//
// Visual stack (bottom to top in z-order, matching the macOS original):
//   1. Drop shadow — a dark rectangle offset down-right behind the post-it,
//      blurred with the kit's SKEffectNode + ctx.filter (`blur(6px)`) for the
//      soft-edge look the macOS build gets from a CIFilter Gaussian blur.
//   2. Post-it body — solid pale-yellow rect.
//   3. Adhesive strip — slightly darker yellow band across the top 32px.
//   4. LEADERBOARD title label.
//   5. Underline below the title.
//   6. Entries node: rows of `rank · name · score`, or a "NO SCORES YET"
//      placeholder at y = -panelSize.height / 4 when the local-high-scores
//      list is empty.
//
// First wasm pass renders the empty state; populating from
// LocalHighScores lands once the score-write path is wired.
final class LeaderboardPanel: SKNode {
    private let panelSize: CGSize
    private let titleFontName = Strings.Font.markerFeltThin
    private let bodyFontName  = Strings.Font.menloBold
    private let entriesNode = SKNode()
    private let titleLabel = SKLabelNode()

    init(size: CGSize) {
        self.panelSize = size
        super.init()
        buildShell()
        let entries = LocalHighScores.load()
        if entries.isEmpty {
            showStatus("NO SCORES YET")
        } else {
            renderRows(entries)
        }
    }

    private func renderRows(_ entries: [LocalHighScores.Entry]) {
        entriesNode.removeAllChildren()
        let rowH: CGFloat = 28
        let leftEdge  = -panelSize.width / 2 + 18
        let rightEdge =  panelSize.width / 2 - 18
        for (i, entry) in entries.prefix(10).enumerated() {
            let y = -CGFloat(i) * rowH

            let rank = SKLabelNode(fontNamed: titleFontName)
            rank.text = "\(i + 1)."
            rank.fontSize = 18
            rank.fontColor = .black
            rank.horizontalAlignmentMode = .right
            rank.verticalAlignmentMode = .center
            rank.position = CGPoint(x: leftEdge + 22, y: y)
            entriesNode.addChild(rank)

            let name = SKLabelNode(fontNamed: titleFontName)
            name.text = entry.name
            name.fontSize = 18
            name.fontColor = .black
            name.horizontalAlignmentMode = .left
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: leftEdge + 28, y: y)
            entriesNode.addChild(name)

            let s = SKLabelNode(fontNamed: titleFontName)
            s.text = String(entry.score)
            s.fontSize = 18
            s.fontColor = .black
            s.horizontalAlignmentMode = .right
            s.verticalAlignmentMode = .center
            s.position = CGPoint(x: rightEdge, y: y)
            entriesNode.addChild(s)
        }
    }

    private func buildShell() {
        let rect = CGRect(
            x: -panelSize.width / 2,
            y: -panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )

        // Drop shadow via SKEffectNode + CIGaussianBlur — common with the apple
        // master; the kit routes the CIFilter to a soft Canvas2D shadowBlur.
        let shadow = SKShapeNode(rect: rect.offsetBy(dx: 1, dy: -3).insetBy(dx: -2, dy: -2))
        shadow.fillColor = SKColor(white: 0, alpha: 0.24)
        shadow.strokeColor = .clear
        shadow.zPosition = -1
        let blur = SKEffectNode()
        blur.shouldEnableEffects = true
        blur.filter = CIFilter(name: Strings.CoreImage.gaussianBlur,
                               parameters: [Strings.CoreImage.inputRadiusKey: 12.5])
        blur.addChild(shadow)
        addChild(blur)

        let postIt = SKShapeNode(rect: rect)
        postIt.fillColor = SKColor(red: 1.0, green: 0.92, blue: 0.42, alpha: 1)
        postIt.strokeColor = .clear
        addChild(postIt)

        // 3. Adhesive strip across the top.
        let adhesiveHeight: CGFloat = 32
        let adhesiveToTitleGap: CGFloat = 10
        let adhesive = SKShapeNode(rect: CGRect(
            x: rect.minX,
            y: rect.maxY - adhesiveHeight,
            width: rect.width,
            height: adhesiveHeight
        ))
        adhesive.fillColor = SKColor(red: 1.0, green: 0.88, blue: 0.34, alpha: 0.45)
        adhesive.strokeColor = .clear
        addChild(adhesive)

        let titleBaselineY = panelSize.height / 2 - adhesiveHeight - adhesiveToTitleGap - 18

        // 4. Title label.
        titleLabel.fontName = titleFontName
        titleLabel.text = "LEADERBOARD"
        titleLabel.fontSize = 24
        titleLabel.fontColor = SKColor(red: 0.18, green: 0.10, blue: 0.04, alpha: 1)
        titleLabel.horizontalAlignmentMode = .center
        titleLabel.position = CGPoint(x: 0, y: titleBaselineY)
        addChild(titleLabel)

        // 5. Underline below the title.
        let underlineHeight: CGFloat = 2
        let underline = SKShapeNode(
            rect: CGRect(
                x: -panelSize.width / 2 + 22,
                y: titleBaselineY - 14,
                width: panelSize.width - 44,
                height: underlineHeight
            ),
            cornerRadius: underlineHeight / 2
        )
        underline.fillColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.40)
        underline.strokeColor = .clear
        addChild(underline)

        // 6. Entries container — rows offset below the underline.
        entriesNode.position = CGPoint(x: 0, y: titleBaselineY - 42)
        addChild(entriesNode)
    }

    // Shows a single centered label inside entriesNode at the
    // y = -panelSize.height / 4 sweet spot the macOS original uses for
    // empty / loading captions.
    private func showStatus(_ text: String) {
        entriesNode.removeAllChildren()
        let label = SKLabelNode(fontNamed: titleFontName)
        label.text = text
        label.fontSize = 18
        label.fontColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.7)
        label.horizontalAlignmentMode = .center
        // entriesNode's origin is at titleBaselineY - 42 in panel-local coords.
        // The macOS original places empty/loading text at panel.y = -panelH/4
        // (in panel coords, where panel center = 0). Translating that into
        // entriesNode-local coords:
        //   panel y     = -panelSize.height / 4
        //   entriesNode origin in panel coords = titleBaselineY - 42
        //   so entriesNode-local y = -panelSize.height/4 - (titleBaselineY - 42)
        let entriesOrigin = (panelSize.height / 2 - 32 - 10 - 18) - 42
        label.position = CGPoint(x: 0, y: -panelSize.height / 4 - entriesOrigin)
        entriesNode.addChild(label)
    }
}
