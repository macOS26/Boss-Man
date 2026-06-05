import SpriteKit
import AppKit

// Title screen, shared by both ports: BOSS-MAN wordmark tilted slightly, red
// stapler illustration, green "(P)lay" + blue "(E)ditor" buttons, high score,
// the leaderboard panel docked left, and a bottom-right toggle column. Layout,
// builders, and input are all common across platforms.
final class TitleScene: SKScene {
    private var playButtonRect = CGRect.zero
    private var editorButtonRect = CGRect.zero
    private var bossTracksLabel: SKLabelNode?
    private var waterGunLabel: SKLabelNode?
    private var fullscreenLabel: SKLabelNode?
    private var escWindowLabel: SKLabelNode?
    private var mazeLabel: SKLabelNode?

    override func didMove(to view: SKView) {
        // The title is nearly static, so render it at 10 fps to keep CPU/GPU low.
        // Game/editor scenes restore 60 fps on the way out (startGame / startEditor).
        view.preferredFramesPerSecond = 10
        backgroundColor = SKColor(calibratedRed: 1.0, green: 0.93, blue: 0.34, alpha: 1)
        anchorPoint = .zero

        let title = SKLabelNode(fontNamed: Strings.Font.markerFeltWide)
        title.text = Strings.Title.gameTitle
        title.fontSize = 108 * SpriteFactory.worldRenderScale
        title.setScale(1 / SpriteFactory.worldRenderScale)
        title.fontColor = .black
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.74)
        title.zRotation = -0.04
        title.zPosition = 10
        addChild(title)

        let credit = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
        credit.text = "Game Design by Todd Bruss"
        credit.fontSize = 24 * SpriteFactory.worldRenderScale
        credit.setScale(1 / SpriteFactory.worldRenderScale)
        credit.fontColor = .black
        credit.position = CGPoint(x: size.width / 2, y: size.height * 0.95 - 15)
        credit.zPosition = 10
        addChild(credit)

        let stapler = makeStapler()
        stapler.position = CGPoint(x: size.width / 2, y: size.height * 0.46 + 8)
        stapler.zRotation = -0.06
        addChild(stapler)

        // Two title buttons: green "(P)lay" and blue "(E)ditor". Click/tap either
        // or press P / E.
        let promptY = size.height * 0.15 + 20
        let green = SKColor.systemGreen
        let blue  = SKColor.systemBlue
        let bw: CGFloat = 240, bh: CGFloat = 52, gap: CGFloat = 28
        playButtonRect = makeTitleButton(
            text: Strings.Title.playGame, color: green,
            center: CGPoint(x: size.width / 2 - bw / 2 - gap / 2, y: promptY),
            size: CGSize(width: bw, height: bh), textDY: -1, icon: "🕹️")
        editorButtonRect = makeTitleButton(
            text: Strings.Title.levelEditor, color: blue,
            center: CGPoint(x: size.width / 2 + bw / 2 + gap / 2, y: promptY),
            size: CGSize(width: bw, height: bh), icon: "✏️")

        let high = Persistence.int(forKey: Strings.DefaultsKey.highScore)
        if high > 0 {
            let hs = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
            hs.text = Strings.Title.highScore(high)
            hs.fontSize = 26 * SpriteFactory.worldRenderScale
            hs.setScale(1 / SpriteFactory.worldRenderScale)
            hs.fontColor = .black
            hs.position = CGPoint(x: size.width / 2, y: size.height * 0.06 + 10)
            addChild(hs)
        }

        let panelSize = CGSize(width: 320, height: 400)
        let panel = LeaderboardPanel(
            size: panelSize,
            titleFont: Strings.Font.markerFeltThin,
            bodyFont: Strings.Font.menloBold
        )
        panel.position = CGPoint(x: panelSize.width / 2 + 32, y: size.height * 0.5 + 28)   // leaderboard raised 8px
        addChild(panel)

