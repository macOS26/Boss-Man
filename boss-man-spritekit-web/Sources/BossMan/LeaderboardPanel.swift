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
        showStatus("NO SCORES YET")
    }

    private func buildShell() {
        let rect = CGRect(
            x: -panelSize.width / 2,
            y: -panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )

        // Post-it body with a real Canvas2D shadowBlur drop shadow. The
        // earlier SKEffectNode + ctx.filter approach gave hard edges because
        // fillRect honoring of ctx.filter is inconsistent across browsers.
        // SKShapeNode.shadowBlur routes through ctx.shadowBlur, which is the
        // standard Canvas2D drop-shadow primitive and produces a real
        // Gaussian halo for every subsequent fill.
        let postIt = SKShapeNode(rect: rect)
        postIt.fillColor = SKColor(red: 1.0, green: 0.92, blue: 0.42, alpha: 1)
        postIt.strokeColor = .clear
        postIt.shadowBlur = 56
        postIt.shadowOffset = CGVector(dx: 12, dy: -14)
        postIt.shadowColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.36)
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
