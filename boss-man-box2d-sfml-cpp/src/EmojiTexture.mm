#include "EmojiText.hpp"
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <algorithm>
#include <cmath>

namespace bm {

// Rasterize an emoji string through the macOS text stack (CoreText via
// NSAttributedString), the same path SpriteKit's SKLabelNode uses for color emoji.
bool platformRenderEmojiRGBA(const std::string& utf8, int pixelSize,
                             std::vector<unsigned char>& outRGBA, int& outW, int& outH) {
    @autoreleasepool {
        NSString* str = [[NSString alloc] initWithBytes:utf8.data()
                                                 length:(NSUInteger)utf8.size()
                                               encoding:NSUTF8StringEncoding];
        if (!str || str.length == 0) return false;

        NSFont* font = [NSFont systemFontOfSize:(CGFloat)pixelSize];
        NSDictionary* attrs = @{ NSFontAttributeName: font };
        NSAttributedString* attr = [[NSAttributedString alloc] initWithString:str attributes:attrs];

        NSSize sz = [attr size];
        int w = (int)std::ceil(sz.width);
        int h = (int)std::ceil(sz.height);
        if (w <= 0 || h <= 0) return false;

        std::vector<unsigned char> buf((size_t)w * h * 4, 0);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(
            buf.data(), (size_t)w, (size_t)h, 8, (size_t)w * 4, cs,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(cs);
        if (!ctx) return false;

        NSGraphicsContext* g = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:g];
        [attr drawAtPoint:NSMakePoint(0, 0)];
        [NSGraphicsContext restoreGraphicsState];
        CGContextRelease(ctx);

        // The bitmap buffer already reads top-down (row 0 = top), matching SFML, so no
        // vertical flip is needed. Pixels are premultiplied; un-premultiply for SFML's
        // straight-alpha blending.
        outRGBA.assign((size_t)w * h * 4, 0);
        for (int y = 0; y < h; ++y) {
            const unsigned char* src = &buf[(size_t)y * w * 4];
            unsigned char* dst = &outRGBA[(size_t)y * w * 4];
            for (int x = 0; x < w; ++x) {
                unsigned char a = src[x * 4 + 3];
                if (a == 0) continue; // dst already zeroed
                dst[x * 4 + 0] = (unsigned char)std::min(255, src[x * 4 + 0] * 255 / a);
                dst[x * 4 + 1] = (unsigned char)std::min(255, src[x * 4 + 1] * 255 / a);
                dst[x * 4 + 2] = (unsigned char)std::min(255, src[x * 4 + 2] * 255 / a);
                dst[x * 4 + 3] = a;
            }
        }
        outW = w;
        outH = h;
        return true;
    }
}

} // namespace bm
