#include "Game.hpp"
#include "EmojiText.hpp"
#include "Assets.hpp"
#include "MacWindow.hpp"
#include "UiScale.hpp"
#include "Settings.hpp"
#include <algorithm>
#include <cstdlib>
#include <cmath>

namespace bm {

namespace {
// The game-over screen mirrors the SpriteKit master: Marker Felt Wide for the
// title / score / prompts / keys (bold), Menlo Bold for the typed name and the
// leaderboard rows (body).
sf::Font& gameOverFont(bool bold) {
    static sf::Font wide, menlo;
    static bool wideLoaded = false, menloLoaded = false;
    if (bold) {
        if (!wideLoaded) wideLoaded = loadFont(wide, "assets/fonts/MarkerFelt-Wide.ttf");
        return wide;
    }
    if (!menloLoaded) menloLoaded = loadFont(menlo, "assets/fonts/Menlo-Bold.ttf");
    return menlo;
}
// halign: 0 left, 1 center, 2 right (about x). Rasterizes at uiScale and
// counter-scales so text stays crisp on Retina. Returns the logical text width.
float goText(sf::RenderTarget& t, const std::string& s, float sizePx, sf::Color color,
             float x, float centerY, int halign, bool bold = true) {
    float dpi = uiScale();
    sf::Text txt;
    txt.setFont(gameOverFont(bold));
    txt.setString(s);
    txt.setCharacterSize((unsigned)(sizePx * dpi));
    txt.setFillColor(color);
    auto lb = txt.getLocalBounds();
    float ox = (halign == 0) ? lb.left : (halign == 2 ? lb.left + lb.width : lb.left + lb.width / 2.f);
    txt.setOrigin(ox, lb.top + lb.height / 2.f);
    txt.setScale(1.f / dpi, 1.f / dpi);
    txt.setPosition(x, centerY);
    t.draw(txt);
    return lb.width / dpi;
}
} // namespace

Game::Game()
    : window(sf::VideoMode(WINDOW_WIDTH, WINDOW_HEIGHT), WINDOW_TITLE,
             sf::Style::Titlebar | sf::Style::Close,
             sf::ContextSettings(0, 0, 8)),  // antialiasing for soft shape edges
      gridMap(TILE_SIZE) {
    applyFramePacing();
    window.setKeyRepeatEnabled(false);
    applyLetterboxView();
#ifndef __APPLE__
    // Window/taskbar icon on Windows and Linux (macOS uses the .app bundle icon).
    {
        sf::Image icon;
        if (loadImage(icon, "resources/icons/AppIcon.png"))
            window.setIcon(icon.getSize().x, icon.getSize().y, icon.getPixelsPtr());
    }
#endif
#ifdef __APPLE__
    enableNativeFullscreen(window.getSystemHandle()); // green button does real fullscreen
    uiScale() = windowBackingScale(window.getSystemHandle()); // crisp text on Retina
#endif
    bossController.setSound(&sound);
    bossController.setDelegate(this); // boss water-droplet dodge queries the game
    travelerSpawner.setSound(&sound);
    levelData = LevelLoader::loadFromAsset();
    levelStore.setBundled(levelData);
    state.loadHighScore();
    leaderboard.load();
}

void Game::toggleFullscreen() {
#ifdef __APPLE__
    // Use macOS-native fullscreen (same as the green button); the Resized event
    // re-applies the letterbox view.
    toggleNativeFullscreen(window.getSystemHandle());
#else
    fullscreen = !fullscreen;
    sf::ContextSettings settings(0, 0, 8); // keep antialiasing
    if (fullscreen) {
        window.create(sf::VideoMode::getDesktopMode(), WINDOW_TITLE,
                      sf::Style::Fullscreen, settings);
    } else {
        window.create(sf::VideoMode(WINDOW_WIDTH, WINDOW_HEIGHT), WINDOW_TITLE,
                      sf::Style::Titlebar | sf::Style::Close, settings);
    }
    applyFramePacing();
    window.setKeyRepeatEnabled(false);
    applyLetterboxView();
#endif
}

// Map the fixed 1184x644 logical layout onto the window, letterboxed to preserve
// aspect ratio. All rendering uses logical coordinates, so this is the only place
// that needs to know the real window size.
void Game::applyLetterboxView() {
    sf::Vector2u ws = window.getSize();
#ifdef __APPLE__
    uiScale() = windowBackingScale(window.getSystemHandle());
#else
    // Windows/Linux: getSize() is physical pixels (DPI-aware), so the logical->
    // pixel scale is the letterbox fit. Rasterize text at that density for crisp
    // glyphs at any window size, including fullscreen.
    if (ws.x > 0 && ws.y > 0)
        uiScale() = std::min((float)ws.x / WINDOW_WIDTH, (float)ws.y / WINDOW_HEIGHT);
#endif
    float winAspect = (float)ws.x / (float)ws.y;
    float gameAspect = (float)WINDOW_WIDTH / (float)WINDOW_HEIGHT;
    sf::FloatRect vp(0, 0, 1, 1);
    if (winAspect > gameAspect) {
        float w = gameAspect / winAspect;
        vp = sf::FloatRect((1 - w) / 2.f, 0.f, w, 1.f);
    } else if (winAspect < gameAspect) {
        float h = winAspect / gameAspect;
        vp = sf::FloatRect(0.f, (1 - h) / 2.f, 1.f, h);
    }
    sf::View view(sf::FloatRect(0, 0, (float)WINDOW_WIDTH, (float)WINDOW_HEIGHT));
    view.setViewport(vp);
    window.setView(view);
}

void Game::applyFramePacing() {
#ifdef __APPLE__
    // SFML's vsync doesn't survive the macOS native-fullscreen transition, so we
    // pace via the frame limiter at the display's actual refresh — 120 on a
    // ProMotion/120Hz panel, 60 otherwise. Never forces 120 on a 60Hz screen.
    window.setFramerateLimit((unsigned)displayRefreshHz(window.getSystemHandle()));
#else
    // vsync matches the monitor's refresh and is reliable on Windows/Linux.
    window.setVerticalSyncEnabled(true);
#endif
}

void Game::run() {
    while (window.isOpen()) tick();
}

void Game::tick() {
    sf::Time dt = clock.restart();
    timeSinceLastUpdate += dt;
    while (timeSinceLastUpdate >= TIME_PER_UPDATE) {
        processInput();
        update(TIME_PER_UPDATE.asSeconds());
        timeSinceLastUpdate -= TIME_PER_UPDATE;
    }
    render();
}

std::vector<std::string> Game::currentLevelRows() {
    int idx = (state.level - 1) % (int)levelNames().size();
    std::string name = levelNames()[idx];
    // LevelStore returns custom edited rows (from the level editor) when present,
    // otherwise the bundled level — so edits show up immediately in play/practice.
    auto rows = levelStore.loadLevel(name);
    if (!rows.empty()) return rows;
    if (levelData.count(name)) return levelData[name];
    return {};
}

void Game::buildLevel() {
    auto rows = currentLevelRows();
    if (rows.empty()) return;

    // Pin the maze to the bottom (HUD on top, small gap between), matching the
    // SpriteKit 16:9 scene layout.
    gridMap.yOffset = WINDOW_HEIGHT - GRID_ROWS * (int)TILE_SIZE;
    gridMap.setRows(rows);
    pathfinder = std::make_unique<Pathfinder>(gridMap);
    mazeRenderer = std::make_unique<MazeRenderer>(gridMap);
    mazeRenderer->cubicleColor = CUBICLE_COLORS[(state.level - 1) % 12];
    state.dotCount = mazeRenderer->build();
    state.goldDiscCount = mazeRenderer->placedGoldDiscs;

    GridPos spawn = (mazeRenderer->workerSpawnFromMap.x >= 0)
        ? mazeRenderer->workerSpawnFromMap : WORKER_SPAWN;

    worker = std::make_unique<WorkerController>(spawn, gridMap);
    worker->applySpawnShield();
    worker->lastTileCallback = [this](GridPos g) { workerEnteredTile(g); };

    bossController.spawn(state.level, gridMap, *pathfinder, mazeRenderer->bossSpawnsFromMap);

    // Physics
    physicsWorld.clear();
    std::vector<sf::Vector2f> wallCenters;
    for (int rowIndex = 0; rowIndex < (int)gridMap.rows.size(); ++rowIndex) {
        auto& row = gridMap.rows[rowIndex];
        for (int col = 0; col < (int)row.size(); ++col) {
            if (row[col] == Tile::wall) {
                int gridY = (int)gridMap.rows.size() - 1 - rowIndex;
                wallCenters.push_back(gridMap.pointFor({col, gridY}));
            }
        }
    }
    physicsWorld.createWallBody(wallCenters, TILE_SIZE);

    auto wpos = gridMap.pointFor(spawn);
    physicsWorld.workerBody = physicsWorld.createDynamicCircle(
        wpos.x, wpos.y, 10, PhysicsCat::WORKER,
        PhysicsCat::BOSS | PhysicsCat::MACHINE | PhysicsCat::TPS_BOX |
        PhysicsCat::GOLD_DISC | PhysicsCat::WATER_GUN | PhysicsCat::WATER_PELLET);

    for (auto& boss : bossController.entities) {
        auto bpos = gridMap.pointFor(boss.spawn);
        physicsWorld.bossBodies.push_back(physicsWorld.createKinematicCircle(
            bpos.x, bpos.y, 10, PhysicsCat::BOSS,
            PhysicsCat::WORKER | PhysicsCat::WATER_DROPLET));
    }

    for (auto& p : mazeRenderer->pickups) {
        uint16 cat = 0, mask = 0;
        if (p.type == Tile::goldDisc) { cat = PhysicsCat::GOLD_DISC; mask = PhysicsCat::WORKER; }
        else if (p.type == Tile::waterGun) { cat = PhysicsCat::WATER_GUN; mask = PhysicsCat::WORKER; }
        else if (p.type == Tile::waterPellet) { cat = PhysicsCat::WATER_PELLET; mask = PhysicsCat::WORKER; }
        else if (p.type == Tile::brownBox) { cat = PhysicsCat::TPS_BOX; mask = PhysicsCat::WORKER; }
        else { cat = PhysicsCat::MACHINE; mask = PhysicsCat::WORKER; }
        if (cat != 0)
            physicsWorld.pickupBodies.push_back(physicsWorld.createStaticCircle(
                p.pixelPos.x, p.pixelPos.y, 11, cat, mask));
    }

    physicsWorld.world.SetContactListener(&contactRouter);

    travelerSpawner.reset();
    travelerSpawner.scheduleVisits(state.level, *pathfinder);

    bool isMIB = (state.level % 12 == 0);
    sound.startBackgroundMusic(isMIB);
    refreshHUD();
}

void Game::handleTitleHit(float x, float y) {
    switch (titleScreen.hitTest(x, y)) {
    case TitleScreen::Hit::Play:       input.pRequested = true; break;
    case TitleScreen::Hit::Editor:     input.eRequested = true; break;
    case TitleScreen::Hit::BossTracks: Settings::setBossTracksSquare(!Settings::bossTracksSquare()); break;
    case TitleScreen::Hit::WaterGun:
        // Cycle Left -> Right -> Hide -> Left (two bools: left + hide).
        if (Settings::waterGunHide()) {
            Settings::setWaterGunHide(false);
            Settings::setWaterGunLeft(true);
        } else if (Settings::waterGunLeft()) {
            Settings::setWaterGunLeft(false);
        } else {
            Settings::setWaterGunHide(true);
        }
        break;
    case TitleScreen::Hit::Fullscreen:
    case TitleScreen::Hit::Window:     input.fullscreenToggleRequested = true; break;
    case TitleScreen::Hit::None:       break;
    }
}

void Game::processInput() {
    sf::Event event;
    while (window.pollEvent(event)) {
        if (event.type == sf::Event::Closed) {
            window.close();
            return;
        }
        if (event.type == sf::Event::Resized) {
            applyLetterboxView(); // follow native-fullscreen / size changes
            applyFramePacing();   // re-match refresh (e.g. moved to another monitor)
            continue;
        }
        // The editor handles its own raw mouse/keyboard (palette, painting,
        // ⌘ shortcuts), so route events straight to it and skip InputController.
        if (gameState == GameState::Editor) {
            editor.handleEvent(event, window);
            continue;
        }
        // Game-over combo screen: taps hit the on-screen keyboard / PLAY / ESC;
        // physical keys type the name (when the score qualifies), Enter (or P when
        // not typing) is PLAY, Escape is ESC. Deferred via input flags like the title.
        if (gameState == GameState::GameOver) {
            if (event.type == sf::Event::MouseButtonPressed && event.mouseButton.button == sf::Mouse::Left) {
                sf::Vector2f p = window.mapPixelToCoords(sf::Vector2i(event.mouseButton.x, event.mouseButton.y));
                gameOverTap(p.x, p.y);
            } else if (event.type == sf::Event::TouchEnded) {
                sf::Vector2f p = window.mapPixelToCoords(sf::Vector2i((int)event.touch.x, (int)event.touch.y));
                gameOverTap(p.x, p.y);
            } else if (event.type == sf::Event::KeyPressed) {
                int code = event.key.code;
                if (code == sf::Keyboard::Enter || (!goQualified && code == sf::Keyboard::P)) {
                    gameOverCommit(); input.pRequested = true;
                } else if (code == sf::Keyboard::Escape) {
                    gameOverCommit(); input.escapeRequested = true;
                } else if (goQualified && code == sf::Keyboard::Backspace) {
                    if (!goName.empty()) goName.pop_back();
                } else if (goQualified && code >= sf::Keyboard::A && code <= sf::Keyboard::Z) {
                    gameOverAppendChar((char)('A' + (code - sf::Keyboard::A)));
                } else if (goQualified && code >= sf::Keyboard::Num0 && code <= sf::Keyboard::Num9) {
                    gameOverAppendChar((char)('0' + (code - sf::Keyboard::Num0)));
                } else if (goQualified && code == sf::Keyboard::Space) {
                    gameOverAppendChar(' ');
                }
            }
            continue;
        }
        // Title-screen clicks: the (P)lay/(E)ditor buttons and the bottom-right
        // toggle column. Map the pixel to logical (letterboxed) coordinates and
        // hit-test the rects set by the last titleScreen.draw().
        if (gameState == GameState::Title && event.type == sf::Event::MouseButtonPressed
                && event.mouseButton.button == sf::Mouse::Left) {
            sf::Vector2f p = window.mapPixelToCoords(
                sf::Vector2i(event.mouseButton.x, event.mouseButton.y));
            handleTitleHit(p.x, p.y);
            continue;
        }
        // In-game mouse/trackpad: moving steers Pete (swipe), left-click fires
        // the water gun (the on-screen fire button is the visual affordance).
        if (gameState == GameState::Playing) {
            if (event.type == sf::Event::MouseMoved) {
                input.handleMouseMove(event.mouseMove.x, event.mouseMove.y);
                continue;
            }
            if (event.type == sf::Event::MouseButtonPressed
                    && event.mouseButton.button == sf::Mouse::Left) {
                input.fireRequested = true;
                continue;
            }
        }
        // Touch (Android): drag past a threshold steers Pete; a tap fires in-game
        // or hits a title button. Desktop never emits these events.
        if (event.type == sf::Event::TouchBegan) {
            touchFinger = (int)event.touch.finger;
            touchStartX = (float)event.touch.x;
            touchStartY = (float)event.touch.y;
            touchMoved = false;
            continue;
        }
        if (event.type == sf::Event::TouchMoved && (int)event.touch.finger == touchFinger) {
            if (gameState == GameState::Playing && !touchMoved) {
                float dx = (float)event.touch.x - touchStartX;
                float dy = (float)event.touch.y - touchStartY;
                float adx = std::abs(dx), ady = std::abs(dy);
                if (adx >= 40.f || ady >= 40.f) {
                    touchMoved = true;
                    if (adx >= ady) input.lastDirection = dx > 0 ? MoveDirection::Right : MoveDirection::Left;
                    else            input.lastDirection = dy > 0 ? MoveDirection::Down  : MoveDirection::Up;
                }
            }
            continue;
        }
        if (event.type == sf::Event::TouchEnded && (int)event.touch.finger == touchFinger) {
            touchFinger = -1;
            if (!touchMoved) {
                if (gameState == GameState::Title) {
                    sf::Vector2f p = window.mapPixelToCoords(sf::Vector2i((int)touchStartX, (int)touchStartY));
                    handleTitleHit(p.x, p.y);
                } else if (gameState == GameState::Playing) {
                    input.fireRequested = true;
                }
            }
            continue;
        }
        input.handleEvent(event);
    }

    // Fullscreen toggle (F) — handled after polling so we don't recreate the
    // window mid-event-queue. Works in any game state.
    if (input.fullscreenToggleRequested) toggleFullscreen();

    if (gameState == GameState::Editor) {
        if (editor.playRequested) {
            editor.playRequested = false;
            gameState = GameState::Playing;
            state.resetForNewGame();
            state.level = editor.currentLevelIndex + 1;
            state.practiceMode = true;
            buildLevel();
            hud.showMessage(Message::PRACTICE_MODE, 3.0f);
        } else if (editor.backRequested) {
            editor.backRequested = false;
            gameState = GameState::Title;
        }
        input.consume();
        return;
    }

    if (gameState == GameState::Title) {
        if (input.pRequested) {
            gameState = GameState::Playing;
            state.resetForNewGame();
            state.practiceMode = false;
            buildLevel();
            hud.showMessage(Message::INTRO, 3.0f);
        }
        if (input.eRequested) {
            gameState = GameState::Editor;
            editor.open(editor.currentLevelIndex);
        }
        // ESC on the title returns a fullscreen window to windowed ("ESC for
        // Window"); it no longer quits (use the window close button to quit).
        if (input.escapeRequested && fullscreen) toggleFullscreen();
    } else if (gameState == GameState::GameOver) {
        if (input.pRequested) restartGame();
        if (input.escapeRequested) returnToTitle();
    } else if (gameState == GameState::Playing) {
        if (input.pRequested) {
            gameState = GameState::Paused;
            hud.showMessage(Message::PAUSED, 9999.0f);
            sound.pauseAudio();
        }
        if (input.escapeRequested) returnToTitle();
        if (input.fireRequested && worker) fireWaterGun();
        if (input.lastDirection != MoveDirection::None && worker) {
            worker->queueDirection(input.lastDirection);
            input.lastDirection = MoveDirection::None;
        }
    } else if (gameState == GameState::Paused) {
        if (input.pRequested) {
            gameState = GameState::Playing;
            hud.showMessage("", 0.1f);
            sound.resumeAudio();
        }
        if (input.escapeRequested) returnToTitle();
    }

    input.consume();
}

void Game::update(float dt) {
    sound.updateDucking(); // restore/duck SFX+music around boss voice lines
    if (gameState == GameState::Editor) { editor.update(dt); return; }
    if (gameState != GameState::Playing) return;

    hud.update(dt);
    scorePopups.update(dt);

    if (mazeRenderer) {
        for (auto& p : mazeRenderer->pickups)
            if (p.cooldownTimer > 0.0f) p.cooldownTimer -= dt;
    }

    if (worker) {
        worker->update(dt, gridMap);
        if (physicsWorld.workerBody)
            physicsWorld.workerBody->SetTransform(
                b2Vec2(worker->pixelPos.x / 100.0f, worker->pixelPos.y / 100.0f), 0);
    }

    GridPos workerGrid = worker ? worker->grid : WORKER_SPAWN;
    MoveDirection workerDir = worker ? worker->direction : MoveDirection::None;
    bool shielded = worker ? worker->isShielded : true;
    bossController.update(dt, gridMap, *pathfinder, workerGrid, workerDir,
                         goldDiscActive, !shielded);

    for (int i = 0; i < (int)bossController.entities.size() && i < (int)physicsWorld.bossBodies.size(); ++i) {
        auto& boss = bossController.entities[i];
        if (!physicsWorld.bossBodies[i]) continue;
        // A splashed/escaped boss has no contact body, so PETE can't run into it
        // (SpriteKit removes the node entirely until it respawns).
        if (physicsWorld.bossBodies[i]->IsEnabled() != boss.isActive)
            physicsWorld.bossBodies[i]->SetEnabled(boss.isActive);
        if (boss.isActive)
            physicsWorld.bossBodies[i]->SetTransform(
                b2Vec2(boss.pixelPos.x / 100.0f, boss.pixelPos.y / 100.0f), 0);
    }

    if (goldDiscActive) {
        goldDiscTimer -= dt;
        if (goldDiscTimer <= 0) endGoldDiscMode();
    }

    waterGun.update(dt);
    waterSplash.update(dt);
    travelerSpawner.update(dt, gridMap);

    // Box2D contacts
    contactRouter.clear();
    physicsWorld.step(dt);

    bool bossCaught = false;
    for (auto& c : contactRouter.contacts) {
        if (c.catA == PhysicsCat::BOSS && c.catB == PhysicsCat::WORKER) {
            for (int i = 0; i < (int)bossController.entities.size() && i < (int)physicsWorld.bossBodies.size(); ++i) {
                if (physicsWorld.bossBodies[i] == c.bodyA) {
                    if (!bossController.entities[i].isActive) continue;
                    if (bossController.isImmobilized(i)) continue;
                    if (bossController.isInFleeMode(i)) {
                        std::string bossName = bossController.entities[i].name;
                        bossController.capture(i, gridMap);
                        int pts = 100 * bossController.captureStreak;
                        state.bumpScore(pts);
                        sound.playCaptureBoss(bossController.captureStreak);
                        auto pos = gridMap.pointFor(bossController.entities[i].grid);
                        scorePopups.add(pts, pos);
                        refreshHUD();
                        hud.showMessage(bossName + " captured! +" + std::to_string(pts), 2.0f);
                    } else if (!shielded) {
                        bossCaught = true;
                    }
                }
            }
        }
        if (c.catA == PhysicsCat::GOLD_DISC && c.catB == PhysicsCat::WORKER) {
            for (int i = 0; i < (int)mazeRenderer->pickups.size() && i < (int)physicsWorld.pickupBodies.size(); ++i) {
                if (physicsWorld.pickupBodies[i] == c.bodyA && mazeRenderer->pickups[i].type == Tile::goldDisc && mazeRenderer->pickups[i].active) {
                    mazeRenderer->pickups[i].active = false;
                    state.bumpScore(5);
                    state.collectedGoldDiscs++;
                    sound.playGoldDisc();
                    startGoldDiscMode();
                    refreshHUD();
                    checkLevelComplete();
                }
            }
        }
        if (c.catA == PhysicsCat::MACHINE && c.catB == PhysicsCat::WORKER) {
            for (int i = 0; i < (int)mazeRenderer->pickups.size() && i < (int)physicsWorld.pickupBodies.size(); ++i) {
                if (physicsWorld.pickupBodies[i] == c.bodyA && mazeRenderer->pickups[i].active
                    && mazeRenderer->pickups[i].cooldownTimer <= 0)
                    handleMachine(mazeRenderer->pickups[i].machineName, i);
            }
        }
        if (c.catA == PhysicsCat::TPS_BOX && c.catB == PhysicsCat::WORKER) {
            for (int i = 0; i < (int)mazeRenderer->pickups.size() && i < (int)physicsWorld.pickupBodies.size(); ++i) {
                if (physicsWorld.pickupBodies[i] == c.bodyA && mazeRenderer->pickups[i].active)
                    collectTPSReport(i);
            }
        }
        if (c.catA == PhysicsCat::WATER_GUN && c.catB == PhysicsCat::WORKER) {
            for (int i = 0; i < (int)mazeRenderer->pickups.size() && i < (int)physicsWorld.pickupBodies.size(); ++i) {
                if (physicsWorld.pickupBodies[i] == c.bodyA && mazeRenderer->pickups[i].active) {
                    mazeRenderer->pickups[i].active = false;
                    state.bumpScore(75);
                    scorePopups.add(75, mazeRenderer->pickups[i].pixelPos);
                    sound.playWaterGunPickup();
                    waterGunPickedUp = true;
                    waterGun.activate();
                    refreshHUD();
                }
            }
        }
        if (c.catA == PhysicsCat::WATER_PELLET && c.catB == PhysicsCat::WORKER) {
            for (int i = 0; i < (int)mazeRenderer->pickups.size() && i < (int)physicsWorld.pickupBodies.size(); ++i) {
                if (physicsWorld.pickupBodies[i] == c.bodyA && mazeRenderer->pickups[i].active) {
                    mazeRenderer->pickups[i].active = false;
                    state.bumpScore(50);
                    scorePopups.add(50, mazeRenderer->pickups[i].pixelPos);
                    if (waterGunPickedUp) waterGun.reloadPellets(WATER_GUN_PELLETS);
                    sound.playWaterGunPickup();
                    refreshHUD();
                }
            }
        }
    }

    if (bossCaught) bossCaughtWorker();

    // Water droplet vs boss collision and wall check
    for (auto& d : waterGun.droplets) {
        if (!d.active) continue;

        // Wall collision: check if droplet center is in a wall tile
        int gx = (int)(d.pos.x / TILE_SIZE);
        int gy = (int)((d.pos.y - gridMap.yOffset) / TILE_SIZE);
        gy = GRID_ROWS - 1 - gy; // flip back to grid coords
        if (gx >= 0 && gx < GRID_COLS && gy >= 0 && gy < GRID_ROWS) {
            if (!gridMap.isWalkable({gx, gy})) {
                d.active = false;
                continue;
            }
        }

        for (int i = 0; i < (int)bossController.entities.size(); ++i) {
            auto& boss = bossController.entities[i];
            if (!boss.isActive) continue;
            float dx = d.pos.x - boss.pixelPos.x;
            float dy = d.pos.y - boss.pixelPos.y;
            if (dx*dx + dy*dy < 14.4f * 14.4f) {
                d.active = false;
                waterSplash.spawn(boss.pixelPos);
                bossController.splash(i, gridMap, *pathfinder);
                state.bumpScore(50);
                scorePopups.add(50, boss.pixelPos);
                sound.playWaterGunSplash();
                hud.showMessage(Message::BOSS_SPLASHED, 1.5f);
                refreshHUD();
                break;
            }
        }
    }

    // Worker-traveler grid collision
    if (worker) {
        for (auto& tr : travelerSpawner.travelers) {
            if (tr.active && !tr.catching && tr.grid == worker->grid) {
                travelerSpawner.catchTraveler(tr);
                state.bumpScore(tr.points);
                sound.playFishOrTreat();
                scorePopups.add(tr.points, tr.pixelPos);
                refreshHUD();
                hud.showMessage("Caught " + tr.emoji + "! +" + std::to_string(tr.points), 2.0f);
            }
        }
    }
}

void Game::render() {
    // Hide the cursor only during active play (shown on title / pause / game-over
    // / editor), matching the Xcode build. Synced on state change; no-op on WASM
    // (the browser owns the cursor) and on touch devices.
    bool hideCursor = (gameState == GameState::Playing);
    if (hideCursor != cursorHidden) {
        window.setMouseCursorVisible(!hideCursor);
        cursorHidden = hideCursor;
    }

    window.clear(sf::Color(15, 15, 18));

    // Monotonic wall-clock for animation (the dt `clock` is restarted every tick,
    // so it can't drive continuous motion — that froze the dot/pickup pulses and
    // the spinning water shot).
    float animT = animClock.getElapsedTime().asSeconds();

    if (gameState == GameState::Title) {
        titleScreen.draw(window, WINDOW_WIDTH, WINDOW_HEIGHT, state.highScore, leaderboard.entries());
    } else if (gameState == GameState::Editor) {
        editor.draw(window);
    } else {
        if (mazeRenderer) {
            mazeRenderer->drawBackground(window);
            mazeRenderer->drawDots(window, animT);
            mazeRenderer->drawPickups(window, animT);
        }

        for (auto& tr : travelerSpawner.travelers) {
            if (!tr.active && !tr.catching) continue;
            float scale = tr.catching ? tr.catchScale : 1.0f;
            float alpha = tr.catching ? tr.catchAlpha : 1.0f;
            uint8_t a = (uint8_t)(alpha * 255);

            // Emoji glyph rendered via the OS text stack (sf::Text can't do color emoji).
            // Flipped to face travel direction; the points label below is not flipped.
            // Rendered larger than a tile so the traveler fills the lane.
            drawEmoji(window, tr.emoji, tr.pixelPos, 35.42f * scale, sf::Color(255, 255, 255, a), tr.flipX);

            // Points label above
            static sf::Font font;
            static bool fontLoaded = false;
            if (!fontLoaded) {
                fontLoaded = loadFont(font, "assets/fonts/JetBrainsMono-Bold.ttf");
            }
            // systemYellow points label, +24 above the glyph. It is a child of the
            // SpriteKit wrapper, so it scales and fades with the catch animation.
            // Rasterized at uiScale and counter-scaled so it stays crisp on Retina.
            float dpi = uiScale();
            sf::Text ptsText;
            ptsText.setFont(font);
            ptsText.setString(std::to_string(tr.points));
            ptsText.setCharacterSize((unsigned)(11 * scale * dpi));
            ptsText.setFillColor(sf::Color(255, 231, 0, a));
            auto plb = ptsText.getLocalBounds();
            ptsText.setOrigin(plb.left + plb.width/2, plb.top + plb.height/2);
            ptsText.setScale(1.f / dpi, 1.f / dpi);
            ptsText.setPosition(tr.pixelPos.x, tr.pixelPos.y - 24 * scale);
            window.draw(ptsText);
        }

        // In-flight water shot: a systemCyan core with a systemBlue stroke plus a
        // white specular highlight that orbits the core (0.4s/rev) so it reads as
        // spinning through the air, matching the SpriteKit WaterDropletVisual.
        float dropSpin = animT * (6.2831853f / 0.4f);
        for (auto& d : waterGun.droplets) {
            if (!d.active) continue;
            const float R = 5.f;
            sf::CircleShape core(R, 16);
            core.setOrigin(R, R);
            core.setPosition(d.pos.x, d.pos.y);
            core.setFillColor(sf::Color(50, 200, 240, 217));   // systemCyan @ 0.85
            core.setOutlineThickness(1.f);
            core.setOutlineColor(sf::Color(10, 122, 255));      // systemBlue
            window.draw(core);
            const float off = R * 0.3f;
            float sx = -off * std::cos(dropSpin) + off * std::sin(dropSpin);
            float sy = -off * std::sin(dropSpin) - off * std::cos(dropSpin);
            sf::CircleShape spec(R * 0.35f, 12);
            spec.setOrigin(R * 0.35f, R * 0.35f);
            spec.setPosition(d.pos.x + sx, d.pos.y + sy);
            spec.setFillColor(sf::Color(255, 255, 255, 191));   // white @ 0.75
            window.draw(spec);
        }

        bossController.draw(window);

        if (worker) worker->draw(window);

        waterSplash.draw(window);

        scorePopups.draw(window);
        hud.draw(window, WINDOW_WIDTH, WINDOW_HEIGHT);

        // On-screen fire button: one big translucent ring tucked tangent to the
        // bottom corner (faint white fill + white stroke, NO inner core), matching
        // the SpriteKit installFireButton. Left-click anywhere fires; the Hide
        // setting suppresses the button. Side follows the Water Gun setting.
        if (!Settings::waterGunHide()) {
            const float R = 90.f;
            float cx = Settings::waterGunLeft() ? R : (float)WINDOW_WIDTH - R;
            float cy = (float)WINDOW_HEIGHT - R;
            sf::CircleShape ring(R, 64);
            ring.setOrigin(R, R);
            ring.setPosition(cx, cy);
            ring.setFillColor(sf::Color(255, 255, 255, 36));    // white @ 0.14
            ring.setOutlineThickness(2.f);
            ring.setOutlineColor(sf::Color(255, 255, 255, 128)); // white @ 0.5
            window.draw(ring);
        }

        if (gameState == GameState::GameOver) drawGameOver();
    }

    window.display();
}

void Game::workerEnteredTile(GridPos grid) {
    if (mazeRenderer->collectDot(grid.x, grid.y)) {
        state.collectedDots++;
        state.bumpScore(1);
        sound.playDotBlip();
        refreshHUD();
        checkLevelComplete();
    }
}

void Game::checkLevelComplete() {
    bool dotsDone = state.collectedDots >= state.dotCount;
    bool discsDone = state.collectedGoldDiscs >= state.goldDiscCount;
    if (dotsDone && discsDone) {
        if (state.tpsReportsDelivered >= 1) startNextLevel();
        else hud.showMessage(Message::NEED_TPS, 3.0f);
    }
}

void Game::bossCaughtWorker() {
    sound.playCaughtByBoss();
    state.lives--;
    if (goldDiscActive) endGoldDiscMode();
    state.reportItems.clear();
    state.currentReportScore = 0;

    // Losing the in-progress report ungrays its machines so they are collectable
    // again immediately, matching SpriteKit's resetGrayedMachines.
    if (mazeRenderer) {
        for (auto& p : mazeRenderer->pickups) {
            if (p.type == Tile::printer || p.type == Tile::fax ||
                p.type == Tile::coverSheet || p.type == Tile::bookBinder)
                p.cooldownTimer = 0.0f;
        }
    }
    refreshHUD();

    if (worker) {
        worker->resetMotion();
        worker->teleport(mazeRenderer->workerSpawnFromMap.x >= 0 ? mazeRenderer->workerSpawnFromMap : WORKER_SPAWN, gridMap);
        worker->applySpawnShield();
    }
    bossController.teleportAllToSpawn(gridMap, *pathfinder);

    if (state.lives <= 0) {
        gameState = GameState::GameOver;
        // Seed the combo screen: practice mode (launched from the editor) never
        // affects the high score or the leaderboard, matching the SpriteKit
        // GameScene. The name is recorded on commit (PLAY/ESC) only when the
        // score qualifies; non-qualifying scores never reach the top 10 anyway.
        goName.clear();
        goCommitted = false;
        goQualified = false;
        if (!state.practiceMode) {
            state.saveHighScore();
            goQualified = leaderboard.qualifies(state.score);
            goName = leaderboard.savedName();
            if (goName.empty()) { const char* user = std::getenv("USER"); goName = user ? user : ""; }
        }
        sound.stopBackgroundMusic();
        sound.stopGoldDiscBass();
        sound.playGameOver();
    } else {
        hud.showMessage("A boss caught you! " + std::to_string(state.lives) + " workers left.", 3.0f);
    }
}

std::vector<Game::GameOverKey> Game::gameOverKeys() const {
    std::vector<GameOverKey> keys;
    const float W = (float)WINDOW_WIDTH;
    if (goQualified) {
        const std::string rows[] = {"1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"};
        const float keyW = 82.f, keyH = 50.f, gap = 10.f;
        float y = 235.f;
        for (const auto& row : rows) {
            float rowW = (float)row.size() * keyW + (float)(row.size() - 1) * gap;
            float x = (W - rowW) / 2.f;
            for (char c : row) {
                keys.push_back({sf::FloatRect(x, y - keyH / 2.f, keyW, keyH), 0, c});
                x += keyW + gap;
            }
            y += keyH + gap;
        }
        const float delW = keyW * 2.f, spW = keyW * 6.f;
        float rowW = delW + gap + spW;
        float x = (W - rowW) / 2.f;
        keys.push_back({sf::FloatRect(x, y - keyH / 2.f, delW, keyH), 1, 0});
        x += delW + gap;
        keys.push_back({sf::FloatRect(x, y - keyH / 2.f, spW, keyH), 2, 0});
    }
    const float bw = W * 0.30f, gapB = 90.f;
    const float bh = goQualified ? 70.f : 80.f;
    const float by = goQualified ? 557.f : 507.f;
    float startX = (W - (2.f * bw + gapB)) / 2.f;
    keys.push_back({sf::FloatRect(startX, by - bh / 2.f, bw, bh), 4, 0});                 // ESC (left)
    keys.push_back({sf::FloatRect(startX + bw + gapB, by - bh / 2.f, bw, bh), 3, 0});     // PLAY (right)
    return keys;
}

void Game::drawGameOver() {
    const float W = (float)WINDOW_WIDTH, H = (float)WINDOW_HEIGHT;
    sf::RectangleShape dim(sf::Vector2f(W, H));
    dim.setFillColor(sf::Color(0, 0, 0, 205));
    window.draw(dim);
    const float m = 18.f;
    sf::RectangleShape panel(sf::Vector2f(W - 2 * m, H - 2 * m));
    panel.setPosition(m, m);
    panel.setFillColor(sf::Color(26, 26, 33, 250));
    panel.setOutlineColor(sf::Color(255, 140, 0));
    panel.setOutlineThickness(3.f);
    window.draw(panel);

    const bool q = goQualified;
    goText(window, "GAME OVER", q ? 44.f : 56.f, sf::Color(242, 51, 46), W / 2, q ? 44.f : 70.f, 1);
    goText(window, "FINAL " + std::to_string(state.score) + "    HIGH " + std::to_string(state.highScore),
           q ? 22.f : 24.f, sf::Color::White, W / 2, q ? 82.f : 118.f, 1);

    // The leaderboard is the least important element: shown only when there is no
    // name entry, otherwise yielded to the keyboard.
    if (q) {
        goText(window, "NEW HIGH SCORE!   Enter name:", 20.f, sf::Color(77, 217, 255), W / 2, 120.f, 1);
        const float fw = 600.f, fh = 44.f, fx = (W - fw) / 2.f, fy = 165.f;
        sf::RectangleShape field(sf::Vector2f(fw, fh));
        field.setPosition(fx, fy - fh / 2.f);
        field.setFillColor(sf::Color(245, 245, 245));
        field.setOutlineColor(sf::Color(150, 150, 150));
        field.setOutlineThickness(1.f);
        window.draw(field);
        float tw = goText(window, goName, 24.f, sf::Color(13, 13, 26), fx + 14.f, fy, 0, false);
        if (std::fmod(animClock.getElapsedTime().asSeconds(), 0.9f) < 0.45f) {
            // Thin rectangle caret (matches SpriteKit; tucks against the last
            // letter with no glyph side-bearing, unlike a "|").
            sf::RectangleShape caret(sf::Vector2f(3.f, fh * 0.6f));
            caret.setFillColor(sf::Color(13, 13, 26));
            caret.setPosition(fx + 16.f + tw, fy - fh * 0.3f);
            window.draw(caret);
        }
    } else {
        goText(window, "LEADERBOARD", 22.f, sf::Color(255, 235, 107), W / 2, 158.f, 1);
        const auto& entries = leaderboard.entries();
        const float rowH = 27.f, topY = 192.f;
        if (entries.empty()) {
            goText(window, "No local scores yet.", 18.f, sf::Color(180, 180, 180), W / 2, topY, 1);
        } else {
            for (int i = 0; i < (int)entries.size() && i < 10; ++i) {
                float y = topY + (float)i * rowH;
                goText(window, std::to_string(i + 1) + ". " + entries[i].name, 20.f, sf::Color::White, W * 0.30f, y, 0, false);
                goText(window, std::to_string(entries[i].score), 20.f, sf::Color::White, W * 0.70f, y, 2, false);
            }
        }
    }

    for (const auto& k : gameOverKeys()) {
        sf::RectangleShape r(sf::Vector2f(k.rect.width, k.rect.height));
        r.setPosition(k.rect.left, k.rect.top);
        sf::Color fill(56, 56, 56), stroke(110, 110, 110);
        std::string lbl;
        float fs = 18.f;
        switch (k.kind) {
        case 0: lbl = std::string(1, k.ch); break;
        case 1: lbl = "DEL"; fill = sf::Color(80, 80, 80); fs = 15.f; break;
        case 2: lbl = "SPACE"; fs = 15.f; break;
        case 3: lbl = "PLAY"; fill = sf::Color(31, 128, 46); stroke = sf::Color(60, 180, 80); fs = 28.f; break;
        case 4: lbl = "ESC"; fill = sf::Color(128, 46, 46); stroke = sf::Color(180, 70, 70); fs = 28.f; break;
        }
        r.setFillColor(fill);
        r.setOutlineColor(stroke);
        r.setOutlineThickness(1.f);
        window.draw(r);
        // SpriteKit: letter/number keys + DEL/SPACE are Menlo (body); only the
        // ESC/PLAY action buttons are Marker Felt.
        bool keyBold = (k.kind == 3 || k.kind == 4);
        goText(window, lbl, fs, sf::Color::White, k.rect.left + k.rect.width / 2.f, k.rect.top + k.rect.height / 2.f, 1, keyBold);
    }
}

void Game::gameOverTap(float x, float y) {
    for (const auto& k : gameOverKeys()) {
        if (!k.rect.contains(x, y)) continue;
        switch (k.kind) {
        case 0: gameOverAppendChar(k.ch); break;
        case 1: if (!goName.empty()) goName.pop_back(); break;
        case 2: gameOverAppendChar(' '); break;
        case 3: gameOverCommit(); input.pRequested = true; break;
        case 4: gameOverCommit(); input.escapeRequested = true; break;
        }
        return;
    }
}

void Game::gameOverAppendChar(char c) {
    if (!goQualified || (int)goName.size() >= 16) return;
    if (c == ' ' && goName.empty()) return;
    goName.push_back(c);
}

void Game::gameOverCommit() {
    if (!goQualified || goCommitted) return;
    std::string n = goName;
    while (!n.empty() && n.front() == ' ') n.erase(n.begin());
    while (!n.empty() && n.back() == ' ') n.pop_back();
    if (n.empty()) return;
    goCommitted = true;
    leaderboard.saveName(n);
    leaderboard.record(n, state.score);
}

void Game::startGoldDiscMode() {
    goldDiscActive = true;
    goldDiscTimer = GOLD_DISC_DUR;
    bossController.setGoldDiscActive(true);
    sound.startGoldDiscBass(state.level % 12 == 0);
    hud.showMessage(Message::GOLD_DISC_ACTIVE, 3.0f);
    refreshHUD();
}

void Game::endGoldDiscMode() {
    goldDiscActive = false;
    goldDiscTimer = 0;
    bossController.setGoldDiscActive(false);
    sound.stopGoldDiscBass();
    hud.showMessage(Message::GOLD_DISC_ENDED, 2.0f);
    refreshHUD();
}

void Game::fireWaterGun() {
    if (!waterGun.isActive) return;
    if (goldDiscActive) { hud.showMessage(Message::WATER_GUN_BLUE, 2.0f); return; }
    if (!worker || worker->direction == MoveDirection::None) return;
    waterGun.fire(worker->pixelPos, worker->direction);
    sound.playWaterGunShoot();
    refreshHUD();
    // Out of ammo: can't fire, but the gun stays picked up until a new level so the
    // HUD keeps showing it and water pellets can reload it.
    if (waterGun.pelletsRemaining == 0) {
        hud.showMessage(Message::WATER_GUN_ENDED, 2.0f);
    }
}

void Game::handleMachine(const std::string& name, int pickupIndex) {
    bool isReq = false;
    for (auto& r : Machine::REQUIRED) if (r == name) { isReq = true; break; }
    if (!isReq || state.reportItems.count(name)) return;
    state.reportItems.insert(name);

    int itemIndex = (int)state.reportItems.size() - 1;
    int pts = 0;
    if (itemIndex < 4) {
        pts = REPORT_ITEM_POINTS[itemIndex];
        state.bumpScore(pts);
        state.currentReportScore += pts;
        scorePopups.add(pts, mazeRenderer->pickups[pickupIndex].pixelPos);
    }

    sound.playMachine(name);
    // SpriteKit grayOutMachine: dim the touched machine and make it uncollectable
    // for a cooldown, then it ungrays — it is NOT removed.
    mazeRenderer->pickups[pickupIndex].cooldownTimer = MACHINE_COOLDOWN;
    refreshHUD();

    if ((int)state.reportItems.size() == (int)Machine::REQUIRED.size())
        hud.showMessage(Message::TPS_READY, 6.0f);
    else
        hud.showMessage("Collected " + name +
                        " page for TPS report +" + std::to_string(pts), 2.0f);
}

void Game::collectTPSReport(int pickupIndex) {
    if ((int)state.reportItems.size() < (int)Machine::REQUIRED.size()) {
        // List the missing machines in canonical order (printer, fax, cover sheet,
        // book binder), matching Strings.Message.tpsMissingItems. The voice key
        // uses the P/F/C/M codes (scripts/generate_voices.sh); the HUD shows the
        // display names: "The TPS report is missing Printer, Fax, Cover Sheet."
        std::string key = "tps_missing_";
        std::string names;
        auto addMissing = [&](const std::string& machine, char code) {
            if (state.reportItems.count(machine)) return;
            key += code;
            if (!names.empty()) names += ", ";
            names += Machine::DISPLAY_NAMES.at(machine);
        };
        addMissing(Machine::PRINTER,     'P');
        addMissing(Machine::FAX,         'F');
        addMissing(Machine::COVER_SHEET, 'C');
        addMissing(Machine::BOOK_BINDER, 'M');
        sound.playVoice(key);
        hud.showMessage("The TPS report is missing " + names + ".", 5.0f);
        return;
    }
    state.tpsReportsDelivered++;
    state.reportItems.clear();
    state.currentReportScore = 0;

    int tpsPoints = state.level * 100 + 100;
    state.bumpScore(tpsPoints);
    if (worker) scorePopups.add(tpsPoints, worker->pixelPos);

    sound.playTpsDeliver();
    bool gainedLife = state.lives < MAX_LIVES;
    if (gainedLife) state.lives++;
    refreshHUD();
    hud.showMessage("TPS report turned in! +" + std::to_string(tpsPoints) +
                    (gainedLife ? ", extra worker hired." : ", workers at max."), 3.0f);
    checkLevelComplete();
}

void Game::refreshHUD() {
    hud.score = state.score;
    hud.highScore = state.highScore;
    hud.level = state.level;
    hud.collectedDots = state.collectedDots;
    hud.dotCount = state.dotCount;
    hud.tpsReports = state.tpsReportsDelivered;
    hud.reportItems = state.reportItems;
    hud.lives = state.lives;
    hud.waterGunActive = waterGun.isActive;
    hud.waterGunVisible = waterGunPickedUp && !Settings::waterGunHide();
    hud.waterGunPellets = waterGun.pelletsRemaining;
    hud.goldDiscActive = goldDiscActive;
}

void Game::startNextLevel() {
    state.advanceLevel();
    resetSceneAndBuild();
    sound.playLevelStart();
    hud.showMessage("Level " + std::to_string(state.level) + "! New office floor loaded.", 3.0f);
}

void Game::resetSceneAndBuild() {
    bossController.clear();
    travelerSpawner.reset();
    if (goldDiscActive) endGoldDiscMode();
    waterGun.deactivate();
    waterGunPickedUp = false;
    sound.stopGoldDiscBass();
    worker.reset();
    buildLevel();
}

void Game::restartGame() {
    hud.isGameOver = false;
    gameState = GameState::Playing;
    state.resetForNewGame();
    resetSceneAndBuild();
    hud.showMessage(Message::NEW_GAME, 3.0f);
}

void Game::returnToTitle() {
    hud.isGameOver = false;
    sound.stopBackgroundMusic();
    if (goldDiscActive) endGoldDiscMode();
    // A practice session (started from the editor) returns to the editor at the
    // level being tested, like the SpriteKit GameScene.returnToTitleScene().
    if (state.practiceMode) {
        gameState = GameState::Editor;
        editor.open(std::max(0, state.level - 1));
        return;
    }
    gameState = GameState::Title;
}

// MARK: - Boss water-droplet dodge (BossControllerDelegate)

GridPos Game::dropletGridFor(sf::Vector2f pos) const {
    int gx = (int)(pos.x / TILE_SIZE);
    int gy = (int)((pos.y - gridMap.yOffset) / TILE_SIZE);
    gy = GRID_ROWS - 1 - gy; // flip screen row into bottom-up grid coords
    return {gx, gy};
}

MoveDirection Game::dropletAxisThreatening(GridPos bossGrid) {
    for (auto& d : waterGun.droplets) {
        if (!d.active) continue;
        // Travel axis from screen velocity: y-down screen, y-up grid.
        MoveDirection dir;
        if (std::abs(d.velocity.x) > std::abs(d.velocity.y))
            dir = d.velocity.x > 0 ? MoveDirection::Right : MoveDirection::Left;
        else
            dir = d.velocity.y < 0 ? MoveDirection::Up : MoveDirection::Down;
        if (dropletThreatens(dropletGridFor(d.pos), dir, bossGrid))
            return dir;
    }
    return MoveDirection::None;
}

// A boss is threatened when it shares the droplet's row/col, sits ahead of it
// along its travel axis within the dodge range, and every tile between is
// walkable (a wall would stop the shot first).
bool Game::dropletThreatens(GridPos d, MoveDirection dir, GridPos b) const {
    auto step = bm::delta(dir);
    int dist;
    if (step.x != 0) {
        if (b.y != d.y) return false;
        int diff = b.x - d.x;
        if (diff == 0 || (step.x > 0) != (diff > 0)) return false;
        dist = std::abs(diff);
    } else {
        if (b.x != d.x) return false;
        int diff = b.y - d.y;
        if (diff == 0 || (step.y > 0) != (diff > 0)) return false;
        dist = std::abs(diff);
    }
    if (dist > 8) return false;
    GridPos cell = d;
    for (int i = 0; i < dist; ++i) {
        cell = {cell.x + step.x, cell.y + step.y};
        if (!gridMap.isWalkable(cell)) return false;
    }
    return true;
}

} // namespace bm