#pragma once

namespace bm {

// macOS-native fullscreen helpers. `handle` is the SFML window system handle
// (an NSWindow* on macOS). No-ops on other platforms.
void enableNativeFullscreen(void* handle); // makes the green button toggle fullscreen
void toggleNativeFullscreen(void* handle); // same as clicking it / ⌃⌘F
float windowBackingScale(void* handle);    // Retina backing scale (2.0 on HiDPI, else 1.0)
int displayRefreshHz(void* handle);        // screen's max refresh (120 on ProMotion, else 60)

// Runs a modal NSAlert (warning style) with a destructive + cancel button.
// Returns true when the destructive (first) button is chosen. Used by the level
// editor's Clear confirmation, mirroring the SpriteKit NSAlert.
bool macConfirmDialog(const char* title, const char* body,
                      const char* destructiveButton, const char* cancelButton);

// Reveals (and selects) a file in Finder, like NSWorkspace.activateFileViewerSelecting.
void macRevealInFinder(const char* path);

} // namespace bm
