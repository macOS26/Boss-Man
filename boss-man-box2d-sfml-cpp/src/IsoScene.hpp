#pragma once
#include <SFML/Graphics.hpp>
#include <vector>
#include <string>
#include <memory>
#include <unordered_set>
#include <map>
#include "GridMap.hpp"
#include "Pathfinder.hpp"
#include "BossController.hpp"
#include "TravelerSpawner.hpp"
#include "WorkerController.hpp"
#include "Scene3D.hpp"
#include "RoundState.hpp"
#include "WaterGunState.hpp"
#include "HUDRenderer.hpp"
#include "MoveDirection.hpp"

namespace bm {

class SoundManager;

// ISO 3D bonus (era 1985): isometric overhead view of the office maze. PARALLEL
// projection (no vanishing point) with short raised blocks; depth = row. The maze is
// projected ONCE at build time into per-row vertex arrays; only the camera offset and
// the moving sprites change each frame. Pete is driven by the REAL WorkerController
// (2D grid physics), not the lane-walk used by the first-person modes. Ported from
// the SpriteKit IsoScene master; reuses BossController/TravelerSpawner/RoundState/
// WaterGunState exactly like the other 3D scenes.
class IsoScene : public BossControllerDelegate, public Scene3D {
public:
    IsoScene(SoundManager& sound, RoundState& state,
             const std::vector<std::string>& mapRows, int highScore);

    void update(float dt) override;
    void render(sf::RenderTarget& target) override;

    void keyDown(int sfKeyCode, bool isRepeat) override;
    void keyUp(int sfKeyCode) override;
    void mouseDown(float x, float y) override;
    void mouseDragged(float x, float y) override;
    void mouseUp() override;
    void touch(unsigned finger, float x, float y, int phase) override;

    bool isGameOver() const override { return gameOver_; }
    bool wantsExit() const override { return wantsExit_; }
    void clearExit() override { wantsExit_ = false; }
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
    static bool isDotTile(char ch) { return ch == Tile::dot || ch == Tile::hideout; }

    // MARK: - Pete (real WorkerController physics); continuous raster centre
    double px_ = 1.5, py_ = 1.5;
    double spawnPx_ = 1.5, spawnPy_ = 1.5;
    float animTime_ = 0.0f;   // monotonic clock for pickup throbs / boss pulse

    // MARK: - Isometric parallel projection (mirrors IsoScene.swift)
    double isoTW_ = 0, isoTH_ = 0, isoWH_ = 0, pVpY_ = 0;
    static constexpr double pFocal_ = 70.0;
    void setupProjection();
    double persp(double rowEdge) const;
    // Project a maze coordinate (raster col/row edge, world height y) to y-up iso space.
    sf::Vector2f proj(double colEdge, double rowEdge, double y) const;
    double perspScale(double row) const { return persp(row); }

    // MARK: - Layout (radar band at the bottom, like the other 3D scenes)
    float radarH_ = 180.f;
    float viewW_ = 0.f, viewHeight_ = 0.f;
    float viewArea() const { return viewHeight_ - radarH_; }
    // y-up iso point -> SFML y-down screen, with the per-frame world offset folded in.
    float worldOffX_ = 0.f, worldOffY_ = 0.f;   // y-up offset that pins Pete to centre
    sf::Vector2f toScreen(sf::Vector2f isoPt) const {
        return {isoPt.x + worldOffX_, viewHeight_ - (isoPt.y + worldOffY_)};
    }

    // MARK: - Static maze geometry, built once (one quad array per row for painter z).
    std::vector<sf::VertexArray> mazeRows_;        // floor/side/front/top/trim per row
    // Dots are collectable, so kept per row and rebuilt when one is taken.
    std::vector<std::vector<int>> dotColsPerRow_;  // dot columns per row
    std::vector<sf::VertexArray> dotRows_;         // projected dot-cube faces per row
    int isoDotsLeft_ = 0;
    void buildIso();
    void rebuildDotRow(int r);
    void appendDotFaces(sf::VertexArray& va, int c, int r, bool gold) const;

    // MARK: - Stationary pickups (emoji / gold / water), projected each frame.
    struct Pickup { char kind; int col, row; bool alive; float alpha; float cooldownTimer = 0.f; };
    std::vector<Pickup> pickups_;
    void buildPickups();

