import SpriteKit

// One launch path for both first-person bonus modes — RAYCAST 3D (DoomScene, the
// single-hit raycaster) and VOXEL 3D (VoxelScene, the overhead voxel-span view) —
// so the title screen and the level editor present either through the same code.
protocol Bonus3DScene: SKScene {
    var practiceMode: Bool { get set }
    var startingLevel: Int { get set }
}

