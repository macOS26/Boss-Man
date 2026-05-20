import SpriteKit

/// Implements SKPhysicsContactDelegate on behalf of GameScene so the
/// scene itself doesn't have to. Each category-pair handler is a
/// closure GameScene assigns in didMove — keeps physics dispatch out
/// of the scene class without forcing it into an extension.
@MainActor
final class ContactRouter: NSObject, SKPhysicsContactDelegate {
    /// Returning true short-circuits the entire dispatch — used to drop
    /// contacts during game-over.
    var shouldIgnoreContact: () -> Bool = { false }

    var onBossTouchedWorker: ((SKNode?) -> Void)?
    var onPowerPelletTouched: ((SKNode?) -> Void)?
    var onMachineTouchedWorker: ((SKPhysicsBody, String) -> Void)?
    var onTpsBoxTouchedWorker: (() -> Void)?
    var onFishTouchedWorker: ((SKNode?) -> Void)?

    func didBegin(_ contact: SKPhysicsContact) {
        guard !shouldIgnoreContact() else { return }
        let bodies = [contact.bodyA, contact.bodyB]
        let hasWorker = bodies.contains { $0.categoryBitMask == PhysicsCategory.worker }

        if let bossBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.boss }), hasWorker {
            onBossTouchedWorker?(bossBody.node)
        }
        if let pellet = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.powerPellet }) {
            onPowerPelletTouched?(pellet.node)
        }
        if let machineBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.machine }),
           let name = machineBody.node?.name {
            onMachineTouchedWorker?(machineBody, name)
        }
        if bodies.contains(where: { $0.categoryBitMask == PhysicsCategory.tpsBox }), hasWorker {
            onTpsBoxTouchedWorker?()
        }
        if let fishBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.fish }), hasWorker {
            onFishTouchedWorker?(fishBody.node)
        }
    }
}
