import Foundation

@MainActor
final class GoldDiscTimer {
    private(set) var isActive = false

    func activate() {
        isActive = true
    }

    func deactivate() {
        isActive = false
    }
}
