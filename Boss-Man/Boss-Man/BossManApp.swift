import AppKit
import Darwin
import SpriteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Opt in to secure coding for state restoration so the runtime stops
    // warning "not on all supported macOS versions of this application."
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        let sceneSize = CGSize(width: 1152, height: 648)
        let skView = SKView(frame: CGRect(origin: .zero, size: sceneSize))
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = 60
        skView.shouldCullNonVisibleNodes = true
        skView.showsFPS = false
        skView.showsNodeCount = false

        let scene = TitleScene(size: sceneSize)
        scene.scaleMode = .aspectFit
        skView.presentScene(scene)

        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: sceneSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Boss-Man"
        window.center()
        window.contentView = skView
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let appName = "Boss-Man"

        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())

        let hideItem = appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.keyEquivalentModifierMask = [.command]

        let hideOthersItem = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]

        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())

        let quitItem = appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]

        appMenuItem.submenu = appMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        NSApplication.shared.windowsMenu = windowMenu

        NSApplication.shared.mainMenu = mainMenu
    }
}

@main
@MainActor
enum BossManApp {
    static func main() {
        // Silence the AVSpeechSynthesizer / CoreAudio / Security.framework
        // stderr chatter (AFPreferences, AVAudioBuffer, AddInstanceForFactory,
        // DetachedSignatures, HALC overload, etc.). Must run before any
        // AppKit or AVFoundation symbol is touched so the env var is in
        // place when those frameworks initialize their logging.
        setenv("OS_ACTIVITY_MODE", "disable", 1)
        #if !DEBUG
        // Release-only: route raw stderr fprintf calls from Apple frameworks
        // to /dev/null. Kept out of Debug so crash diagnostics stay visible
        // during development.
        freopen("/dev/null", "w", stderr)
        #endif

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
