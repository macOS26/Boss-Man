import Foundation

@MainActor
final class WaterGunTimer {
    private(set) var isActive = false
    private(set) var pelletsRemaining: Int = 0
    private let maxPellets = 8

    func activate() {
        isActive = true
        pelletsRemaining = maxPellets
    }

    func deactivate() {
        isActive = false
        pelletsRemaining = 0
    }

    func consumePellet() -> Bool {
        guard isActive, pelletsRemaining > 0 else { return false }
        pelletsRemaining -= 1
        if pelletsRemaining == 0 { deactivate() }
        return true
    }
}