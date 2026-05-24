import AppKit
import Darwin
import GameKit
import SpriteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, GKGameCenterControllerDelegate {
    static let startFullscreenKey = Strings.DefaultsKey.startFullscreen

    static var startFullscreenPreference: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: startFullscreenKey) == nil { return true }
            return defaults.bool(forKey: startFullscreenKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: startFullscreenKey) }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private var window: NSWindow!
    private var startFullscreenMenuItem: NSMenuItem?
    private var fullscreenMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        // 37 cols × 32pt = 1184 wide, 17 rows × 32pt = 544 + 104 HUD = 648 tall.
        let sceneSize = CGSize(width: 1184, height: 648)
        let skView = SKView(frame: CGRect(origin: .zero, size: sceneSize))
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = 60
        skView.shouldCullNonVisibleNodes = true
        skView.showsFPS = false
        skView.showsNodeCount = false
        skView.showsPhysics = false
        skView.disableDepthStencilBuffer = false
        
        skView.allowsTransparency = true

        let scene = TitleScene(size: sceneSize)
        scene.scaleMode = .aspectFit
        skView.presentScene(scene)

        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: sceneSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = Strings.App.bundleName
        window.center()
        window.contentView = skView
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.tabbingMode = .disallowed
        window.makeKeyAndOrderFront(nil)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowFullscreenStateChanged(_:)),
                           name: NSWindow.didEnterFullScreenNotification, object: window)
        center.addObserver(self, selector: #selector(windowFullscreenStateChanged(_:)),
                           name: NSWindow.didExitFullScreenNotification, object: window)

        if AppDelegate.startFullscreenPreference {
            DispatchQueue.main.async { [weak window] in
                window?.toggleFullScreen(nil)
            }
        }

        authenticateGameCenter()
    }

    private func authenticateGameCenter() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            if let viewController {
                self?.presentGameCenterAuth(viewController)
                return
            }
            if let error {
                NSLog(Strings.App.gameCenterAuthFailed(error.localizedDescription))
            }
        }
    }

    private func presentGameCenterAuth(_ viewController: NSViewController) {
        let authWindow = NSWindow(contentViewController: viewController)
        authWindow.styleMask = [.titled, .closable]
        authWindow.title = Strings.App.signInToGameCenter
        authWindow.center()
        authWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleStartFullscreenPreference(_ sender: Any?) {
        AppDelegate.startFullscreenPreference.toggle()
        startFullscreenMenuItem?.state = AppDelegate.startFullscreenPreference ? .on : .off
    }

    @objc private func resetLocalLeaderboard(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = Strings.App.resetAlertTitle
        alert.informativeText = Strings.App.resetAlertBody
        alert.alertStyle = .warning
        alert.addButton(withTitle: Strings.App.resetButton)
        alert.addButton(withTitle: Strings.App.cancelButton)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.removeObject(forKey: LocalHighScores.storeKey)
        UserDefaults.standard.removeObject(forKey: RoundState.highScoreKey)
    }

    @objc private func toggleWindowFullscreen(_ sender: Any?) {
        window?.toggleFullScreen(nil)
    }

    @objc private func openGameCenter(_ sender: Any?) {
        let vc = GKGameCenterViewController(state: .default)
        vc.gameCenterDelegate = self
        let hostingWindow = NSWindow(contentViewController: vc)
        hostingWindow.styleMask = [.titled, .closable, .resizable]
        hostingWindow.title = Strings.App.gameCenter
        hostingWindow.setContentSize(CGSize(width: 720, height: 540))
        hostingWindow.center()
        hostingWindow.makeKeyAndOrderFront(nil)
    }

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.view.window?.close()
    }

    @objc private func windowFullscreenStateChanged(_ notification: Notification) {
        let isFullscreen = window?.styleMask.contains(.fullScreen) ?? false
        fullscreenMenuItem?.title = isFullscreen ? Strings.App.exitFullscreen : Strings.App.enterFullscreen
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let appName = Strings.App.bundleName

        appMenu.addItem(withTitle: Strings.Menu.about(appName), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: Strings.KeyEquivalent.none)
        appMenu.addItem(NSMenuItem.separator())

        let startFullscreenItem = appMenu.addItem(
            withTitle: Strings.App.startFullscreen,
            action: #selector(toggleStartFullscreenPreference(_:)),
            keyEquivalent: Strings.KeyEquivalent.none
        )
        startFullscreenItem.target = self
        startFullscreenItem.state = AppDelegate.startFullscreenPreference ? .on : .off
        startFullscreenMenuItem = startFullscreenItem

        let resetLeaderboardItem = appMenu.addItem(
            withTitle: Strings.App.resetLocalLeaderboard,
            action: #selector(resetLocalLeaderboard(_:)),
            keyEquivalent: Strings.KeyEquivalent.none
        )
        resetLeaderboardItem.target = self

        let gameCenterItem = appMenu.addItem(
            withTitle: Strings.App.gameCenter,
            action: #selector(openGameCenter(_:)),
            keyEquivalent: Strings.KeyEquivalent.none
        )
        gameCenterItem.target = self
        appMenu.addItem(NSMenuItem.separator())

        let hideItem = appMenu.addItem(withTitle: Strings.Menu.hide(appName), action: #selector(NSApplication.hide(_:)), keyEquivalent: Strings.KeyEquivalent.hide)
        hideItem.keyEquivalentModifierMask = [.command]

        let hideOthersItem = appMenu.addItem(withTitle: Strings.Menu.hideOthers, action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: Strings.KeyEquivalent.hide)
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]

        appMenu.addItem(withTitle: Strings.Menu.showAll, action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: Strings.KeyEquivalent.none)
        appMenu.addItem(NSMenuItem.separator())

        let quitItem = appMenu.addItem(withTitle: Strings.Menu.quit(appName), action: #selector(NSApplication.terminate(_:)), keyEquivalent: Strings.KeyEquivalent.quit)
        quitItem.keyEquivalentModifierMask = [.command]

        appMenuItem.submenu = appMenu

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: Strings.Menu.view)
        let fullscreenItem = viewMenu.addItem(
            withTitle: Strings.App.enterFullscreen,
            action: #selector(toggleWindowFullscreen(_:)),
            keyEquivalent: Strings.KeyEquivalent.fullscreen
        )
        fullscreenItem.target = self
        fullscreenItem.keyEquivalentModifierMask = [.command, .control]
        fullscreenMenuItem = fullscreenItem
        viewMenuItem.submenu = viewMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: Strings.Menu.window)
        windowMenu.addItem(withTitle: Strings.Menu.minimize, action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: Strings.KeyEquivalent.minimize)
        windowMenu.addItem(withTitle: Strings.Menu.close, action: #selector(NSWindow.performClose(_:)), keyEquivalent: Strings.KeyEquivalent.close)
        windowMenuItem.submenu = windowMenu
        NSApplication.shared.windowsMenu = windowMenu

        NSApplication.shared.mainMenu = mainMenu
    }
}

@main
@MainActor
enum BossManApp {
    static func main() {
        setenv(Strings.System.osActivityModeKey, Strings.System.osActivityDisable, 1)
        #if !DEBUG
        freopen(Strings.System.devNull, Strings.System.writeMode, stderr)
        #endif

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
