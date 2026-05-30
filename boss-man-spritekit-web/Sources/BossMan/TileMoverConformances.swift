import SpriteKit

// Wires this game's common types to the kit's reusable TileMover protocols.
// Kept out of the common GridMap/MoveDirection/PixelPerson files because the
// kit protocols only exist on wasm; the method requirements are already met, so
// these conformances are empty.
extension GridMap: TileMap {}
extension MoveDirection: TileDirection {}
extension PixelPerson: TileWalkAnimating {}
