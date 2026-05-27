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

namespace bm {

enum class GameState { Title, Playing, Paused, GameOver, Editor };

class Game {
public:
    Game();
    void run();

private:
    void processInput();
    void update(float dt);
    void render();
    void toggleFullscreen();
    void applyLetterboxView();
    void applyFramePacing(); // vsync on Win/Linux; refresh-matched cap on macOS
    void buildLevel();
    void resetSceneAndBuild();
    void startNextLevel();
    void restartGame();
    void returnToTitle();
    void workerEnteredTile(GridPos grid);
    void checkLevelComplete();
    void bossCaughtWorker();
    void startGoldDiscMode();
    void endGoldDiscMode();
    void fireWaterGun();
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

    GameState gameState = GameState::Title;
    bool fullscreen = false;
    bool waterGunPickedUp = false;
    float goldDiscTimer = 0.0f;
    bool goldDiscActive = false;

    std::unordered_map<std::string, std::vector<std::string>> levelData;
    std::vector<std::string> officeMaps;

    sf::Clock clock;
    const sf::Time TIME_PER_UPDATE = sf::seconds(1.0f / 120.0f);
};

} // namespace bm