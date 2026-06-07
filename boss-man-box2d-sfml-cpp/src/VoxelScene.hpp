#pragma once
#include <SFML/Graphics.hpp>
#include <vector>
#include <string>
#include <memory>
#include <unordered_set>
#include <unordered_map>
#include <map>
#include "GridMap.hpp"
#include "Pathfinder.hpp"
#include "BossController.hpp"
#include "TravelerSpawner.hpp"
#include "Scene3D.hpp"
#include "RoundState.hpp"
#include "WaterGunState.hpp"
#include "HUDRenderer.hpp"
#include "MoveDirection.hpp"

namespace bm {

class SoundManager;

// First-person 3D "DOOM" mode (era 1993): the office maze (level 1) rendered with a
// Wolfenstein-style DDA raycaster for the walls, a blended sunset sky, and
// billboarded game sprites (pellets, gold discs, bosses) standing in the corridors.
// The camera trails behind Pete so you see him walking ahead of you; a top-down
// radar sits at the bottom. Ported verbatim from the SpriteKit VoxelScene master.
//
// Reuses the REAL game systems: BossController (speed/square+smooth, flee/splash/
// capture/respawn), RoundState, WaterGunState, GoldDiscTimer (via goldDiscTimer),
// SoundManager, ScorePopup, PixelPersonRenderer. Only the raycaster renderer and the
// first-person/tank input are mode-specific.
class VoxelScene : public BossControllerDelegate, public Scene3D {
public:
    VoxelScene(SoundManager& sound, RoundState& state,
              const std::vector<std::string>& mapRows, int highScore);

    // Per-frame: advance the simulation by a fixed 1/60 step then draw. `dt` is the
    // accumulated wall-clock slice; the tank step + boss advance use the fixed step.
    void update(float dt);
    void render(sf::RenderTarget& target);

    // Keyboard / mouse routed from Game::processInput (logical letterbox coords).
    void keyDown(int sfKeyCode, bool isRepeat);
    void keyUp(int sfKeyCode);
    void mouseDown(float x, float y);
    void mouseDragged(float x, float y);
    void mouseUp();
    // Multi-touch D-pad: route every finger (phase 0 down / 1 move / 2 up) so two
    // fingers can press two wedges (forward + a turn) at once on a phone.
    void touch(unsigned finger, float x, float y, int phase);

    // True once Pete has run out of lives: Game tears the scene down and shows the
    // shared game-over combo screen (no name entry, like the 2D modes).
    bool isGameOver() const { return gameOver_; }
    bool wantsExit() const { return wantsExit_; }
    void clearExit() { wantsExit_ = false; }
    bool wantsNextLevel() const override { return wantsNextLevel_; }
    int nextLevelIndex() const override { return nextLevel_; }
    void clearNextLevel() override { wantsNextLevel_ = false; }

    // BossControllerDelegate: per-step boss water-pellet evasion (same as 2D modes).
    MoveDirection dropletAxisThreatening(GridPos bossGrid) override;

private:
    SoundManager& sound_;
    RoundState& state_;

    // MARK: - Maze (level 1, raster top-down: y increases down the rows array)
    std::vector<std::string> map_;
    int rowsCount_ = 0, colsCount_ = 0;
    char tileAtRaster(int c, int r) const;
    bool isWall(double x, double y) const;
    bool open(int c, int r) const;
    static double cardinal(int dx, int dy);

    // MARK: - Pete + chase camera (grid coords)
    double px_ = 1.5, py_ = 1.5, angle_ = 0.0;
    int moveDirX_ = 1, moveDirY_ = 0;       // current lane direction (cardinal)
    bool wantDirSet_ = false; int wantDirX_ = 0, wantDirY_ = 0; // queued junction turn
    bool pendingSecondTurn_ = false;
    std::string peteDirName_ = "PETE";
    double targetAngle_ = 0.0;
    double spawnPx_ = 1.5, spawnPy_ = 1.5;
    double camX_ = 0.0, camY_ = 0.0;
    double bob_ = 0.0;       // head-bob phase (advances only while moving)
    double peteWalkPhase_ = 0.0; // Pete leg/arm walk clock, in seconds, advances only while moving
    float animTime_ = 0.0f;  // monotonic clock for pickup throbs (always advances)
    static constexpr double camBack_ = 0.65;

