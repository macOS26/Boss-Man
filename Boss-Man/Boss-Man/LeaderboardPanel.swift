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
    static let leaderboardID = "BossManLeaderBoard0001"

    /// Node name used for click hit-testing on the sign-in link.
    static let signInLinkNodeName = "leaderboard.signin_link"

    private let panelSize: CGSize
    private let titleFontName: String
    private let bodyFontName: String
    private let entriesNode = SKNode()
    private let titleLabel = SKLabelNode()
    private var notAuthRetries = 0
    private let maxNotAuthRetries = 3

    init(size: CGSize, titleFont: String, bodyFont: String) {
        self.panelSize = size
        self.titleFontName = titleFont
        self.bodyFontName = bodyFont
        super.init()
        buildShell()
        showStatus("Loading…")
        load()
        // Auth is async — if the auth handler fires after we've already
        // tried (and failed) the first fetch, reload then.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(authStateChanged),
            name: .GKPlayerAuthenticationDidChangeNotificationName,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func authStateChanged() {
        print("[GC] auth state changed: isAuthenticated=\(GKLocalPlayer.local.isAuthenticated)")
        if GKLocalPlayer.local.isAuthenticated {
            fetchEntries()
        }
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

        // Drop shadow: slightly larger, offset down-right, dark and soft.
        let shadow = SKShapeNode(rect: rect.offsetBy(dx: 6, dy: -8).insetBy(dx: -2, dy: -2))
        shadow.fillColor = NSColor(calibratedWhite: 0, alpha: 0.14)
        shadow.strokeColor = .clear
        shadow.zPosition = -1
        let blur = SKEffectNode()
        blur.shouldEnableEffects = true
        blur.filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 6])
        blur.addChild(shadow)
        addChild(blur)

        // The Post-it itself: classic 3M canary yellow with a faint
        // square corner (Post-its have very tight radii, not rounded
        // pills) and no stroke.
        let postIt = SKShapeNode(rect: rect)
        postIt.fillColor = NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.42, alpha: 1)
        postIt.strokeColor = .clear
        addChild(postIt)

        // Adhesive band along the top edge: a little more saturated
        // than the body so it reads as the sticky strip on a real
        // Post-it. 10pt of breathing room sits between the strip and
        // the LEADERBOARD title.
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

        titleLabel.fontName = titleFontName
        titleLabel.text = "LEADERBOARD"
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

    /// Entry point. If the player is already authenticated, fetch
    /// immediately. Otherwise do nothing — the auth-state notification
    /// observer set up in init() will fire whenever GameKit finishes
    /// authenticating and call fetchEntries() exactly once. No timers,
    /// no polling.
    private func load() {
        showStatus("Loading…")
        if GKLocalPlayer.local.isAuthenticated {
            fetchEntries()
        }
    }

    private func fetchEntries() {
        Task { @MainActor in
            print("[GC] \(GKLocalPlayer.local.displayName) authenticated; fetching '\(Self.leaderboardID)'")
            do {
                let leaderboards = try await GKLeaderboard.loadLeaderboards(IDs: [Self.leaderboardID])
                guard let board = leaderboards.first else {
                    print("[GC] leaderboard not found — falling back to local")
                    renderLocalFallback()
                    return
                }
                let (_, entries, _) = try await board.loadEntries(
                    for: .global,
                    timeScope: .allTime,
                    range: NSRange(location: 1, length: 10)
                )
                if entries.isEmpty {
                    print("[GC] leaderboard empty — falling back to local")
                    renderLocalFallback()
                } else {
                    print("[GC] showing \(entries.count) Game Center entries")
                    render(entries: entries)
                }
            } catch {
                print("[GC] fetch failed (\(error.localizedDescription)) — falling back to local")
                renderLocalFallback()
            }
        }
    }

    private func renderLocalFallback() {
        let locals = LocalHighScores.load()
        guard !locals.isEmpty else { return }
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
                color: .systemBlue
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

        let rankLabel = SKLabelNode(fontNamed: titleFontName)
        rankLabel.text = "\(rank)."
        rankLabel.fontSize = 18
        rankLabel.fontColor = color
        rankLabel.horizontalAlignmentMode = .left
        rankLabel.position = CGPoint(x: left, y: y)
        row.addChild(rankLabel)

        let nameLabel = SKLabelNode(fontNamed: titleFontName)
        nameLabel.text = name
        nameLabel.fontSize = 18
        nameLabel.fontColor = color
        nameLabel.horizontalAlignmentMode = .left
        nameLabel.position = CGPoint(x: left + 36, y: y)
        row.addChild(nameLabel)

        let scoreLabel = SKLabelNode(fontNamed: titleFontName)
        scoreLabel.text = "\(score)"
        scoreLabel.fontSize = 18
        scoreLabel.fontColor = color
        scoreLabel.horizontalAlignmentMode = .right
        scoreLabel.position = CGPoint(x: right, y: y)
        row.addChild(scoreLabel)

        return row
    }
}
