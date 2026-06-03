import AppKit
import WebKit

// MARK: - Logical render size (matches the SpriteKit -> WebAssembly canvas)

private let logicalWidth: CGFloat = 1184
private let logicalHeight: CGFloat = 666

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, NSWindowDelegate, WKScriptMessageHandler {
    private var window: NSWindow!
    private var webView: WKWebView!

    private static let nativeWindowMessage = "nativeWindow"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.installMainMenu()
        let root = Self.resolveWebRoot()

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(WebFolderSchemeHandler(root: root), forURLScheme: WebFolderSchemeHandler.scheme)
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = WKUserContentController()
        controller.add(self, name: Self.nativeWindowMessage)
        controller.addUserScript(WKUserScript(source: Self.fullscreenBridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController = controller

        let frame = NSRect(x: 0, y: 0, width: logicalWidth, height: logicalHeight)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsMagnification = false
        webView.setValue(false, forKey: "drawsBackground")

        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Boss-Man"
        window.delegate = self
        window.contentView = webView
        window.contentAspectRatio = NSSize(width: logicalWidth, height: logicalHeight)
        window.contentMinSize = NSSize(width: logicalWidth / 2, height: logicalHeight / 2)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.center()
        window.setFrameAutosaveName("BossManDesktopWindow")
        window.makeKeyAndOrderFront(nil)
        window.initialFirstResponder = webView

        let entry = URL(string: "\(WebFolderSchemeHandler.scheme)://app/server.html")!
        webView.load(URLRequest(url: entry))

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.window?.makeFirstResponder(webView)
    }

    // MARK: - Fullscreen bridge (in-game button -> native window)

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.nativeWindowMessage,
              let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              let window else { return }

        let isFullscreen = window.styleMask.contains(.fullScreen)
        switch action {
        case "enter":  if !isFullscreen { window.toggleFullScreen(nil) }
        case "exit":   if isFullscreen { window.toggleFullScreen(nil) }
        case "toggle": window.toggleFullScreen(nil)
        default: break
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) { notifyFullscreen(true) }
    func windowDidExitFullScreen(_ notification: Notification) { notifyFullscreen(false) }

    private func notifyFullscreen(_ on: Bool) {
        webView.evaluateJavaScript("window.__bossmanFullscreen && window.__bossmanFullscreen(\(on))")
    }

    private static let fullscreenBridgeJS = """
    (function () {
      var mh = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeWindow;
      if (!mh) return;
      var fsElement = null;
      function post(action) { try { mh.postMessage({ action: action }); } catch (e) {} }
      function game() { return document.getElementById('game') || document.documentElement; }

      Element.prototype.requestFullscreen = function () { fsElement = this; post('enter'); return Promise.resolve(); };
      Element.prototype.webkitRequestFullscreen = function () { fsElement = this; post('enter'); };
      Document.prototype.exitFullscreen = function () { post('exit'); return Promise.resolve(); };
      Document.prototype.webkitExitFullscreen = function () { post('exit'); };

      Object.defineProperty(document, 'fullscreenElement', { configurable: true, get: function () { return fsElement; } });
      Object.defineProperty(document, 'webkitFullscreenElement', { configurable: true, get: function () { return fsElement; } });

      function fire(type) {
        var ev;
        try { ev = new Event(type); } catch (e) { ev = document.createEvent('Event'); ev.initEvent(type, true, false); }
        document.dispatchEvent(ev);
      }

      window.__bossmanFullscreen = function (on) {
        var g = game();
        if (on) {
          fsElement = g;
          if (g.dataset) g.dataset.bmPrevStyle = g.getAttribute('style') || '';
          g.style.width = '100vw';
          g.style.height = '100vh';
          g.style.maxWidth = 'none';
          g.style.maxHeight = 'none';
          g.style.borderRadius = '0';
        } else {
          fsElement = null;
          g.setAttribute('style', (g.dataset && g.dataset.bmPrevStyle) || '');
        }
        fire('fullscreenchange');
        fire('webkitfullscreenchange');
      };
    })();
    """

    // MARK: - Main menu

    private static func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Hide Boss-Man", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Boss-Man", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        let fullScreen = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Locate the bundled web payload

    private static func resolveWebRoot() -> URL {
        let fm = FileManager.default

        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("web"),
           fm.fileExists(atPath: bundled.appendingPathComponent("server.html").path) {
            return bundled
        }

        if let override = ProcessInfo.processInfo.environment["BOSSMAN_WEB_ROOT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot.appendingPathComponent("boss-man-spritekit-web/web", isDirectory: true)
    }
}

// MARK: - Entry point

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
