import Foundation

// Verbatim port of boss-man-spritekit-swift/Boss-Man/PowerPelletTimer.swift.
// Tiny flag flipped on/off by the gold-disc timer; the scene reads it on
// each Pete arrival to decide whether to count a boss-touch as a capture
// (Pete eats the boss) or as a hit (Pete loses a life).
final class GoldDiscTimer {
    private(set) var isActive = false

    func activate() {
        isActive = true
    }

    func deactivate() {
        isActive = false
    }
}
