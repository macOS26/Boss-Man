import AppKit
import SpriteKit

@MainActor
final class UsernameDialog: SKNode {

    static let nodeName = "usernameDialog"
    static let confirmButtonName = "usernameDialogConfirm"
    static let skipButtonName = "usernameDialogSkip"

    private let panelSize: CGSize
    private let fontName: String
    private let onConfirm: (String) -> Void
    private let onSkip: () -> Void

    private var field: NSTextField!

    init(size: CGSize, fontName: String, onConfirm: @escaping (String) -> Void, onSkip: @escaping () -> Void) {
        self.panelSize = size
        self.fontName = fontName
        self.onConfirm = onConfirm
        self.onSkip = onSkip
        super.init()
        name = Self.nodeName
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        let overlay = SKShapeNode(rect: CGRect(x: -2000, y: -2000, width: 4000, height: 4000))
        overlay.fillColor = NSColor(calibratedWhite: 0, alpha: 0.45)
        overlay.strokeColor = .clear
        overlay.zPosition = 999
        addChild(overlay)

        let rect = CGRect(
            x: -panelSize.width / 2,
            y: -panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )

        let bg = SKShapeNode(rect: rect, cornerRadius: 12)
        bg.fillColor = NSColor(calibratedWhite: 1, alpha: 0.96)
        bg.strokeColor = NSColor(calibratedWhite: 0.7, alpha: 1)
        bg.lineWidth = 2
        bg.zPosition = 1000
        addChild(bg)

        let title = SKLabelNode(fontNamed: fontName)
        title.text = Strings.Leaderboard.newHighScoreTitle
        title.fontSize = 22
        title.fontColor = NSColor(calibratedRed: 0.18, green: 0.10, blue: 0.04, alpha: 1)
        title.horizontalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: panelSize.height / 2 - 38)
        title.zPosition = 1001
        addChild(title)

        let prompt = SKLabelNode(fontNamed: fontName)
        prompt.text = Strings.Leaderboard.enterUsernamePrompt
        prompt.fontSize = 16
        prompt.fontColor = NSColor(calibratedWhite: 0.35, alpha: 1)
        prompt.horizontalAlignmentMode = .center
        prompt.position = CGPoint(x: 0, y: panelSize.height / 2 - 62)
        prompt.zPosition = 1001
        addChild(prompt)

        let confirmBtn = SKShapeNode(rect: CGRect(x: -55, y: -panelSize.height / 2 + 18, width: 110, height: 34), cornerRadius: 8)
        confirmBtn.fillColor = .systemBlue
        confirmBtn.strokeColor = .clear
        confirmBtn.name = Self.confirmButtonName
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
        confirmLabel.name = Self.confirmButtonName
        addChild(confirmLabel)

        let skipBtn = SKShapeNode(rect: CGRect(x: -40, y: -panelSize.height / 2 + 58, width: 80, height: 24), cornerRadius: 6)
        skipBtn.fillColor = .clear
        skipBtn.strokeColor = NSColor(calibratedWhite: 0.6, alpha: 1)
        skipBtn.lineWidth = 1
        skipBtn.name = Self.skipButtonName
        skipBtn.zPosition = 1001
        addChild(skipBtn)

        let skipLabel = SKLabelNode(fontNamed: fontName)
        skipLabel.text = Strings.Leaderboard.skipButton
        skipLabel.fontSize = 13
        skipLabel.fontColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        skipLabel.horizontalAlignmentMode = .center
        skipLabel.verticalAlignmentMode = .center
        skipLabel.position = CGPoint(x: 0, y: -panelSize.height / 2 + 70)
        skipLabel.zPosition = 1002
        skipLabel.name = Self.skipButtonName
        addChild(skipLabel)
    }

    func attachFieldToView() {
        guard let view = scene?.view, field == nil else { return }

        let fieldWidth: CGFloat = panelSize.width - 60
        let fieldHeight: CGFloat = 30
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: fieldWidth, height: fieldHeight))
        field.placeholderString = Strings.Leaderboard.usernamePlaceholder
        field.font = NSFont(name: fontName, size: 16) ?? NSFont.systemFont(ofSize: 16)
        field.alignment = .center
        field.bezelStyle = .roundedBezel
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.stringValue = LocalHighScores.savedUsername ?? Strings.empty
        self.field = field

        let scenePoint = convert(CGPoint(x: 0, y: panelSize.height / 2 - 95), to: scene!)
        let viewPoint = view.convert(scenePoint, from: scene!)

        field.frame.origin = CGPoint(
            x: viewPoint.x - field.frame.width / 2,
            y: viewPoint.y - field.frame.height / 2
        )
        view.addSubview(field)
        view.window?.makeFirstResponder(field)

        if field.stringValue.isEmpty == false {
            field.selectText(nil)
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: field.stringValue.count)
        }
    }

    func removeFieldFromView() {
        field?.removeFromSuperview()
    }

    func handleConfirm() {
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        LocalHighScores.savedUsername = name
        removeFieldFromView()
        onConfirm(name)
    }

    func handleSkip() {
        removeFieldFromView()
        onSkip()
    }
}