    double pelletWorldH() const override { return 0.15; }

    // MARK: - Layout / projection (VOXEL: wide FOV + raised, tilted-down camera, mirroring VoxelScene.swift)
    static constexpr int columns_ = 220;           // Scene3D default (DoomScene narrows to 200)
    static constexpr double planeScale_ = 1.2;     // tan(fov/2): wide ~100° FOV so a big swath of maze shows
    static constexpr double eyeHeight_ = 0.7;      // raised camera -> looks down
    static constexpr double wallHeightScale_ = 0.5; // short walls -> tops sit below the horizon
    static constexpr double maxVoxelDist_ = 40.0;  // match Swift wallFar
    float radarH_ = 180.f;
    float viewW_ = 0.f, viewHeight_ = 0.f; // window logical width/height
    float viewH() const { return viewHeight_ - radarH_; }
    float viewMidY() const { return radarH_ + viewH() * 0.70f; } // horizon (SK y-up)
    std::vector<double> zbuf_;

    // MARK: - Billboards (pooled: built once, projected each frame)
    struct Billboard {
        int kind;        // tile char of the pickup this billboard represents
        double worldH;   // world height for the perspective projection
        double x, y;     // grid centre (raster top-down)
        bool alive;
        float alpha;            // 1.0 normally, 0.55 when a machine is grayed
        float cooldownTimer = 0.f; // > 0 while dimmed; restores to 1.0 when it reaches 0
        // Per-frame projection output (filled by projectSprites).
        bool visible = false;
        float screenX = 0.f, scale = 1.f, floorY = 0.f, depthZ = 0.f;
    };
    std::vector<Billboard> billboards_;

    // MARK: - Bosses (the REAL BossController, index-based in this port)
    GridMap gridMap_;
    std::unique_ptr<Pathfinder> pathfinder_;
    BossController bossController_;
    bool peteShielded_ = false;

    // MARK: - Traveler (the fish/treat that walks the maze, same spawner as 2D)
    TravelerSpawner travelerSpawner_;

    struct Shot {
        double x, y;
        int dirX, dirY;
        bool alive;
        float spin; // specular orbit phase for the 3D + radar visuals
        // Per-frame projection output (3D view).
        bool visible = false;
        float screenX = 0.f, scale = 1.f, floorY = 0.f, depthZ = 0.f;
    };
    std::vector<Shot> shots_;

    // MARK: - Death close-up (reuse the REAL catching boss)
    bool dying_ = false;
    int deathFramesLeft_ = 0;
    int deathBossIndex_ = -1;
    static constexpr int deathFrames_ = 90; // 1.5s at 60fps
    bool gameOver_ = false;
    bool wantsExit_ = false;
    bool wantsNextLevel_ = false;
    int nextLevel_ = 0;

    // MARK: - Gold disc / report / pickup bookkeeping
    WaterGunState waterGun_;
    bool waterGunPickedUp_ = false;
    double frightenSecondsLeft_ = 0.0;
    static constexpr double goldDiscDuration_ = 20.0;
    bool goldDiscActive_ = false;
    bool onBrownBox_ = false;
    std::unordered_set<int> collected_; // mapKey of one-time stationary items taken

    // MARK: - HUD
    HUDRenderer hud_;
    int highScore_ = 0;
    bool isUserPaused_ = false;
    void refreshHUD();

    // MARK: - Minimap (the real 2D level, centered at the bottom)
    static constexpr float mapCell_ = 32.f;
    float mapScale_ = 1.f;
    sf::Vector2f mapOrigin_{0.f, 0.f};
    sf::Vector2f mapLocal(double x, double y) const;
    int mapKey(int c, int r) const { return r * colsCount_ + c; }
    std::unordered_set<int> hiddenPickups_; // mapKey of collected/hidden minimap pickups

    // Score popups (rise + fade over 0.7s). Two flavours, matching the SpriteKit
    // master: a big one over Pete in the 3D corridor (fontSize 54) and a smaller
    // one on Pete in the radar (fontSize 40). Both rise 42px and fade out.
    struct MiniPop { std::string text; sf::Vector2f pos; float timer; float fontSize; };
    std::vector<MiniPop> miniPops_;   // radar copies (drawn inside the map panel)
    std::vector<MiniPop> bigPops_;    // 3D-corridor copies (drawn in the main view)

