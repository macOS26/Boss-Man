import AppKit
import GameKit
import SpriteKit

/// Game Center top-scores panel for the title screen. Renders ten
/// entries from the global leaderboard, falling back to a status
/// message when the player isn't signed in or the leaderboard hasn't
/// been set up in App Store Connect yet.
@MainActor
final class LeaderboardPanel: SKNode {
    /// Must match the leaderboard ID created in App Store Connect.
    static let leaderboardID = "boss_man.high_score"

    /// Node name used for click hit-testing on the sign-in link.
    static let signInLinkNodeName = "leaderboard.signin_link"

    private let panelSize: CGSize
    private let titleFontName: String
    private let bodyFontName: String
    private let entriesNode = SKNode()

    init(size: CGSize, titleFont: String, bodyFont: String) {
        self.panelSize = size
        self.titleFontName = titleFont
        self.bodyFontName = bodyFont
        super.init()
        buildShell()
        showStatus("Loading…")
        load()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func buildShell() {
        let rect = CGRect(
            x: -panelSize.width / 2,
            y: -panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )
        let bg = SKShapeNode(rect: rect, cornerRadius: 14)
        bg.fillColor = NSColor(calibratedWhite: 0, alpha: 0.16)
        bg.strokeColor = NSColor(calibratedWhite: 0, alpha: 0.55)
        bg.lineWidth = 2
        addChild(bg)

        let title = SKLabelNode(fontNamed: titleFontName)
        title.text = "LEADERBOARD"
        title.fontSize = 22
        title.fontColor = .black
        title.horizontalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: panelSize.height / 2 - 34)
        addChild(title)

        let underline = SKShapeNode(rect: CGRect(
            x: -panelSize.width / 2 + 18,
            y: panelSize.height / 2 - 48,
            width: panelSize.width - 36,
            height: 1.5
        ))
        underline.fillColor = NSColor(calibratedWhite: 0, alpha: 0.45)
        underline.strokeColor = .clear
        addChild(underline)

        entriesNode.position = CGPoint(x: 0, y: panelSize.height / 2 - 76)
        addChild(entriesNode)
    }

    private func showStatus(_ text: String, asLink: Bool = false) {
        entriesNode.removeAllChildren()
        let label = SKLabelNode(fontNamed: bodyFontName)
        label.text = text
        label.fontSize = 18
        label.fontColor = asLink
            ? NSColor(calibratedRed: 0.0, green: 0.30, blue: 0.85, alpha: 1)
            : NSColor(calibratedWhite: 0, alpha: 0.7)
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: -panelSize.height / 4)
        if asLink {
            label.name = Self.signInLinkNodeName
            // Faux underline so it reads as an actionable link.
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
            // Expand the hit target so the click is forgiving.
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
        // Render local scores first so the panel always has content.
        renderLocalFallback()

        Task { @MainActor in
            guard GKLocalPlayer.local.isAuthenticated else {
                if LocalHighScores.load().isEmpty {
                    showStatus("Sign in to Game Center", asLink: true)
                }
                return
            }
            do {
                let leaderboards = try await GKLeaderboard.loadLeaderboards(IDs: [Self.leaderboardID])
                guard let board = leaderboards.first else { return }
                let (_, entries, _) = try await board.loadEntries(
                    for: .global,
                    timeScope: .allTime,
                    range: NSRange(location: 1, length: 10)
                )
                if !entries.isEmpty {
                    render(entries: entries)
                }
            } catch {
                // Keep local fallback on screen; nothing to do.
            }
        }
    }

    private func renderLocalFallback() {
        let locals = LocalHighScores.load()
        guard !locals.isEmpty else { return }
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
                highlight: false
            ))
        }
    }

    private func render(entries: [GKLeaderboard.Entry]) {
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
                highlight: entry.player == GKLocalPlayer.local
            ))
        }
    }

    private func row(rank: Int, name: String, score: Int, y: CGFloat, left: CGFloat, right: CGFloat, highlight: Bool) -> SKNode {
        let row = SKNode()
        let color: NSColor = highlight
            ? NSColor(calibratedRed: 0.55, green: 0.05, blue: 0.05, alpha: 1)
            : .black

        let rankLabel = SKLabelNode(fontNamed: bodyFontName)
        rankLabel.text = "\(rank)."
        rankLabel.fontSize = 18
        rankLabel.fontColor = color
        rankLabel.horizontalAlignmentMode = .left
        rankLabel.position = CGPoint(x: left, y: y)
        row.addChild(rankLabel)

        let nameLabel = SKLabelNode(fontNamed: bodyFontName)
        nameLabel.text = name
        nameLabel.fontSize = 18
        nameLabel.fontColor = color
        nameLabel.horizontalAlignmentMode = .left
        nameLabel.position = CGPoint(x: left + 36, y: y)
        row.addChild(nameLabel)

        let scoreLabel = SKLabelNode(fontNamed: bodyFontName)
        scoreLabel.text = "\(score)"
        scoreLabel.fontSize = 18
        scoreLabel.fontColor = color
        scoreLabel.horizontalAlignmentMode = .right
        scoreLabel.position = CGPoint(x: right, y: y)
        row.addChild(scoreLabel)

        return row
    }
}