    // MARK: - Bosses + traveler (the REAL controllers, same as the other modes)
    GridMap gridMap_;
    std::unique_ptr<Pathfinder> pathfinder_;
    BossController bossController_;
    TravelerSpawner travelerSpawner_;
    std::unique_ptr<WorkerController> worker_;     // Pete: real 2D grid physics
    bool peteShielded_ = false;
    std::vector<std::pair<double, double>> bossGrid_;   // smooth raster centre per boss

    // Traveler smooth tracking (continuous raster col/row + facing flip).
    double travCol_ = 0, travRow_ = 0;
    bool travActive_ = false;
    float travFlip_ = 1.f;
    std::string travEmoji_;
    int travPoints_ = 0;
    bool travFacesRight_ = false;

    struct Shot { double x, y; int dirX, dirY; bool alive; float spin; };
    std::vector<Shot> shots_;

    // MARK: - Death close-up (freeze in place; iso already shows the catcher)
    bool dying_ = false;
    int deathFramesLeft_ = 0;
    static constexpr int deathFrames_ = 90;
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
    std::unordered_set<int> collected_;       // one-time stationary items taken
    std::unordered_set<int> isoDotCollected_; // dots taken

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
    std::unordered_set<int> hiddenPickups_;
    sf::VertexArray radarStaticVA_;   // floor checker + walls, batched once (one draw call)
    void buildRadar();

    // Score popups (rise + fade), same flavours as VoxelScene.
    struct MiniPop { std::string text; sf::Vector2f pos; float timer; float fontSize; };
    std::vector<MiniPop> miniPops_;   // radar copies
    std::vector<MiniPop> bigPops_;    // iso-world copies

    // MARK: - On-screen controls
    static constexpr float joystickRadius_ = 129.375f;
    static constexpr float joystickDeadzone_ = 20.f;
    static constexpr float fireButtonRadius_ = 129.375f;
    sf::Vector2f joystickCenter_{0.f, 0.f};
    sf::Vector2f fireButtonCenter_{0.f, 0.f};
    sf::Vector2f joystickThumb_{0.f, 0.f};
    bool dpadUp_ = false, dpadDown_ = false, dpadLeft_ = false, dpadRight_ = false;
    std::map<unsigned, std::string> dpadFinger_;
    bool usingTouch_ = false;
    std::string dpadWedgeAt(float x, float y) const;
    void dpadSet(unsigned finger, float x, float y, int phase);
    void applyDpad();
    void pointer(unsigned finger, float x, float y, int phase);
    bool controlsShown_ = false;

    float simAccumulator_ = 0.f;

    // MARK: - Setup
    void placeStart();
    void setupControllers();

    // MARK: - Per-frame logic
    void step();
    void moveShots();
    void fire();
    void workerDidEnterTile(GridPos grid);   // event-driven pickups (WorkerController hook)
    void collectMachine(const std::string& name, int key, int col, int row);
    void collectTPSReport(int col, int row);
    void resetCollectedMachines();
    void popPoints(int n);
    void checkBossCatch();
    GridPos workerGrid_() const;
    MoveDirection workerDir_() const;
    void startDeath(int bossIndex);
    void updateDeath();
    void finishDeath();
    void checkLevelComplete();
    void startGoldDiscMode();
    void endGoldDiscMode();
    void togglePause();
    bool dropletThreatens(GridPos d, MoveDirection dir, GridPos b) const;
    void hidePickup(int col, int row);

    // MARK: - Rendering helpers
    void placeIsoSprite(const std::string& emoji, double col, double row, double targetH,
                        sf::RenderTarget& target, double lift = 0, sf::Color color = sf::Color::White,
                        bool flipX = false);
    void drawIsoPerson(PixelPersonRenderer& r, double col, double row, double targetH,
                       sf::RenderTarget& target, bool facingLeft, bool walking,
                       MoveDirection lookDir, float walkPhase, float alpha, float extraScale);
    void drawSpritesForRow(sf::RenderTarget& target, int row);
    void drawSky(sf::RenderTarget& target);
    void drawMap(sf::RenderTarget& target);
    void drawControls(sf::RenderTarget& target);
    int deathBossIndex_ = -1;
};

} // namespace bm
