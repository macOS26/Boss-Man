import Foundation

/// Tracks whether power-pellet mode is currently active. Expiry is now
/// handled by a scheduled SKAction in GameScene; this type just holds
/// the flag that BossController and the scene's contact handler read.
@MainActor
final class PowerPelletTimer {
    private(set) var isActive = false

    func activate() {
        isActive = true
    }

    func deactivate() {
        isActive = false
    }
}
