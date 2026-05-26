#pragma once

namespace bm {

// macOS-native fullscreen helpers. `handle` is the SFML window system handle
// (an NSWindow* on macOS). No-ops on other platforms.
void enableNativeFullscreen(void* handle); // makes the green button toggle fullscreen
void toggleNativeFullscreen(void* handle); // same as clicking it / ⌃⌘F
float windowBackingScale(void* handle);    // Retina backing scale (2.0 on HiDPI, else 1.0)

} // namespace bm
