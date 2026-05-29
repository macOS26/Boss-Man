#include "Game.hpp"
#include "EmojiText.hpp"
#include "Assets.hpp"
#include "MacWindow.hpp"
#include "UiScale.hpp"
#include <algorithm>
#include <cstdlib>

namespace bm {

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
        if (input.escapeRequested) window.close();
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
                        bossController.capture(i, gridMap);
                        int pts = 100 * bossController.captureStreak;
                        state.bumpScore(pts);
                        sound.playCaptureBoss(bossController.captureStreak);
                        auto pos = gridMap.pointFor(bossController.entities[i].grid);
                        scorePopups.add(pts, pos);
                        refreshHUD();
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
            if (!boss.isActive || boss.isImmobilized) continue;
            float dx = d.pos.x - boss.pixelPos.x;
            float dy = d.pos.y - boss.pixelPos.y;
            if (dx*dx + dy*dy < 16.0f * 16.0f) {
                d.active = false;
                waterSplash.spawn(boss.pixelPos);
                bossController.splash(i, gridMap, *pathfinder);
                state.bumpScore(50);
                scorePopups.add(50, boss.pixelPos);
                sound.playWaterGunSplash();
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
            }
        }
    }
}

void Game::render() {
    window.clear(sf::Color(15, 15, 18));

    if (gameState == GameState::Title) {
        titleScreen.draw(window, WINDOW_WIDTH, WINDOW_HEIGHT, state.highScore, leaderboard.entries());
    } else if (gameState == GameState::Editor) {
        editor.draw(window);
    } else {
        if (mazeRenderer) {
            mazeRenderer->drawBackground(window);
            mazeRenderer->drawDots(window, clock.getElapsedTime().asSeconds());
            mazeRenderer->drawPickups(window, clock.getElapsedTime().asSeconds());
        }

        for (auto& tr : travelerSpawner.travelers) {
            if (!tr.active && !tr.catching) continue;
            float scale = tr.catching ? tr.catchScale : 1.0f;
            float alpha = tr.catching ? tr.catchAlpha : 1.0f;
            uint8_t a = (uint8_t)(alpha * 255);

            // Emoji glyph rendered via the OS text stack (sf::Text can't do color emoji).
            // Flipped to face travel direction; the points label below is not flipped.
            // 30.8 = 28 * 1.1 — travelers run 10% larger so they fill the lane.
            drawEmoji(window, tr.emoji, tr.pixelPos, 30.8f * scale, sf::Color(255, 255, 255, a), tr.flipX);

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

        for (auto& d : waterGun.droplets) {
            if (!d.active) continue;
            sf::CircleShape drop(5);
            drop.setFillColor(sf::Color(0, 200, 240));
            drop.setPosition(d.pos.x - 5, d.pos.y - 5);
            window.draw(drop);
        }

        bossController.draw(window);

        if (worker) worker->draw(window);

        waterSplash.draw(window);

        scorePopups.draw(window);
        hud.draw(window, WINDOW_WIDTH, WINDOW_HEIGHT);
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
        hud.isGameOver = true;
        // Practice mode (launched from the editor) never affects the high score
        // or the leaderboard, matching the SpriteKit GameScene.
        if (!state.practiceMode) {
            state.saveHighScore();
            const char* user = std::getenv("USER");
            leaderboard.record(user ? user : "PLAYER", state.score);
        }
        sound.stopBackgroundMusic();
        sound.stopGoldDiscBass();
        sound.playGameOver();
    } else {
        hud.showMessage("A boss caught you! " + std::to_string(state.lives) + " workers left.", 3.0f);
    }
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
    if (itemIndex < 4) {
        int pts = REPORT_ITEM_POINTS[itemIndex];
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
    hud.showMessage("TPS report turned in! +" + std::to_string(tpsPoints), 3.0f);
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
    hud.waterGunVisible = waterGunPickedUp;
    hud.waterGunPellets = waterGun.pelletsRemaining;
    hud.goldDiscActive = goldDiscActive;
}

void Game::startNextLevel() {
    state.advanceLevel();
    resetSceneAndBuild();
    sound.playLevelStart();
    hud.showMessage("Level " + std::to_string(state.level) + "!", 3.0f);
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

} // namespace bm