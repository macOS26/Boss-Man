import Foundation

/// Tracks how long the current power-pellet window has left. Tiny on
/// purpose — the actual side effects (boss colors, HUD message, etc.)
/// stay in GameScene where the cross-cutting concerns live.
@MainActor
final class PowerPelletTimer {
    private let duration: TimeInterval
    private(set) var isActive = false
    private var endsAt: TimeInterval = 0

    init(duration: TimeInterval) {
        self.duration = duration
    }

    func activate(now: TimeInterval) {
        isActive = true
        endsAt = now + duration
    }

    func deactivate() {
        isActive = false
        endsAt = 0
    }

    func hasExpired(now: TimeInterval) -> Bool {
        isActive && now >= endsAt
    }
}
