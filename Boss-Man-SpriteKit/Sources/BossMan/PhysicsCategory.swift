// Collision/contact bitmasks shared across the maze, Pete (worker), the boss,
// and every pickup type. The kit's Box2D shim takes these as the body's
// categoryBitMask / collisionBitMask / contactTestBitMask; pairs are matched
// at ContactRouter to dispatch game events.
struct PhysicsCategory {
    static let worker:       UInt32 = 1 << 0
    static let wall:         UInt32 = 1 << 1
    static let dot:          UInt32 = 1 << 2
    static let boss:         UInt32 = 1 << 3
    static let machine:      UInt32 = 1 << 4
    static let tpsBox:       UInt32 = 1 << 5
    static let goldDisc:     UInt32 = 1 << 6
    static let fish:         UInt32 = 1 << 7
    static let waterGun:     UInt32 = 1 << 8
    static let waterDroplet: UInt32 = 1 << 9
    static let waterPellet:  UInt32 = 1 << 10
}