    // MARK: - On-screen controls
    static constexpr float joystickRadius_ = 129.375f;
    static constexpr float joystickKnobRadius_ = 51.75f;
    static constexpr float joystickDeadzone_ = 20.f;   // D-pad centre hole + input deadzone
    static constexpr float fireButtonRadius_ = 129.375f;
    sf::Vector2f joystickCenter_{0.f, 0.f};
    sf::Vector2f fireButtonCenter_{0.f, 0.f};
    sf::Vector2f joystickThumb_{0.f, 0.f};
    bool joystickActive_ = false;
    // X-pattern D-pad: which wedges are lit (diagonals light two -> forward + a turn).
    bool dpadUp_ = false, dpadDown_ = false, dpadLeft_ = false, dpadRight_ = false;
    std::map<unsigned, std::string> dpadFinger_;   // active finger id -> wedge (up/down/left/right)
    bool usingTouch_ = false;   // a real finger arrived: ignore the synthetic mouse pointer (phones send both)
    std::string dpadWedgeAt(float x, float y) const;
    void dpadSet(unsigned finger, float x, float y, int phase);   // update one finger, apply one-shot turns
    void applyDpad();   // recompute held forward + highlight from all fingers
    void pointer(unsigned finger, float x, float y, int phase);   // shared mouse/touch body
    bool controlsShown_ = false;

    // MARK: - Input state (held keys, SFML key codes)
    bool pressUp_ = false, pressDown_ = false;

    // The SpriteKit VoxelScene runs at a fixed 60fps and advances the tank step +
    // BossController by exactly 1/60 each frame. The C++ host ticks update() at
    // 120Hz, so we accumulate real time and fire the 1/60 sim step at 60Hz to keep
    // the verbatim 60fps tuning frame-rate independent.
    float simAccumulator_ = 0.f;

    // MARK: - Setup
    void placeStart();
    void setupBossController();
    void buildBillboards();
    void buildMap();

    // MARK: - Per-frame logic (ported from VoxelScene.step / render / projectSprites)
    void step();
    void moveShots();
    void fire();
    void collectStationary();
    void collectMachine(const std::string& name, int key, int col, int row);
    void collectTPSReport();
    void resetCollectedMachines();
    void popPoints(int n);
    void checkBossCatch();
    GridPos workerGrid_() const;       // Pete reported in GridMap bottom-up coords
    MoveDirection workerDir_() const;
    void startDeath(int bossIndex);
    void updateDeath();
    void finishDeath();
    void startGoldDiscMode();
    void endGoldDiscMode();
    void togglePause();
    void checkLevelComplete3D();
    bool dropletThreatens(GridPos d, MoveDirection dir, GridPos b) const;

    // MARK: - Rendering helpers
    void renderWalls(sf::RenderTarget& target, double dirX, double dirY,
                     double planeX, double planeY);
    // Painter's voxel walls (boxy 3D): coalesced front faces + per-cell flat tops, sorted far->near.
    void renderVoxelWalls(sf::RenderTarget& target, double dirX, double dirY,
                          double planeX, double planeY);
    void projectSprites(double dirX, double dirY, double planeX, double planeY);
    void drawBillboardSprite(sf::RenderTarget& target, const Billboard& b);
    void drawShotSprite(sf::RenderTarget& target, const Shot& s);
    void drawBossBillboard(sf::RenderTarget& target, int bossIndex);
    void drawSky(sf::RenderTarget& target);
    void drawFloor(sf::RenderTarget& target, double dirX, double dirY,
                   double planeX, double planeY);
    void drawMap(sf::RenderTarget& target);
    void drawControls(sf::RenderTarget& target);

    // Boss smooth world position (raster top-down grid coords) per entity, captured
    // each frame from boss.pixelPos before any draw-time mutation.
    std::vector<std::pair<double, double>> bossGrid_;

    // Per-frame boss billboard projection (filled by projectSprites, consumed by the
    // depth-sorted draw + drawBossBillboard).
    struct BossProj { bool visible; float screenX, scale, floorY, targetH, depthZ; };
    std::vector<BossProj> bossProj_;

    // Convert a SpriteKit-style (y-up, 0 at bottom) screen Y to the SFML target Y.
    float screenY(float skY) const { return viewHeight_ - skY; }
};

} // namespace bm
