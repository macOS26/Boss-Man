import SpriteKit
import KitABI

// =============================================================================
// GameplayKit shim — most surveyed games import GameplayKit (Space-Bar,
// FrogMan, AsteroidZ) but never use any GK types. This module exists so
// `import GameplayKit` resolves; the small surface below covers what does
// get used in the wild (GKRandom for shuffling, GKScene for .sks bundles).
// =============================================================================

// Random — wraps wasi-libc `rand()`. Not cryptographic; fine for game RNG.
public protocol GKRandom {
    func nextInt() -> Int
    func nextInt(upperBound: Int) -> Int
    func nextUniform() -> Float
    func nextBool() -> Bool
}

public class GKRandomSource: GKRandom {
    public init() {}
    public init(seed: UInt64) {}
    public static let sharedRandom = GKRandomSource()
    public func nextInt() -> Int { Int(sb64_rand()) }
    public func nextInt(upperBound u: Int) -> Int { u <= 0 ? 0 : abs(nextInt()) % u }
    public func nextUniform() -> Float { Float(nextInt(upperBound: 0x10000)) / 65535.0 }
    public func nextBool() -> Bool { (nextInt() & 1) == 1 }
    public func arrayByShufflingObjects(in array: [Any]) -> [Any] {
        var a = array
        for i in stride(from: a.count - 1, through: 1, by: -1) {
            a.swapAt(i, nextInt(upperBound: i + 1))
        }
        return a
    }
}

public final class GKMersenneTwisterRandomSource: GKRandomSource {}
public final class GKLinearCongruentialRandomSource: GKRandomSource {}
public final class GKARC4RandomSource: GKRandomSource {}

public class GKRandomDistribution: GKRandom {
    public let lowestValue: Int
    public let highestValue: Int
    public init(lowestValue l: Int, highestValue h: Int) {
        lowestValue = l
        highestValue = h
    }
    public init(randomSource s: GKRandom, lowestValue l: Int, highestValue h: Int) {
        lowestValue = l
        highestValue = h
    }
    public func nextInt() -> Int { lowestValue + abs(Int(sb64_rand())) % max(highestValue - lowestValue + 1, 1) }
    public func nextInt(upperBound u: Int) -> Int { abs(Int(sb64_rand())) % max(u, 1) }
    public func nextUniform() -> Float { Float(sb64_rand() & 0xFFFF) / 65535 }
    public func nextBool() -> Bool { (sb64_rand() & 1) == 1 }
    public static func d6() -> GKRandomDistribution { GKRandomDistribution(lowestValue: 1, highestValue: 6) }
    public static func d20() -> GKRandomDistribution { GKRandomDistribution(lowestValue: 1, highestValue: 20) }
}

public final class GKShuffledDistribution: GKRandomDistribution {}
public final class GKGaussianDistribution: GKRandomDistribution {}

// =============================================================================
// GKScene — wraps SKScene loaded from .sks files. Compile-only on web (no
// .sks parser); rootNode is an empty SKScene with userData attached.
// =============================================================================
public final class GKScene {
    public var rootNode: SKScene?
    public var entities: [GKEntity] = []
    public var graphs: [String: AnyObject] = [:]
    public init() {}
    public static func from(fileNamed name: String) -> GKScene? { GKScene() }
}

// =============================================================================
// GKEntity / GKComponent / GKComponentSystem — empty bones for the ECS pattern.
// =============================================================================
open class GKComponent {
    public weak var entity: GKEntity?
    public init() {}
    open func update(deltaTime seconds: TimeInterval) {}
    open func didAddToEntity() {}
    open func willRemoveFromEntity() {}
}

public final class GKEntity {
    public private(set) var components: [GKComponent] = []
    public init() {}
    public func addComponent(_ c: GKComponent) {
        c.entity = self
        components.append(c)
        c.didAddToEntity()
    }
    public func removeComponent(ofType t: GKComponent.Type) {
        for (i, c) in components.enumerated() where type(of: c) == t {
            c.willRemoveFromEntity()
            components.remove(at: i)
            break
        }
    }
    public func component<T: GKComponent>(ofType t: T.Type) -> T? { components.first { $0 is T } as? T }
    public func update(deltaTime seconds: TimeInterval) { for c in components { c.update(deltaTime: seconds) } }
}

public final class GKComponentSystem<T: GKComponent> {
    public init(componentClass: T.Type) {}
    public var components: [T] = []
    public func addComponent(_ c: T) { components.append(c) }
    public func addComponent(foundIn entity: GKEntity) { if let c = entity.component(ofType: T.self) { components.append(c) } }
    public func removeComponent(_ c: T) { components.removeAll { $0 === c } }
    public func update(deltaTime: TimeInterval) { for c in components { c.update(deltaTime: deltaTime) } }
}


