#include "MacWindow.hpp"
#import <AppKit/AppKit.h>

namespace bm {

static NSWindow* nsWindowFrom(void* handle) {
    if (!handle) return nil;
    id obj = (__bridge id)handle;
    if ([obj isKindOfClass:[NSWindow class]]) return (NSWindow*)obj;
    if ([obj isKindOfClass:[NSView class]]) return [(NSView*)obj window];
    return nil;
}

void enableNativeFullscreen(void* handle) {
    NSWindow* w = nsWindowFrom(handle);
    if (!w) return;
    // Lets the green title-bar button (and ⌃⌘F) enter macOS-native fullscreen, and
    // makes "Enter Full Screen" available where a View menu exists.
    w.collectionBehavior |= NSWindowCollectionBehaviorFullScreenPrimary;
    w.styleMask |= NSWindowStyleMaskResizable;
}

void toggleNativeFullscreen(void* handle) {
    NSWindow* w = nsWindowFrom(handle);
    if (w) [w toggleFullScreen:nil];
}

float windowBackingScale(void* handle) {
    NSWindow* w = nsWindowFrom(handle);
    if (w) return (float)w.backingScaleFactor;
    return (float)[NSScreen mainScreen].backingScaleFactor;
}

} // namespace bm
