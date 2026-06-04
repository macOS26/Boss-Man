#pragma once
#include <SFML/Graphics.hpp>
#include "GridMap.hpp"
#include "Pathfinder.hpp"
#include "WorkerController.hpp"
#include "BossController.hpp"
#include "MazeRenderer.hpp"
#include "HUDRenderer.hpp"
#include "ScorePopup.hpp"
#include "SoundManager.hpp"
#include "InputController.hpp"
#include "RoundState.hpp"
#include "LevelLoader.hpp"
#include "TravelerSpawner.hpp"
#include "WaterGunState.hpp"
#include "SplashEffect.hpp"
#include "PhysicsWorld.hpp"
#include "ContactRouter.hpp"
#include "TitleScreen.hpp"
#include "LocalLeaderboard.hpp"
#include "LevelStore.hpp"
#include "LevelEditor.hpp"
#include "DoomScene.hpp"

namespace bm {

enum class GameState { Title, Playing, Paused, GameOver, Editor, Doom3D };

class Game : public BossControllerDelegate {
public:
    Game();
    void run();
    void tick(); // one frame, driven by the web requestAnimationFrame loop

    // BossControllerDelegate: per-step boss water-droplet evasion. Returns the
    // travel axis of a droplet bearing down on the boss at `bossGrid` (None when
    // no threat); the boss steps perpendicular to dodge it.
    MoveDirection dropletAxisThreatening(GridPos bossGrid) override;

private:
    // True when an active droplet on `dropletGrid` travelling `dir` shares the
    // boss's row/col, sits ahead within the dodge range, and has a wall-free path.
    bool dropletThreatens(GridPos dropletGrid, MoveDirection dir, GridPos bossGrid) const;
    GridPos dropletGridFor(sf::Vector2f pos) const;


    void processInput();
    void handleTitleHit(float x, float y); // shared by mouse-click + Android touch
    // Android touch state: a drag steers, a tap fires (in-game) or hits a title button.
    int   touchFinger = -1;
    float touchStartX = 0.f, touchStartY = 0.f;
    bool  touchMoved = false;
    bool  cursorHidden = false; // cursor hidden only during active play (desktop)
    void update(float dt);
    void render();
    void toggleFullscreen();
    void applyLetterboxView();
    void applyFramePacing(); // vsync on Win/Linux; refresh-matched cap on macOS
    // Maze follow-camera (100% = full board / no follow; 150%/200% = zoomed-in
    // camera that eases toward Pete). Ported verbatim from the SpriteKit master
    // (GameScene.setupMazeCamera / updateMazeCamera / smoothDamp).
    void setupMazeCamera();  // (re)latch zoom + view on every level build
    void updateMazeCamera(); // ease the camera toward Pete once per frame
    sf::View worldView() const; // the snapped, Pete-centred world view at the current zoom
    void buildLevel();
    void startDoom3D(int level = 1, bool practice = false); // build + enter the first-person 3D bonus (era 1993)
    void resetSceneAndBuild();
    void startNextLevel();
    void restartGame();
    void returnToTitle();
    void workerEnteredTile(GridPos grid);
    void checkLevelComplete();
    void bossCaughtWorker();
    // Full-screen game-over combo: leaderboard + on-screen keyboard name entry
    // (when the score qualifies) + PLAY/ESC. Mirrors the SpriteKit GameOverScreen.
    struct GameOverKey { sf::FloatRect rect; int kind; char ch; }; // kind 0=char 1=del 2=space 3=play 4=esc
    std::vector<GameOverKey> gameOverKeys() const;
    void drawGameOver();
    void gameOverTap(float x, float y);
    void gameOverAppendChar(char c);
    void gameOverCommit();
    void startGoldDiscMode();
    void endGoldDiscMode();
    void fireWaterGun();
    // True when a tap at logical point p should fire the water gun: any tap when the
    // fire button is hidden (a no-swipe tap fires), or a tap inside the visible
    // ring. Mirrors the SpriteKit touchesBegan/touchesEnded fire path.
    bool fireButtonHitTest(float x, float y) const;
    void handleMachine(const std::string& name, int pickupIndex);
    void collectTPSReport(int pickupIndex);
    void catchTraveler();
    void refreshHUD();
    std::vector<std::string> currentLevelRows();

    sf::RenderWindow window;
    GridMap gridMap;
    std::unique_ptr<Pathfinder> pathfinder;
    std::unique_ptr<MazeRenderer> mazeRenderer;
    HUDRenderer hud;
    SoundManager sound;
    RoundState state;
    InputController input;
    ScorePopupManager scorePopups;
    TravelerSpawner travelerSpawner;
    WaterGunState waterGun;
    SplashEffect waterSplash;
    BossController bossController;
    PhysicsWorld physicsWorld;
    ContactRouter contactRouter;
    TitleScreen titleScreen;
    LocalLeaderboard leaderboard;
    LevelStore levelStore;
    LevelEditor editor{levelStore};
    std::unique_ptr<WorkerController> worker;
    std::unique_ptr<DoomScene> doomScene; // first-person 3D bonus (era 1993)

    GameState gameState = GameState::Title;
    GameState prevTickState_ = GameState::Playing;   // != Title so the title renders on entry (1 fps idle)
    bool fullscreen = false;

    // Maze camera state. `cameraZoom` is the active zoom percent latched at build
    // (100 = no follow). `camPos`/`camVel` are the SmoothDamp target + velocity in
    // world (logical pixel) coords; `camPosValid` stands in for the SpriteKit
    // `camPos: CGPoint?` (nil on the first frame after a build).
    int cameraZoom = 100;
    bool camPosValid = false;
    sf::Vector2f camPos{0.f, 0.f};
    sf::Vector2f camVel{0.f, 0.f};
    // The unscaled, letterboxed base view (full board / HUD layer). Cached by
    // applyLetterboxView so render() can restore it for the screen-fixed overlays
    // without re-querying the backing scale every frame.
    sf::View baseView;
    bool waterGunPickedUp = false;
    float goldDiscTimer = 0.0f;
    bool goldDiscActive = false;

    std::string goName;          // name typed on the game-over combo screen
    bool goQualified = false;    // score made the top 10 (and not practice mode)
    bool goCommitted = false;    // name recorded to the leaderboard already

    std::unordered_map<std::string, std::vector<std::string>> levelData;
    std::vector<std::string> officeMaps;

    sf::Clock clock;       // per-frame dt (restarted every tick)
    sf::Clock animClock;   // monotonic since launch; drives render-time animation
    sf::Time timeSinceLastUpdate;
    const sf::Time TIME_PER_UPDATE = sf::seconds(1.0f / 120.0f);
};

} // namespace bm