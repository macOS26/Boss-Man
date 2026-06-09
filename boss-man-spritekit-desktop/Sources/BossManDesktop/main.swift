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
    private static let nativeDownloadMessage = "nativeDownload"

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let root = Self.resolveWebRoot()

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(WebFolderSchemeHandler(root: root), forURLScheme: WebFolderSchemeHandler.scheme)
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let controller = WKUserContentController()
        controller.add(self, name: Self.nativeWindowMessage)
        controller.add(self, name: Self.nativeDownloadMessage)
        controller.addUserScript(WKUserScript(source: Self.fullscreenBridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: Self.downloadBridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: Self.chromelessCSS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        configuration.userContentController = controller

        let frame = NSRect(x: 0, y: 0, width: logicalWidth, height: logicalHeight)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsMagnification = false
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

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
        switch message.name {
        case Self.nativeWindowMessage:   handleWindowMessage(message)
        case Self.nativeDownloadMessage: handleDownloadMessage(message)
        default: break
        }
    }

    private func handleWindowMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
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

    // The editor's SHOW button triggers a blob <a download> the WKWebView ignores.
    // The download bridge posts the file here; write it to ~/Downloads and reveal
    // it in Finder, matching the native macOS "Reveal File" behavior.
    private func handleDownloadMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let name = body["name"] as? String,
              let data = body["data"] as? String else { return }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let dest = downloads.appendingPathComponent(name.isEmpty ? "levels.json" : name)
        do {
            try data.write(to: dest, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            NSLog("Boss-Man: download save failed for \(dest.path): \(error)")
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) { notifyFullscreen(true) }
    func windowDidExitFullScreen(_ notification: Notification) { notifyFullscreen(false) }

    private func notifyFullscreen(_ on: Bool) {
        webView.evaluateJavaScript("window.__bossmanFullscreen && window.__bossmanFullscreen(\(on))")
    }

    private static let chromelessCSS = """
    (function () {
      var css = "html,body{margin:0!important;padding:0!important;height:100%!important;overflow:hidden!important;background:#000!important;gap:0!important}"
        + "#game{width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;border-radius:0!important;aspect-ratio:auto!important}"
        + "#footer{display:none!important}";
      var s = document.createElement('style');
      s.textContent = css;
      (document.head || document.documentElement).appendChild(s);
    })();
    """

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

      // WKWebView reports fullscreenEnabled === false, so the runtime's
      // win_request_fullscreen gate skips the (bridged) requestFullscreen and
      // takes the dead pseudo-fullscreen path. Report true so the in-game
      // FULLSCREEN/WINDOW buttons route through the native NSWindow toggle.
      Object.defineProperty(document, 'fullscreenEnabled', { configurable: true, get: function () { return true; } });
      Object.defineProperty(document, 'webkitFullscreenEnabled', { configurable: true, get: function () { return true; } });

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

    // The runtime downloads files (levels.json from the editor's SHOW button) by
    // clicking a blob <a download>, which a WKWebView drops on the floor. Catch
    // that click, read the blob text, and hand it to the native side to save +
    // reveal. Only download anchors are intercepted; normal links are untouched.
    private static let downloadBridgeJS = """
    (function () {
      var mh = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeDownload;
      if (!mh) return;
      var origClick = HTMLAnchorElement.prototype.click;
      HTMLAnchorElement.prototype.click = function () {
        try {
          if (this.download && this.href && this.href.indexOf('blob:') === 0) {
            var name = this.download;
            fetch(this.href).then(function (r) { return r.text(); }).then(function (text) {
              try { mh.postMessage({ name: name, data: text }); } catch (e) {}
            });
            return;
          }
        } catch (e) {}
        return origClick.apply(this, arguments);
      };
    })();
    """

    // MARK: - Main menu

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Hide Boss-Man", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Boss-Man", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        let fullScreen = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]

        let developItem = NSMenuItem()
        mainMenu.addItem(developItem)
        let developMenu = NSMenu(title: "Develop")
        developItem.submenu = developMenu
        let inspect = developMenu.addItem(withTitle: "Show Web Inspector", action: #selector(showWebInspector(_:)), keyEquivalent: "i")
        inspect.keyEquivalentModifierMask = [.command, .option]
        inspect.target = self
        developMenu.addItem(withTitle: "Reload", action: #selector(reloadPage(_:)), keyEquivalent: "r").target = self

        NSApp.mainMenu = mainMenu
    }

    @objc private func showWebInspector(_ sender: Any?) {
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        let key = Selector(("_inspector"))
        guard webView.responds(to: key),
              let inspector = webView.value(forKey: "_inspector") as? NSObject else { return }
        let show = Selector(("show"))
        if inspector.responds(to: show) {
            inspector.perform(show)
        }
    }

    @objc private func reloadPage(_ sender: Any?) {
        webView.reload()
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
