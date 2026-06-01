import AppKit
import GameKit
import SpriteKit

@MainActor
final class LeaderboardPanel: SKNode {
    static let leaderboardID = Strings.GameCenter.leaderboardID

    static let signInLinkNodeName = Strings.NodeName.signInLink

    private let panelSize: CGSize
    private let titleFontName: String
    private let bodyFontName: String
    private let entriesNode = SKNode()
    private let titleLabel = SKLabelNode()

    init(size: CGSize, titleFont: String, bodyFont: String) {
        self.panelSize = size
        self.titleFontName = titleFont
        self.bodyFontName = bodyFont
        super.init()
        buildShell()
        load()
#if canImport(ObjectiveC)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(authStateChanged),
            name: .GKPlayerAuthenticationDidChangeNotificationName,
            object: nil
        )
#endif
    }

    deinit {
#if canImport(ObjectiveC)
        NotificationCenter.default.removeObserver(self)
#endif
    }

#if canImport(ObjectiveC)
    @objc private func authStateChanged() {
        refreshFromGameCenter()
    }
#endif

    required init?(coder: NSCoder) {
        fatalError(Strings.System.initCoderUnsupported)
    }

    private func buildShell() {
        let rect = CGRect(
            x: -panelSize.width / 2,
            y: -panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )

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
        postIt.fillColor = NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.42, alpha: 1)
        postIt.strokeColor = .clear
        addChild(postIt)

        let adhesiveHeight: CGFloat = 32
        let adhesiveToTitleGap: CGFloat = 10
        let adhesive = SKShapeNode(rect: CGRect(
            x: rect.minX,
            y: rect.maxY - adhesiveHeight,
            width: rect.width,
            height: adhesiveHeight
        ))
        adhesive.fillColor = NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.34, alpha: 0.45)
        adhesive.strokeColor = .clear
        addChild(adhesive)

        let titleBaselineY = panelSize.height / 2 - adhesiveHeight - adhesiveToTitleGap - 18

        titleLabel.fontName = Strings.Font.markerFeltWide
        titleLabel.text = Strings.Leaderboard.header
        titleLabel.fontSize = 24
        titleLabel.fontColor = NSColor(calibratedRed: 0.18, green: 0.10, blue: 0.04, alpha: 1)
        titleLabel.horizontalAlignmentMode = .center
        titleLabel.position = CGPoint(x: 0, y: titleBaselineY)
        addChild(titleLabel)

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
        underline.fillColor = NSColor(calibratedWhite: 0, alpha: 0.40)
        underline.strokeColor = .clear
        addChild(underline)

        entriesNode.position = CGPoint(x: 0, y: titleBaselineY - 42)
        addChild(entriesNode)
    }

    private func showStatus(_ text: String, asLink: Bool = false) {
        entriesNode.removeAllChildren()
        let label = SKLabelNode(fontNamed: titleFontName)
        label.text = text
        label.fontSize = 18
        label.fontColor = asLink
            ? NSColor(calibratedRed: 0.0, green: 0.30, blue: 0.85, alpha: 1)
            : NSColor(calibratedWhite: 0, alpha: 0.7)
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: -panelSize.height / 4)
        if asLink {
            label.name = Self.signInLinkNodeName
            let underline = SKShapeNode(rect: CGRect(
                x: -label.frame.width / 2 - 4,
                y: label.position.y - 6,
                width: label.frame.width + 8,
                height: 1.5
            ))
            underline.fillColor = label.fontColor ?? .blue
            underline.strokeColor = .clear
            underline.name = Self.signInLinkNodeName
            entriesNode.addChild(underline)
            let hit = SKShapeNode(rect: CGRect(
                x: -panelSize.width / 2 + 18,
                y: label.position.y - 18,
                width: panelSize.width - 36,
                height: 38
            ))
            hit.fillColor = .clear
            hit.strokeColor = .clear
            hit.name = Self.signInLinkNodeName
            entriesNode.addChild(hit)
        }
        entriesNode.addChild(label)
    }

    private func load() {
        #if os(macOS)
        showStatus(Strings.App.loading)
        refreshFromGameCenter()
        #else
        renderLocalFallback()
        #endif
    }

    #if os(macOS)
    private func refreshFromGameCenter() {
        if GKLocalPlayer.local.isAuthenticated {
            showStatus(Strings.App.loading)
            fetchEntries()
        } else if GameCenterClient.authenticationResolved {
            renderLocalFallback()
        } else {
            showStatus(Strings.App.loading)
        }
    }
    #endif

    private func fetchEntries() {
        Task { @MainActor in
            do {
                let leaderboards = try await GKLeaderboard.loadLeaderboards(IDs: [Self.leaderboardID])
                guard let board = leaderboards.first else {
                    renderLocalFallback()
                    return
                }
                let (_, entries, _) = try await board.loadEntries(
                    for: .global,
                    timeScope: .allTime,
                    range: NSRange(location: 1, length: 10)
                )
                if entries.isEmpty {
                    renderLocalFallback()
                } else {
                    render(entries: entries)
                }
            } catch {
                renderLocalFallback()
            }
        }
    }

    private func renderLocalFallback() {
        let locals = LocalHighScores.load()
        guard !locals.isEmpty else {
            showStatus(Strings.Leaderboard.noScores)
            return
        }
        titleLabel.fontColor = .systemRed
        entriesNode.removeAllChildren()
        let rowHeight: CGFloat = 28
        let leftEdge = -panelSize.width / 2 + 18
        let rightEdge = panelSize.width / 2 - 18
        for (index, entry) in locals.enumerated() {
            let y = -CGFloat(index) * rowHeight
            entriesNode.addChild(row(
                rank: index + 1,
                name: entry.name,
                score: entry.score,
                y: y,
                left: leftEdge,
                right: rightEdge,
                color: .black
            ))
        }
    }

    private func render(entries: [GKLeaderboard.Entry]) {
        titleLabel.fontColor = .black
        entriesNode.removeAllChildren()
        let rowHeight: CGFloat = 28
        let leftEdge = -panelSize.width / 2 + 18
        let rightEdge = panelSize.width / 2 - 18
        for (index, entry) in entries.enumerated() {
            let y = -CGFloat(index) * rowHeight
            entriesNode.addChild(row(
                rank: entry.rank,
                name: entry.player.displayName,
                score: entry.score,
                y: y,
                left: leftEdge,
                right: rightEdge,
                color: .black
            ))
        }
    }

    private func row(rank: Int, name: String, score: Int, y: CGFloat, left: CGFloat, right: CGFloat, color: NSColor) -> SKNode {
        let row = SKNode()

        let rankColumnRight = left + 22
        let rankLabel = SKLabelNode(fontNamed: titleFontName)
        rankLabel.text = Strings.Leaderboard.rankLabel(rank)
        rankLabel.fontSize = 18
        rankLabel.fontColor = color
        rankLabel.horizontalAlignmentMode = .right
        rankLabel.position = CGPoint(x: rankColumnRight, y: y)
        row.addChild(rankLabel)

        let nameLabel = SKLabelNode(fontNamed: titleFontName)
        nameLabel.text = name
        nameLabel.fontSize = 18
        nameLabel.fontColor = color
        nameLabel.horizontalAlignmentMode = .left
        nameLabel.position = CGPoint(x: rankColumnRight + 4, y: y)
        row.addChild(nameLabel)

        let scoreLabel = SKLabelNode(fontNamed: titleFontName)
        scoreLabel.text = Strings.Leaderboard.scoreLabel(score)
        scoreLabel.fontSize = 18
        scoreLabel.fontColor = color
        scoreLabel.horizontalAlignmentMode = .right
        scoreLabel.position = CGPoint(x: right, y: y)
        row.addChild(scoreLabel)

        return row
    }
}
