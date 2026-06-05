#pragma once
#include <SFML/Graphics.hpp>

namespace bm {

// The interface both first-person bonus scenes implement — RAYCAST 3D (DoomScene,
// the single-hit raycaster) and VOXEL 3D (VoxelScene, the overhead voxel-span view) —
// so Game drives whichever one the era selected through one polymorphic pointer.
// This is the C++ analog of the Swift Bonus3DScene protocol.
class Scene3D {
public:
    virtual ~Scene3D() = default;
    virtual void update(float dt) = 0;
    virtual void render(sf::RenderTarget& target) = 0;
    virtual void keyDown(int sfKeyCode, bool isRepeat) = 0;
    virtual void keyUp(int sfKeyCode) = 0;
    virtual void mouseDown(float x, float y) = 0;
    virtual void mouseDragged(float x, float y) = 0;
    virtual void mouseUp() = 0;
    virtual void touch(unsigned finger, float x, float y, int phase) = 0;
    virtual bool isGameOver() const = 0;
    virtual bool wantsExit() const = 0;
    virtual void clearExit() = 0;
};

} // namespace bm
