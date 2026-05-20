import AppKit
import Darwin
import GameKit
import SpriteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let startFullscreenKey = "Boss-Man.startFullscreen"

    /// User preference: launch fullscreen on next start. Defaults to true
    /// the first time the app runs so new users get the immersive view.
    static var startFullscreenPreference: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: startFullscreenKey) == nil { return true }
            return defaults.bool(forKey: startFullscreenKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: startFullscreenKey) }
    }

    // Opt in to secure coding for state restoration so the runtime stops
    // warning "not on all supported macOS versions of this application."
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private var window: NSWindow!
    private var startFullscreenMenuItem: NSMenuItem?
    private var fullscreenMenuItem: NSMenuItem?

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
        window.collectionBehavior.insert(.fullScreenPrimary)
        // No browser-style tab bar — the game is a single window.
        window.tabbingMode = .disallowed
        window.makeKeyAndOrderFront(nil)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowFullscreenStateChanged(_:)),
                           name: NSWindow.didEnterFullScreenNotification, object: window)
        center.addObserver(self, selector: #selector(windowFullscreenStateChanged(_:)),
                           name: NSWindow.didExitFullScreenNotification, object: window)

        if AppDelegate.startFullscreenPreference {
            // Defer until after the window is on-screen so AppKit's
            // fullscreen transition has a valid starting frame.
            DispatchQueue.main.async { [weak window] in
                window?.toggleFullScreen(nil)
            }
        }

        authenticateGameCenter()
    }

    /// Authenticates the local Game Center player so macOS can populate
    /// the Game Overlay's "Now Playing" tile with this app's icon and
    /// player state. First run on an unsigned-in machine will hand back
    /// a sign-in view controller; we present it in a transient window.
    private func authenticateGameCenter() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            if let viewController {
                self?.presentGameCenterAuth(viewController)
                return
            }
            if let error {
                NSLog("Game Center auth failed: \(error.localizedDescription)")
            }
        }
    }

    private func presentGameCenterAuth(_ viewController: NSViewController) {
        let authWindow = NSWindow(contentViewController: viewController)
        authWindow.styleMask = [.titled, .closable]
        authWindow.title = "Sign in to Game Center"
        authWindow.center()
        authWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleStartFullscreenPreference(_ sender: Any?) {
        AppDelegate.startFullscreenPreference.toggle()
        startFullscreenMenuItem?.state = AppDelegate.startFullscreenPreference ? .on : .off
    }

    @objc private func toggleWindowFullscreen(_ sender: Any?) {
        window?.toggleFullScreen(nil)
    }

    @objc private func windowFullscreenStateChanged(_ notification: Notification) {
        let isFullscreen = window?.styleMask.contains(.fullScreen) ?? false
        fullscreenMenuItem?.title = isFullscreen ? "Exit Full Screen" : "Enter Full Screen"
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

        let startFullscreenItem = appMenu.addItem(
            withTitle: "Start in Full Screen",
            action: #selector(toggleStartFullscreenPreference(_:)),
            keyEquivalent: ""
        )
        startFullscreenItem.target = self
        startFullscreenItem.state = AppDelegate.startFullscreenPreference ? .on : .off
        startFullscreenMenuItem = startFullscreenItem
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

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        let fullscreenItem = viewMenu.addItem(
            withTitle: "Enter Full Screen",
            action: #selector(toggleWindowFullscreen(_:)),
            keyEquivalent: "f"
        )
        fullscreenItem.target = self
        fullscreenItem.keyEquivalentModifierMask = [.command, .control]
        fullscreenMenuItem = fullscreenItem
        viewMenuItem.submenu = viewMenu

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
