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

bool macConfirmDialog(const char* title, const char* body,
                      const char* destructiveButton, const char* cancelButton) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = title ? [NSString stringWithUTF8String:title] : @"";
    alert.informativeText = body ? [NSString stringWithUTF8String:body] : @"";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:(destructiveButton ? [NSString stringWithUTF8String:destructiveButton] : @"OK")];
    [alert addButtonWithTitle:(cancelButton ? [NSString stringWithUTF8String:cancelButton] : @"Cancel")];
    return [alert runModal] == NSAlertFirstButtonReturn;
}

void macRevealInFinder(const char* path) {
    if (!path) return;
    NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[url]];
}

} // namespace bm
