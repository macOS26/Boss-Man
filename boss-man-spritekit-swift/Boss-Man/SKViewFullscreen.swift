import SpriteKit
#if os(macOS)
import AppKit

// macOS half of the framework's SKView fullscreen shim. On wasm SKView.enter/
// exitFullscreen() forward to the host (win_request/exit_fullscreen); here they
// toggle the AppKit window, so shared scene code calls view?.enterFullscreen()
// and view?.exitFullscreen() with no #if. The guards mirror the master so the
// behavior is unchanged.
extension SKView {
    func enterFullscreen() {
        guard let w = window, !w.styleMask.contains(.fullScreen) else { return }
        w.toggleFullScreen(nil)
    }
    func exitFullscreen() {
        guard let w = window, w.styleMask.contains(.fullScreen) else { return }
        w.toggleFullScreen(nil)
    }
}
#endif