        let controlsHint = SKLabelNode(fontNamed: Strings.Font.menloBold)
        controlsHint.text = Strings.Title.controlsHint
        controlsHint.fontSize = 16
        controlsHint.fontColor = .black
        controlsHint.horizontalAlignmentMode = .center
        controlsHint.position = CGPoint(x: size.width / 2, y: 18)
        addChild(controlsHint)

        // Window controls hug the bottom-right corner; the gameplay toggles
        // (Water Gun / Boss Tracks) hug the bottom-left. 80px apart, big + tappable.
        fullscreenLabel = makeHint(icon: "📺", iconSize: 42, value: "FULLSCREEN", y: promptY - 74, color: .systemRed)
        escWindowLabel  = makeHint(icon: "🪟", iconSize: 42, value: "WINDOW", y: promptY, color: .systemTeal)   // even with EDITOR
        mazeLabel       = makeHint(icon: "", iconSize: 42, value: mazeText(), y: promptY + 74, color: .systemPurple,
                                    sprite: SpriteFactory.bossPersonForBlueprint(1))
        bossTracksLabel = makeHint(icon: "", iconSize: 42, value: bossTracksText(), y: promptY - 74, color: .systemIndigo, left: true,
                                   sprite: SpriteFactory.bossPersonForBlueprint(0))
        waterGunLabel   = makeHint(icon: "🔫", iconSize: 42, value: waterGunText(), y: promptY, color: .systemOrange, left: true)   // GUN even with PLAY
    }

    // MARK: - Settings text
    private func bossTracksText() -> String {
        isSquareTracks() ? "HUNTER" : "SPEEDSTER"
    }
    private func waterGunText() -> String {
        if Persistence.bool(forKey: Strings.DefaultsKey.waterGunHide) { return "HIDDEN" }
        return Persistence.bool(forKey: Strings.DefaultsKey.waterGunLeft) ? "LEFT" : "RIGHT"
    }

    // Cycle Left -> Right -> Hide -> Left (two bools: waterGunLeft + waterGunHide).
    private func cycleWaterGun() {
        if Persistence.bool(forKey: Strings.DefaultsKey.waterGunHide) {          // Hide -> Left
            Persistence.set(false, forKey: Strings.DefaultsKey.waterGunHide)
            Persistence.set(true,  forKey: Strings.DefaultsKey.waterGunLeft)
        } else if Persistence.bool(forKey: Strings.DefaultsKey.waterGunLeft) {   // Left -> Right
            Persistence.set(false, forKey: Strings.DefaultsKey.waterGunLeft)
        } else {                                                                 // Right -> Hide
            Persistence.set(true,  forKey: Strings.DefaultsKey.waterGunHide)
        }
    }
    private func isSquareTracks() -> Bool {
        Persistence.bool(forKey: Strings.DefaultsKey.bossTracksSquare, default: true)
    }
    private func mazeText() -> String {
        MazeZoom.label
    }

    // MARK: - Builders
    // Every button fill is darkened 30% toward black (richer than the raw system hue).
    private func dimmed(_ c: SKColor) -> SKColor { c.blended(withFraction: 0.3, of: .black) ?? c }

    @discardableResult
    private func makeTitleButton(text: String, color: SKColor, center: CGPoint,
                                 size s: CGSize, textDY: CGFloat = 0, icon: String? = nil) -> CGRect {
        let N = SpriteFactory.worldRenderScale
        let container = SKNode()
        container.position = center
        container.zPosition = 5
        addChild(container)
        let bg = SKShapeNode(rect: CGRect(x: -s.width / 2 * N, y: -s.height / 2 * N, width: s.width * N, height: s.height * N),
                             cornerRadius: 12 * N)
        bg.setScale(1 / N)
        bg.fillColor = dimmed(color)
        bg.strokeColor = SKColor(white: 1, alpha: 0.55)   // match the side toggle buttons
        bg.lineWidth = 2 * N
        container.addChild(bg)

        let label = SKLabelNode(fontNamed: Strings.Font.markerFeltWide)
        label.text = text
        label.fontSize = 34 * N
        label.setScale(1 / N)
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.zPosition = 6
        if let icon = icon {
            let iconNode = SKLabelNode(text: icon)
            iconNode.fontSize = 42 * N
            iconNode.setScale(1 / N)
            iconNode.verticalAlignmentMode = .center
            iconNode.horizontalAlignmentMode = .center
            iconNode.position = CGPoint(x: -s.width / 2 + 40, y: textDY)
            iconNode.zPosition = 6
            container.addChild(iconNode)
            label.horizontalAlignmentMode = .left
            label.position = CGPoint(x: -s.width / 2 + 84, y: textDY)
        } else {
            label.horizontalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: textDY)
        }
        container.addChild(label)
        return CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height)
    }

    // Side toggle as a button: rounded fill + border, a fixed-position emoji icon, and
    // the left-aligned value in Marker Felt Wide (white). Anchoring the icon and value at
    // fixed offsets means changing the value never re-centres the row (no number jump).
    private func makeHint(icon: String, iconSize: CGFloat, value: String, y: CGFloat, color: SKColor, left: Bool = false, sprite: SKNode? = nil) -> SKLabelNode {
        let N = SpriteFactory.worldRenderScale
        let btnW: CGFloat = 292, btnH: CGFloat = 50, margin: CGFloat = 16
        let cx = left ? margin + btnW / 2 : size.width - margin - btnW / 2
        let container = SKNode()
        container.position = CGPoint(x: cx, y: y)
        container.zPosition = 5
        addChild(container)

        let bg = SKShapeNode(rect: CGRect(x: -btnW / 2 * N, y: -btnH / 2 * N, width: btnW * N, height: btnH * N), cornerRadius: 12 * N)
        bg.setScale(1 / N)
        bg.fillColor = dimmed(color)
        bg.strokeColor = SKColor(white: 1, alpha: 0.55)
        bg.lineWidth = 2 * N
        container.addChild(bg)

        let iconX = -btnW / 2 + 38
        if let sprite {
            let f = sprite.calculateAccumulatedFrame()
            let s = f.height > 0 ? iconSize / f.height : 1
            sprite.setScale(s)
            sprite.position = CGPoint(x: iconX - f.midX * s, y: -f.midY * s)
            sprite.zPosition = 6
            container.addChild(sprite)
        } else {
            let iconNode = SKLabelNode(text: icon)
            iconNode.fontSize = iconSize * N
            iconNode.setScale(1 / N)
            iconNode.verticalAlignmentMode = .center
            iconNode.horizontalAlignmentMode = .center
            iconNode.position = CGPoint(x: iconX, y: 0)
            iconNode.zPosition = 6
            container.addChild(iconNode)
        }

        let label = SKLabelNode(fontNamed: Strings.Font.markerFeltWide)
        label.text = value
        label.fontSize = 32 * N
        label.setScale(1 / N)
        label.fontColor = .white
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: -btnW / 2 + 80, y: 0)
        label.zPosition = 6
        container.addChild(label)
        return label
    }

    // MARK: - Actions (shared)
    private func startGame() {
        if MazeZoom.is3D { startBonus(); return }   // RAYCAST 3D / VOXEL 3D = first-person bonus
        view?.preferredFramesPerSecond = 60
        let game = GameScene(size: size)
        game.scaleMode = .aspectFit
        view?.presentScene(game, transition: .fade(withDuration: 0.5))
    }

    private func startEditor() {
        view?.preferredFramesPerSecond = 30
        let editor = LevelEditorScene(size: size)
        editor.scaleMode = .aspectFit
        view?.presentScene(editor, transition: .fade(withDuration: 0.3))
    }

    private func startBonus() {
        view?.preferredFramesPerSecond = 60
        let bonus: Bonus3DScene = MazeZoom.isVoxel ? VoxelScene(size: size) : DoomScene(size: size)
        bonus.scaleMode = SKSceneScaleMode.aspectFit
        view?.presentScene(bonus, transition: .fade(withDuration: 0.5))
    }

    private func enterFullscreen() { view?.enterFullscreen() }
    private func exitToWindow()    { view?.exitFullscreen() }

    // Shared tap routing — both ports funnel their pointer event through here.
    private func handleTap(at p: CGPoint) {
        if playButtonRect.contains(p)   { startGame();   return }
        if editorButtonRect.contains(p) { startEditor(); return }
        if let fs = fullscreenLabel, labelHit(fs, p) { enterFullscreen(); return }
        if let esc = escWindowLabel, labelHit(esc, p) { exitToWindow();   return }
        if let m = mazeLabel, labelHit(m, p) {
            MazeZoom.advance()
            m.text = mazeText()
            return
        }
        if let t = bossTracksLabel, labelHit(t, p) {
            Persistence.set(!isSquareTracks(), forKey: Strings.DefaultsKey.bossTracksSquare)
            t.text = bossTracksText()
            return
        }
        if let wg = waterGunLabel, labelHit(wg, p) {
            cycleWaterGun()
            wg.text = waterGunText()
            return
        }
    }

    private func labelHit(_ label: SKLabelNode, _ p: CGPoint) -> Bool {
        guard let container = label.parent else { return label.frame.insetBy(dx: -12, dy: -10).contains(p) }
        return container.calculateAccumulatedFrame().contains(p)   // whole button is tappable
    }

    // MARK: - Input (platform event shapes funnel into the shared actions)
    override func keyDown(with event: NSEvent) { handleKey(Int(event.keyCode)) }
    override func mouseDown(with event: NSEvent) { handleTap(at: event.location(in: self)) }

    private func handleKey(_ key: Int) {
        switch key {
        case KeyCode.keyP, KeyCode.space: startGame()
        case KeyCode.keyE:                startEditor()
        case KeyCode.digit3:              startBonus()
        case KeyCode.keyF:                enterFullscreen()
        case KeyCode.esc:                 exitToWindow()
        default:                          break
        }
    }

    // MARK: - Stapler
    private func makeStapler() -> SKNode {
        let maxSize = CGSize(width: 380, height: 290)
        if let url = Bundle.main.url(forResource: Strings.Resource.redStaplerFile,
                                      withExtension: Strings.Resource.redStaplerExtension),
           let image = NSImage(contentsOf: url) {
            let scale = min(maxSize.width / image.size.width, maxSize.height / image.size.height)
            let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            return SKSpriteNode(texture: SKTexture(image: image), size: fitted)
        }
        return makeFallbackStapler()
    }

    private func makeFallbackStapler() -> SKNode {
        let stapler = SKNode()
        let base = SKShapeNode(rect: CGRect(x: -110, y: -22, width: 220, height: 16), cornerRadius: 4)
        base.fillColor = SKColor(calibratedRed: 0.55, green: 0.05, blue: 0.05, alpha: 1)
        base.strokeColor = SKColor(calibratedRed: 0.12, green: 0, blue: 0, alpha: 1)
        base.lineWidth = 1.5
        stapler.addChild(base)
        let arm = SKShapeNode(rect: CGRect(x: -100, y: -4, width: 220, height: 26), cornerRadius: 8)
        arm.fillColor = .systemRed
        arm.strokeColor = SKColor(calibratedRed: 0.12, green: 0, blue: 0, alpha: 1)
        arm.lineWidth = 1.5
        stapler.addChild(arm)
        let gloss = SKShapeNode(rect: CGRect(x: -90, y: 13, width: 195, height: 5), cornerRadius: 2)
        gloss.fillColor = SKColor(calibratedRed: 1.0, green: 0.78, blue: 0.78, alpha: 0.85)
        gloss.strokeColor = .clear
        stapler.addChild(gloss)
        return stapler
    }
}
