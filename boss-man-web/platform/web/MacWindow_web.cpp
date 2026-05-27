// Web implementations of the macOS window helpers. Most are no-ops; fullscreen
// routes to the browser Fullscreen API, and the editor's confirm dialog proceeds
// (the page has no modal NSAlert).
#include "MacWindow.hpp"
#include "abi.h"

namespace bm {

void enableNativeFullscreen(void*) {}
void toggleNativeFullscreen(void*) { win_request_fullscreen(); }
float windowBackingScale(void*) { return 1.0f; }
int displayRefreshHz(void*) { return 60; }
bool macConfirmDialog(const char*, const char*, const char*, const char*) { return true; }
void macRevealInFinder(const char*) {}

} // namespace bm
