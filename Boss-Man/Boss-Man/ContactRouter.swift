import SpriteKit

@MainActor
final class ContactRouter: NSObject, SKPhysicsContactDelegate {
    var shouldIgnoreContact: () -> Bool = { false }

    var onBossTouchedWorker: ((SKNode?) -> Void)?
    var onGoldDiscTouched: ((SKNode?) -> Void)?
    var onWaterGunTouchedWorker: ((SKNode?) -> Void)?
    var onDropletTouchedBoss: ((SKPhysicsBody, SKPhysicsBody) -> Void)?
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
        if let pellet = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.goldDisc }) {
            onGoldDiscTouched?(pellet.node)
        }
        if let waterGunNode = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.waterGun }), hasWorker {
            onWaterGunTouchedWorker?(waterGunNode.node)
        }
        if let dropletBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.waterDroplet }),
           let bossBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.boss }) {
            onDropletTouchedBoss?(dropletBody, bossBody)
        }
        if let dropletBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.waterDroplet }),
           bodies.contains(where: { $0.categoryBitMask == PhysicsCategory.wall }) {
            dropletBody.node?.removeFromParent()
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
