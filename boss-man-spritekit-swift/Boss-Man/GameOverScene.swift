import AppKit
import SpriteKit

@MainActor
final class GameOverScene: SKScene {

    private let score: Int
    private let highScore: Int
    private let allowEntry: Bool
    private let defaultName: String
    private let isPractice: Bool
    private let practiceLevel: Int
    private let makeRestartScene: () -> SKScene

    init(size: CGSize, score: Int, highScore: Int, allowEntry: Bool,
         defaultName: String, isPractice: Bool, practiceLevel: Int,
         makeRestartScene: @escaping () -> SKScene) {
        self.score = score
        self.highScore = highScore
        self.allowEntry = allowEntry
        self.defaultName = defaultName
        self.isPractice = isPractice
        self.practiceLevel = practiceLevel
        self.makeRestartScene = makeRestartScene
        super.init(size: size)
        scaleMode = .aspectFit
    }

    required init?(coder: NSCoder) { fatalError() }

    private var screen: GameOverScreen?

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 20
        backgroundColor = .black
        anchorPoint = .zero
        #if hasFeature(Embedded)
        let onPlayCB: () -> Void = { [unowned(unsafe) self] in self.play() }
        let onEscCB: () -> Void = { [unowned(unsafe) self] in self.esc() }
        #else
        let onPlayCB: () -> Void = { [weak self] in self?.play() }
        let onEscCB: () -> Void = { [weak self] in self?.esc() }
        #endif
        let s = GameOverScreen(
            size: size, font: Strings.Font.menloBold,
            score: score, highScore: highScore,
            defaultName: defaultName, allowEntry: allowEntry,
            onPlay: onPlayCB,
            onEsc:  onEscCB)
        s.position = .zero
        addChild(s)
        screen = s
    }

    private func play() {
        guard let view else { return }
        let next = makeRestartScene()
        view.presentScene(next, transition: .fade(withDuration: 0.5))
    }

    private func esc() {
        guard let view else { return }
        if isPractice {
            let editor = LevelEditorScene(size: size)
            editor.scaleMode = .aspectFit
            editor.currentLevelIndex = max(0, practiceLevel - 1)
            view.presentScene(editor, transition: .fade(withDuration: 0.5))
            return
        }
        let title = TitleScene(size: size)
        title.scaleMode = .aspectFit
        view.presentScene(title, transition: .fade(withDuration: 0.5))
    }

    override func keyDown(with event: NSEvent) {
        #if os(macOS)
        screen?.handleKey(usernameKeyCode(for: event), shift: event.modifierFlags.contains(.shift))
        #else
        screen?.handleKey(Int(event.keyCode), shift: false)
        #endif
    }

    override func mouseDown(with event: NSEvent) {
        screen?.handleTap(at: event.location(in: self))
    }
}
