#include "VoxelScene.hpp"
#include "SoundManager.hpp"
#include "PixelPersonRenderer.hpp"
#include "EmojiText.hpp"
#include "Assets.hpp"
#include "UiScale.hpp"
#include "Settings.hpp"
#include <SFML/Window/Keyboard.hpp>
#include <algorithm>
#include <cmath>
#include <unordered_map>
#include <unordered_set>

namespace bm {

namespace {

// SFML key codes used by the tank controls (mirrors the SpriteKit KeyCode set).
constexpr int K_ESC   = sf::Keyboard::Escape;
constexpr int K_P     = sf::Keyboard::P;
constexpr int K_SPACE = sf::Keyboard::Space;
constexpr int K_LEFT  = sf::Keyboard::Left;
constexpr int K_RIGHT = sf::Keyboard::Right;
constexpr int K_UP    = sf::Keyboard::Up;
constexpr int K_DOWN  = sf::Keyboard::Down;
constexpr int K_A     = sf::Keyboard::A;
constexpr int K_D     = sf::Keyboard::D;
constexpr int K_W     = sf::Keyboard::W;
constexpr int K_S     = sf::Keyboard::S;

// Pickup emoji glyphs (machines / brown box / water gun), matching the 2D modes.
const std::string EMO_PRINTER = "\xf0\x9f\x96\xa8\xef\xb8\x8f"; // 🖨️
const std::string EMO_FAX     = "\xf0\x9f\x93\xa0";             // 📠
const std::string EMO_COVER   = "\xf0\x9f\x93\x84";             // 📄
const std::string EMO_BINDER  = "\xf0\x9f\x93\x9a";             // 📚
const std::string EMO_BOX     = "\xf0\x9f\x93\xa6";             // 📦
const std::string EMO_GUN     = "\xf0\x9f\x94\xab";             // 🔫

const std::string& pickupEmoji(int ch) {
    switch (ch) {
    case Tile::printer:    return EMO_PRINTER;
    case Tile::fax:        return EMO_FAX;
    case Tile::coverSheet: return EMO_COVER;
    case Tile::bookBinder: return EMO_BINDER;
    case Tile::brownBox:   return EMO_BOX;
    case Tile::waterGun:   return EMO_GUN;
    }
    static const std::string none;
    return none;
}

const sf::Font& nameFont() {
    static sf::Font font;
    static bool loaded = false;
    if (!loaded) loaded = loadFont(font, "assets/fonts/JetBrainsMono-Bold.ttf");
    return font;
}

// Crisp-on-Retina centered label (rasterize at uiScale, counter-scale down).
void drawCenteredText(sf::RenderTarget& t, const std::string& s, float sizePx,
                      sf::Color color, float x, float y) {
    if (s.empty()) return;
    float dpi = uiScale();
    sf::Text txt;
    txt.setFont(nameFont());
    txt.setString(s);
    txt.setCharacterSize((unsigned)(sizePx * dpi));
    txt.setFillColor(color);
    auto lb = txt.getLocalBounds();
    txt.setOrigin(lb.left + lb.width / 2.f, lb.top + lb.height / 2.f);
    txt.setScale(1.f / dpi, 1.f / dpi);
    txt.setPosition(x, y);
    t.draw(txt);
}

// The Pete-back avatar renderer (rear silhouette: no eyes/tie, hair-coloured head).
PersonConfig peteBackConfig() {
    PersonConfig cfg{PETE_BODY, PETE_TIE, PETE_HAIR, PETE_SHOE_OUT, PETE_PANTS, SKIN_COLOR};
    cfg.backView = true;
    cfg.walkExaggeration = 1.0f;
    return cfg;
}

} // namespace

VoxelScene::VoxelScene(SoundManager& sound, RoundState& state,
                     const std::vector<std::string>& mapRows, int highScore)
    : sound_(sound), state_(state), map_(mapRows), gridMap_(32.f), highScore_(highScore) {
    rowsCount_ = (int)map_.size();
    colsCount_ = rowsCount_ > 0 ? (int)map_[0].size() : 0;
    viewW_ = (float)WINDOW_WIDTH;
    viewHeight_ = (float)WINDOW_HEIGHT;
    zbuf_.assign(columns_, 0.0);

    // Fresh dot tally for the bonus; keep the level set by the caller (title = 1,
    // the editor's test = the level being edited) so the HUD + wall colour match.
    state_.collectedDots = 0;
    state_.reportItems.clear();
    state_.currentReportScore = 0;
    state_.tpsReportsDelivered = 0;
    state_.highScore = highScore_;
    int dots = 0;
    for (auto& row : map_)
        for (char c : row)
            if (c == Tile::dot || c == Tile::hideout) dots++;
    state_.dotCount = dots;
    int discs = 0;
    for (auto& row : map_)
        for (char c : row)
            if (c == Tile::goldDisc) discs++;
    state_.goldDiscCount = discs;

    placeStart();
    buildBillboards();
    buildMap();
    setupBossController();
    // The traveler walks the maze for points, exactly as in 2D (same spawner); the 3D view
    // projects it as an emoji billboard at its grid tile (see render()).
    travelerSpawner_.setSound(&sound_);
    travelerSpawner_.reset();
    travelerSpawner_.scheduleVisits(state_.level, *pathfinder_);

    hud_.compactHud = true; // force the compact 150/200-style mini HUD (DOOM era zoomPercent is 100)
    refreshHUD();

    // On-screen controls (joystick + fire button), unless the Water Gun setting hides
    // them. Centers are stored in SFML y-down logical coords (the bottom corner),
    // tucked 15px above the bottom edge like the SpriteKit installFireButton.
    if (ControlMode::showsControl()) {
        controlsShown_ = true;
        bool fireOnLeft = !ControlMode::onLeft();   // fire button opposite the movement widget
        float bottomY = viewHeight_ - (fireButtonRadius_ + 15.f);
        fireButtonCenter_ = sf::Vector2f(fireOnLeft ? fireButtonRadius_ : viewW_ - fireButtonRadius_,
                                         bottomY);
        joystickCenter_ = sf::Vector2f(fireOnLeft ? viewW_ - joystickRadius_ : joystickRadius_,
                                       viewHeight_ - (joystickRadius_ + 15.f));
        joystickThumb_ = joystickCenter_;
    }

    sound_.startBackgroundMusic(false);
}

// MARK: - Map helpers

char VoxelScene::tileAtRaster(int c, int r) const {
    if (r < 0 || r >= rowsCount_ || c < 0 || c >= (int)map_[r].size()) return Tile::wall;
    return map_[r][c];
}

bool VoxelScene::isWall(double x, double y) const {
    int c = (int)std::floor(x), r = (int)std::floor(y);
    if (r < 0 || r >= rowsCount_ || c < 0 || c >= (int)map_[r].size()) return true;
    return map_[r][c] == Tile::wall;
}

bool VoxelScene::open(int c, int r) const {
    if (r < 0 || r >= rowsCount_ || c < 0 || c >= (int)map_[r].size()) return false;
    return map_[r][c] != Tile::wall;
}

double VoxelScene::cardinal(int dx, int dy) {
    if (dx > 0) return 0;
    if (dx < 0) return M_PI;
    return dy > 0 ? M_PI / 2 : -M_PI / 2;
}

void VoxelScene::placeStart() {
    int sc = 1, sr = 1; bool found = false;
    for (int r = 0; r < rowsCount_ && !found; ++r)
        for (int c = 0; c < (int)map_[r].size(); ++c)
            if (map_[r][c] == Tile::worker) { sc = c; sr = r; found = true; break; }
    if (!found) {
        for (int r = 0; r < rowsCount_ && !found; ++r)
            for (int c = 0; c < (int)map_[r].size(); ++c)
                if (map_[r][c] != Tile::wall) { sc = c; sr = r; found = true; break; }
    }
    px_ = sc + 0.5; py_ = sr + 0.5;
    spawnPx_ = px_; spawnPy_ = py_;
    int dx[] = {1, 0, -1, 0}, dy[] = {0, 1, 0, -1};
    for (int i = 0; i < 4; ++i)
        if (open(sc + dx[i], sr + dy[i])) { moveDirX_ = dx[i]; moveDirY_ = dy[i]; break; }
    targetAngle_ = cardinal(moveDirX_, moveDirY_);
    angle_ = targetAngle_;
}

// MARK: - Billboards

void VoxelScene::buildBillboards() {
    for (int r = 0; r < rowsCount_; ++r) {
        for (int c = 0; c < (int)map_[r].size(); ++c) {
            char ch = map_[r][c];
            double x = c + 0.5, y = r + 0.5;
            double worldH = 0.6;
            bool keep = true;
            switch (ch) {
            case Tile::dot: case Tile::hideout:   worldH = pelletWorldH(); break;
            case Tile::goldDisc:                  worldH = 0.4;  break;
            case Tile::waterPellet:               worldH = 0.4;  break;
            case Tile::waterGun:                  worldH = 0.5;  break;
            case Tile::printer: case Tile::fax:
            case Tile::coverSheet: case Tile::bookBinder:
            case Tile::brownBox:                  worldH = 0.6;  break;
            default: keep = false; break;
            }
            if (!keep) continue;
            billboards_.push_back(Billboard{ch, worldH, x, y, true, 1.f});
        }
    }
}

// MARK: - Minimap

sf::Vector2f VoxelScene::mapLocal(double x, double y) const {
    // SpriteKit y-up local map space, then offset + scaled into the SFML panel.
    float lx = (float)x * mapCell_;
    float ly = ((float)rowsCount_ - (float)y) * mapCell_; // y-up
    float sx = mapOrigin_.x + lx * mapScale_;
    float sy = screenY(mapOrigin_.y + ly * mapScale_);    // y-up -> y-down
    return {sx, sy};
}

void VoxelScene::buildMap() {
    float mapH = (float)rowsCount_ * mapCell_;
    float mapW = (float)colsCount_ * mapCell_;
    mapScale_ = (radarH_ - 8.f) / mapH;
    // SpriteKit: mapLayer.position = ((width - mapW*scale)/2, 4) in y-up space.
    mapOrigin_ = sf::Vector2f((viewW_ - mapW * mapScale_) / 2.f, 4.f);
}

// MARK: - BossController setup

void VoxelScene::setupBossController() {
    gridMap_.yOffset = 0.f;
    gridMap_.setRows(map_);
    pathfinder_ = std::make_unique<Pathfinder>(gridMap_);
    bossController_.setSound(&sound_);
    bossController_.setDelegate(this);

    // Spawn positions from the level '1'..'4' tiles, in the bottom-up GridMap grid.
    std::vector<std::pair<int, GridPos>> overrides;
    for (int r = 0; r < rowsCount_; ++r) {
        int gridY = rowsCount_ - 1 - r;
        for (int c = 0; c < (int)map_[r].size(); ++c) {
            char ch = map_[r][c];
            if (ch >= '1' && ch <= '4')
                overrides.push_back({ch - '1', GridPos{c, gridY}});
        }
    }
    bossController_.spawn(1, gridMap_, *pathfinder_, overrides);
    bossGrid_.assign(bossController_.entities.size(), {0.0, 0.0});
}

// MARK: - HUD

void VoxelScene::refreshHUD() {
    hud_.score = state_.score;
    hud_.highScore = state_.highScore;
    hud_.level = state_.level;
    hud_.collectedDots = state_.collectedDots;
    hud_.dotCount = state_.dotCount;
    hud_.tpsReports = state_.tpsReportsDelivered;
    hud_.reportItems = state_.reportItems;
    hud_.lives = state_.lives;
    hud_.waterGunActive = waterGun_.isActive;
    hud_.waterGunVisible = waterGunPickedUp_;
    hud_.waterGunPellets = waterGun_.pelletsRemaining;
    hud_.goldDiscActive = false;
}

// MARK: - Gold disc

void VoxelScene::startGoldDiscMode() {
    goldDiscActive_ = true;
    bossController_.setGoldDiscActive(true);
    sound_.startGoldDiscBass(false);
    frightenSecondsLeft_ = goldDiscDuration_;
    hud_.showMessage(Message::GOLD_DISC_ACTIVE, 3.f);
    refreshHUD();
}

void VoxelScene::endGoldDiscMode() {
    goldDiscActive_ = false;
    bossController_.setGoldDiscActive(false);
    sound_.stopGoldDiscBass();
    frightenSecondsLeft_ = 0;
    hud_.showMessage(Message::GOLD_DISC_ENDED, 2.f);
    refreshHUD();
}

// MARK: - Pause

void VoxelScene::togglePause() {
    isUserPaused_ = !isUserPaused_;
    if (isUserPaused_) {
        hud_.showMessage(Message::PAUSED, 9999.f);
        sound_.pauseAudio();
        travelerSpawner_.pause();
    } else {
        hud_.showMessage("", 0.1f);
        sound_.resumeAudio();
        travelerSpawner_.resume();
    }
}

// MARK: - BossControllerDelegate (Pete reported in GridMap bottom-up coords)

MoveDirection VoxelScene::dropletAxisThreatening(GridPos bossGrid) {
    for (auto& s : shots_) {
        if (!s.alive) continue;
        GridPos d{(int)std::floor(s.x), rowsCount_ - 1 - (int)std::floor(s.y)};
        MoveDirection dir = s.dirX > 0 ? MoveDirection::Right
                          : s.dirX < 0 ? MoveDirection::Left
                          : (s.dirY > 0 ? MoveDirection::Down : MoveDirection::Up);
        if (dropletThreatens(d, dir, bossGrid)) return dir;
    }
    return MoveDirection::None;
}

bool VoxelScene::dropletThreatens(GridPos d, MoveDirection dir, GridPos b) const {
    const int dropletDodgeRange = 8;
    auto del = bm::delta(dir);
    int dist;
    if (del.x != 0) {
        if (b.y != d.y) return false;
        int delta = b.x - d.x;
        if (delta == 0 || ((del.x > 0) != (delta > 0))) return false;
        dist = std::abs(delta);
    } else {
        if (b.x != d.x) return false;
        int delta = b.y - d.y;
        if (delta == 0 || ((del.y > 0) != (delta > 0))) return false;
        dist = std::abs(delta);
    }
    if (dist > dropletDodgeRange) return false;
    GridPos step = d;
    for (int i = 0; i < dist; ++i) {
        step = {step.x + del.x, step.y + del.y};
        if (!gridMap_.isWalkable(step)) return false;
    }
    return true;
}

// MARK: - Per-frame

void VoxelScene::update(float dt) {
    if (isUserPaused_ || gameOver_) { hud_.update(dt); return; }

    // Advance the sim at a fixed 60Hz (the SpriteKit master's preferredFramesPerSecond),
    // even though the host ticks at 120Hz. Each fired step runs the verbatim 1/60 logic.
    const float fixed = 1.f / 60.f;
    simAccumulator_ += dt;
    int guard = 0;
    while (simAccumulator_ >= fixed && guard < 4) {
        simAccumulator_ -= fixed;
        guard++;
        if (dying_) { updateDeath(); continue; }
        step();
    }

    animTime_ += dt; // pickup throb clock (independent of motion)
    hud_.update(dt);
    for (auto& b : billboards_) {
        if (b.cooldownTimer > 0.f) {
            b.cooldownTimer -= dt;
            if (b.cooldownTimer <= 0.f) { b.cooldownTimer = 0.f; b.alpha = 1.f; }
        }
    }
    // Radar popups rise 42px over 0.7s (60px/s); 3D popups rise fontSize*1.55 over
    // 0.7s. Both fade out across the 0.7s lifetime (alpha = timer/0.7 at draw).
    for (auto& m : miniPops_) { m.timer -= dt; m.pos.y -= 60.f * dt; }
    miniPops_.erase(std::remove_if(miniPops_.begin(), miniPops_.end(),
        [](const MiniPop& m) { return m.timer <= 0; }), miniPops_.end());
    for (auto& m : bigPops_) { m.timer -= dt; m.pos.y -= (m.fontSize * 1.55f / 0.7f) * dt; }
    bigPops_.erase(std::remove_if(bigPops_.begin(), bigPops_.end(),
        [](const MiniPop& m) { return m.timer <= 0; }), bigPops_.end());
}

// MARK: - Lane movement (Pac-Man style: auto-forward, turn at junctions)

void VoxelScene::step() {
    double da = targetAngle_ - angle_;
    while (da > M_PI) da -= 2 * M_PI;
    while (da < -M_PI) da += 2 * M_PI;
    angle_ += std::max(-0.14, std::min(0.14, da));

    const double speed = 1.0 / (0.14 * 60.0); // match WorkerController 0.14s/tile at 60fps
    int col = (int)std::floor(px_), row = (int)std::floor(py_);
    double ccx = col + 0.5, ccy = row + 0.5;

    bool angleDone = std::abs(da) < 0.15;

    // Turn near a tile centre: take a ←/→ turn ONLY into an open lane (Pete never turns to
    // face a wall — a blocked turn stays queued for the next junction where that lane opens).
    // The down button queues the opposite heading, an about-face that ALWAYS corners here
    // since the lane behind Pete is open. Snap onto the square from up to ~0.4 tile away.
    bool hasDir = pressUp_;
    if (wantDirSet_) {
        bool atCenter = std::abs(px_ - ccx) < 0.4 && std::abs(py_ - ccy) < 0.4;
        if ((!hasDir && angleDone) || (hasDir && atCenter && open(col + wantDirX_, row + wantDirY_))) {
            px_ = ccx; py_ = ccy; moveDirX_ = wantDirX_; moveDirY_ = wantDirY_;
            if (pendingSecondTurn_) {
                wantDirX_ = moveDirY_; wantDirY_ = -moveDirX_; wantDirSet_ = true;
            } else {
                wantDirSet_ = false;
            }
            pendingSecondTurn_ = false;
            targetAngle_ = cardinal(moveDirX_, moveDirY_);
            if (moveDirX_ > 0) peteDirName_ = "EAST";
            else if (moveDirX_ < 0) peteDirName_ = "WEST";
            else if (moveDirY_ > 0) peteDirName_ = "SOUTH";
            else peteDirName_ = "NORTH";
        }
    }

    // Hold ↑ = forward along facing; release = stop in tracks. ↓ is an about-face (wantDir), not reverse.
    int tdx = moveDirX_;
    int tdy = moveDirY_;
    if (hasDir) {
        bool atCenter = std::abs(px_ - ccx) < 0.06 && std::abs(py_ - ccy) < 0.06;
        GridPos partner = atCenter && !open(col + tdx, row + tdy)
            ? gridMap_.tunnelPartner(GridPos{col, rowsCount_ - 1 - row}) : GridPos{-1, -1};
        if (partner.x >= 0) {
            px_ = partner.x + 0.5;
            py_ = (rowsCount_ - 1 - partner.y) + 0.5;
        } else {
            if (tdx != 0) py_ += std::max(-speed, std::min(speed, ccy - py_));
            else          px_ += std::max(-speed, std::min(speed, ccx - px_));
            if (open(col + tdx, row + tdy)) {
                px_ += tdx * speed; py_ += tdy * speed;
            } else {
                if (tdx > 0) px_ = std::min(px_ + speed, ccx);
                else if (tdx < 0) px_ = std::max(px_ - speed, ccx);
                if (tdy > 0) py_ = std::min(py_ + speed, ccy);
                else if (tdy < 0) py_ = std::max(py_ - speed, ccy);
            }
        }
    } else {
        px_ = ccx; py_ = ccy;
    }

    // Dots + small pickups (proximity within half a tile).
    for (auto& b : billboards_) {
        if (!b.alive || b.worldH >= 0.5) continue;
        if (std::abs(b.x - px_) < 0.5 && std::abs(b.y - py_) < 0.5) {
            b.alive = false;
            int bc = (int)b.x, br = (int)b.y;
            hiddenPickups_.insert(mapKey(bc, br));
            switch (tileAtRaster(bc, br)) {
            case Tile::goldDisc:
                sound_.playGoldDisc(); state_.collectedGoldDiscs++;
                state_.bumpScore(5); popPoints(5); startGoldDiscMode();
                break;
            case Tile::waterPellet:
                sound_.playWaterGunPickup(); state_.bumpScore(50); popPoints(50);
                if (waterGunPickedUp_) waterGun_.reloadPellets(8);
                break;
            default:
                sound_.playDotBlip(); state_.collectedDots++; state_.bumpScore(1);
                break;
            }
            refreshHUD();
            checkLevelComplete3D();
        }
    }
    billboards_.erase(std::remove_if(billboards_.begin(), billboards_.end(),
        [](const Billboard& b) { return !b.alive && b.worldH < 0.5; }),
        billboards_.end());

    collectStationary();
    moveShots();

    int pgx = (int)std::floor(px_), pgy = rowsCount_ - 1 - (int)std::floor(py_);
    bossController_.update(1.0 / 60.0, gridMap_, *pathfinder_, workerGrid_(), workerDir_(),
                           goldDiscActive_, peteShielded_,
                           [pgx, pgy](const BossEntity& e) {
                               return std::max(std::abs(e.grid.x - pgx), std::abs(e.grid.y - pgy)) > 3;
                           });
    travelerSpawner_.update(1.0 / 60.0, gridMap_);

    // Capture each boss's SMOOTH world position from boss.pixelPos (the mover holds
    // the truth; the raycaster never overwrites it in this port). pixelPos is this
    // port's y-DOWN screen pixels, so pixelPos/32 is already the continuous raster
    // top-down centre (x = col+0.5, y = rasterRow+0.5) the billboard projection wants.
    bossGrid_.assign(bossController_.entities.size(), {0.0, 0.0});
    for (size_t i = 0; i < bossController_.entities.size(); ++i) {
        auto& e = bossController_.entities[i];
        bossGrid_[i] = {(double)e.pixelPos.x / 32.0, (double)e.pixelPos.y / 32.0};
    }

    // Shielded exactly while bosses flash in (spawnGrace == any boss immobilized).
    peteShielded_ = false;
    for (size_t i = 0; i < bossController_.entities.size(); ++i)
        if (bossController_.entities[i].isActive && bossController_.isImmobilized((int)i)) {
            peteShielded_ = true; break;
        }

    checkBossCatch();
    for (auto& tr : travelerSpawner_.travelers) {   // walked onto the traveler's tile -> catch it
        if (tr.active && !tr.catching && tr.grid == workerGrid_()) {
            std::string caughtEmoji = tr.emoji;
            travelerSpawner_.catchTraveler(tr);
            state_.bumpScore(tr.points); sound_.playFishOrTreat(); popPoints(tr.points); refreshHUD();
            hud_.showMessage("Caught " + caughtEmoji + "!", 2.f);
        }
    }

    if (frightenSecondsLeft_ > 0) {
        frightenSecondsLeft_ -= 1.0 / 60.0;
        if (frightenSecondsLeft_ <= 0) endGoldDiscMode();
    }

    if (hasDir) {
        bob_ += 0.22;
        peteWalkPhase_ += 1.0 / 60.0; // seconds of walking, fed to the renderer's Swift-cadence clock
    }
}

// MARK: - workerGrid / workerDir (GridMap bottom-up)

GridPos VoxelScene::workerGrid_() const {
    return GridPos{(int)std::floor(px_), rowsCount_ - 1 - (int)std::floor(py_)};
}

MoveDirection VoxelScene::workerDir_() const {
    if (moveDirX_ > 0) return MoveDirection::Right;
    if (moveDirX_ < 0) return MoveDirection::Left;
    return moveDirY_ > 0 ? MoveDirection::Down : MoveDirection::Up;
}

// MARK: - Boss helpers

// MARK: - Boss catch

void VoxelScene::checkBossCatch() {
    int pgx = (int)std::floor(px_), pgy = rowsCount_ - 1 - (int)std::floor(py_);
    for (size_t i = 0; i < bossController_.entities.size(); ++i) {
        auto& e = bossController_.entities[i];
        if (!e.isActive) continue;
        if ((int)e.grid.x != pgx || (int)e.grid.y != pgy) continue;
        if (bossController_.isImmobilized((int)i)) continue;
        if (bossController_.isInFleeMode((int)i)) {
            std::string name = e.name;
            bossController_.capture((int)i, gridMap_);
            int pts = 100 * bossController_.captureStreak;
            state_.bumpScore(pts);
            sound_.playCaptureBoss(bossController_.captureStreak);
            popPoints(pts);
            refreshHUD();
        } else if (!peteShielded_) {
            startDeath((int)i);
            return;
        }
    }
}

// MARK: - Death close-up

void VoxelScene::startDeath(int bossIndex) {
    if (dying_) return;
    dying_ = true;
    deathBossIndex_ = bossIndex;
    sound_.playCaughtByBoss();
    if (goldDiscActive_) endGoldDiscMode();
    deathFramesLeft_ = deathFrames_;
}

void VoxelScene::updateDeath() {
    deathFramesLeft_--;
    if (deathFramesLeft_ <= 0) finishDeath();
}

void VoxelScene::finishDeath() {
    dying_ = false;
    deathBossIndex_ = -1;
    state_.lives -= 1;
    refreshHUD();
    if (state_.lives <= 0) {
        gameOver_ = true;
        sound_.stopBackgroundMusic();
        sound_.stopGoldDiscBass();
        sound_.playGameOver();
        return;
    }
    px_ = spawnPx_; py_ = spawnPy_; wantDirSet_ = false; pendingSecondTurn_ = false; pressUp_ = pressDown_ = false;
    int sc = (int)std::floor(spawnPx_), sr = (int)std::floor(spawnPy_);
    int dx[] = {1, 0, -1, 0}, dy[] = {0, 1, 0, -1};
    for (int i = 0; i < 4; ++i)
        if (open(sc + dx[i], sr + dy[i])) { moveDirX_ = dx[i]; moveDirY_ = dy[i]; break; }
    targetAngle_ = cardinal(moveDirX_, moveDirY_); angle_ = targetAngle_;
    bossController_.teleportAllToSpawn(gridMap_, *pathfinder_); // 3s spawnGrace
    bossGrid_.assign(bossController_.entities.size(), {0.0, 0.0});
}

// MARK: - Water gun shooting

void VoxelScene::fire() {
    if (!waterGun_.consumePellet()) return;
    sound_.playWaterGunShoot();
    refreshHUD();
    shots_.push_back(Shot{px_, py_, moveDirX_, moveDirY_, true, 0.f});
}

void VoxelScene::moveShots() {
    const double speed = 0.22;
    for (auto& s : shots_) {
        if (!s.alive) continue;
        s.x += s.dirX * speed;
        s.y += s.dirY * speed;
        s.spin += 0.22f;
        if (isWall(s.x, s.y)) { s.alive = false; continue; }
        int sgx = (int)std::floor(s.x), sgy = rowsCount_ - 1 - (int)std::floor(s.y);
        for (size_t i = 0; i < bossController_.entities.size(); ++i) {
            auto& e = bossController_.entities[i];
            if (!e.isActive) continue;
            if ((int)e.grid.x == sgx && (int)e.grid.y == sgy) {
                bossController_.splash((int)i, gridMap_, *pathfinder_);
                s.alive = false;
                sound_.playWaterGunSplash();
                state_.bumpScore(50); popPoints(50); refreshHUD();
                break;
            }
        }
    }
    shots_.erase(std::remove_if(shots_.begin(), shots_.end(),
        [](const Shot& s) { return !s.alive; }), shots_.end());
}

// MARK: - Stationary item collection

void VoxelScene::collectStationary() {
    int pcol = (int)std::floor(px_), prow = (int)std::floor(py_);
    if (prow < 0 || prow >= rowsCount_ || pcol < 0 || pcol >= (int)map_[prow].size()) return;
    char ch = map_[prow][pcol];
    if (ch == Tile::brownBox) {
        if (!onBrownBox_) { onBrownBox_ = true; collectTPSReport(); }
        return;
    }
    onBrownBox_ = false;
    int key = mapKey(pcol, prow);
    if (collected_.count(key)) return;
    switch (ch) {
    case Tile::waterGun:
        collected_.insert(key); waterGun_.activate(); waterGunPickedUp_ = true;
        state_.bumpScore(50); popPoints(50);
        sound_.playWaterGunPickup();
        billboards_.erase(std::remove_if(billboards_.begin(), billboards_.end(),
            [&](Billboard& b) { return (int)b.x == pcol && (int)b.y == prow; }), billboards_.end());
        hiddenPickups_.insert(key);
        refreshHUD();
        break;
    case Tile::printer:    collectMachine(Machine::PRINTER, key, pcol, prow); break;
    case Tile::fax:        collectMachine(Machine::FAX, key, pcol, prow); break;
    case Tile::coverSheet: collectMachine(Machine::COVER_SHEET, key, pcol, prow); break;
    case Tile::bookBinder: collectMachine(Machine::BOOK_BINDER, key, pcol, prow); break;
    default: break;
    }
}

void VoxelScene::collectMachine(const std::string& name, int key, int col, int row) {
    bool required = false;
    for (auto& n : Machine::REQUIRED) if (n == name) { required = true; break; }
    if (!required || state_.reportItems.count(name)) return;
    collected_.insert(key);
    state_.reportItems.insert(name);
    int itemIndex = (int)state_.reportItems.size() - 1; // points ramp 10/25/50/100
    if (itemIndex < (int)(sizeof(REPORT_ITEM_POINTS) / sizeof(int))) {
        int pts = REPORT_ITEM_POINTS[itemIndex];
        state_.bumpScore(pts); state_.currentReportScore += pts; popPoints(pts);
    }
    sound_.playMachine(name);
    // Gray (dim) the billboard + minimap pickup, don't remove it.
    for (auto& b : billboards_)
        if ((int)b.x == col && (int)b.y == row) b.alpha = 0.55f;
    if (state_.reportItems.size() == Machine::REQUIRED.size()) hud_.showMessage(Message::TPS_READY, 6.f);
    refreshHUD();
}

void VoxelScene::collectTPSReport() {
    if (state_.reportItems.size() != Machine::REQUIRED.size()) {
        std::string missing;
        for (auto& n : Machine::REQUIRED)
            if (!state_.reportItems.count(n)) missing += (missing.empty() ? "" : ", ") + n;
        hud_.showMessage("Missing: " + missing, 5.f);
        return;
    }
    state_.tpsReportsDelivered += 1;
    state_.reportItems.clear();
    int tpsPoints = state_.level * 100 + 100;
    state_.bumpScore(tpsPoints); state_.currentReportScore = 0;
    popPoints(tpsPoints);
    for (auto& b : billboards_)
        if (b.kind == Tile::brownBox) { b.alpha = 0.55f; b.cooldownTimer = MACHINE_COOLDOWN; }
    sound_.playTpsDeliver();
    bool gainedLife = state_.lives < MAX_LIVES;
    if (gainedLife) state_.lives += 1;
    resetCollectedMachines();
    refreshHUD();
    hud_.showMessage(gainedLife ? Message::TPS_TURNED_IN_LIFE : Message::TPS_TURNED_IN, 3.f);
    checkLevelComplete3D();
}

void VoxelScene::resetCollectedMachines() {
    for (int r = 0; r < rowsCount_; ++r) {
        for (int c = 0; c < (int)map_[r].size(); ++c) {
            char ch = map_[r][c];
            if (ch == Tile::printer || ch == Tile::fax ||
                ch == Tile::coverSheet || ch == Tile::bookBinder) {
                collected_.erase(mapKey(c, r));
                for (auto& b : billboards_)
                    if ((int)b.x == c && (int)b.y == r) b.alpha = 1.f;
            }
        }
    }
}

// MARK: - Level complete

void VoxelScene::checkLevelComplete3D() {
    if (wantsNextLevel_) return;
    bool dotsDone = state_.collectedDots >= state_.dotCount;
    bool discsDone = state_.collectedGoldDiscs >= state_.goldDiscCount;
    if (!dotsDone || !discsDone) return;
    if (state_.tpsReportsDelivered >= 1) {
        state_.advanceLevel();
        nextLevel_ = state_.level;
        hud_.showMessage(Message::levelLoaded(state_.level), 3.f);
        wantsNextLevel_ = true;
    } else {
        hud_.showMessage(Message::NEED_TPS, 3.f);
    }
}

// MARK: - Score popups (3D view + minimap mini)

void VoxelScene::popPoints(int n) {
    // 3D corridor: big yellow "+N" above Pete (Menlo-Bold 54), spawned 20px up and
    // rising fontSize*1.55 over 0.7s, exactly like ScorePopup.show(fontSize: 54).
    float peteBaseY = radarH_ + viewH() * 0.42f / 2.f + 6.f;
    float skY = peteBaseY + viewH() * 0.30f; // y-up, above Pete
    bigPops_.push_back(MiniPop{"+" + std::to_string(n),
                               {viewW_ / 2.f, screenY(skY + 20.f)}, 0.7f, 54.f});
    // Radar: a matching smaller yellow "+N" on Pete in the minimap (fontSize 40).
    sf::Vector2f petePos = mapLocal(px_, py_);
    miniPops_.push_back(MiniPop{"+" + std::to_string(n), petePos, 0.7f, 40.f});
}

// MARK: - Input

void VoxelScene::keyDown(int code, bool isRepeat) {
    if (gameOver_) return;
    if (code == K_ESC) { wantsExit_ = true; return; }
    if (code == K_P) { togglePause(); return; }
    if (isUserPaused_) return;
    if (code == K_SPACE) { if (!isRepeat) fire(); return; }
    if (code == K_LEFT || code == K_A) {
        wantDirSet_ = true; wantDirX_ = moveDirY_; wantDirY_ = -moveDirX_; // turn left
        return;
    }
    if (code == K_RIGHT || code == K_D) {
        wantDirSet_ = true; wantDirX_ = -moveDirY_; wantDirY_ = moveDirX_; // turn right
        return;
    }
    if (code == K_UP || code == K_W) { pressUp_ = true; return; }
    if (code == K_DOWN || code == K_S) {
        wantDirSet_ = true; wantDirX_ = moveDirY_; wantDirY_ = -moveDirX_; pendingSecondTurn_ = true;
        return;
    }
}

void VoxelScene::keyUp(int code) {
    if (code == K_UP || code == K_W) pressUp_ = false;
}

static float radiusBetween(sf::Vector2f a, sf::Vector2f b) {
    float dx = a.x - b.x, dy = a.y - b.y;
    return std::sqrt(dx * dx + dy * dy);
}

// Which wedge a point is in (single direction per finger; "" = centre/outside).
std::string VoxelScene::dpadWedgeAt(float x, float y) const {
    float dx = x - joystickCenter_.x, dy = y - joystickCenter_.y;
    float mag = std::sqrt(dx * dx + dy * dy);
    if (mag < joystickDeadzone_ || mag > joystickRadius_) return "";
    if (std::abs(dy) >= std::abs(dx)) return dy < 0 ? "up" : "down";   // SFML y down: up = forward
    return dx > 0 ? "right" : "left";
}

void VoxelScene::dpadSet(unsigned finger, float x, float y, int phase) {
    std::string prev = dpadFinger_.count(finger) ? dpadFinger_[finger] : std::string();
    std::string w = (phase == 2) ? std::string() : dpadWedgeAt(x, y);
    if (w.empty()) dpadFinger_.erase(finger); else dpadFinger_[finger] = w;
    // STICK mode: the thumb rides the finger (direction still comes from dpadWedgeAt).
    if (phase == 2) joystickThumb_ = joystickCenter_;
    else {
        float dx = x - joystickCenter_.x, dy = y - joystickCenter_.y;
        float mag = std::sqrt(dx * dx + dy * dy), lim = joystickRadius_ * 0.58f;
        joystickThumb_ = (mag > lim && mag > 0.f) ? sf::Vector2f(joystickCenter_.x + dx / mag * lim, joystickCenter_.y + dy / mag * lim) : sf::Vector2f(x, y);
    }
    // One-shot turn the moment a finger ENTERS a turn wedge: left/right = 90°, down = 180°.
    if (!w.empty() && w != prev) {
        if (w == "left")       { wantDirSet_ = true; wantDirX_ = moveDirY_;  wantDirY_ = -moveDirX_; }
        else if (w == "right") { wantDirSet_ = true; wantDirX_ = -moveDirY_; wantDirY_ = moveDirX_; }
        else if (w == "down")  { wantDirSet_ = true; wantDirX_ = moveDirY_; wantDirY_ = -moveDirX_; pendingSecondTurn_ = true; }
    }
    applyDpad();
}

void VoxelScene::applyDpad() {
    bool up = false, down = false, left = false, right = false;
    for (auto& fw : dpadFinger_) {
        const std::string& w = fw.second;
        if (w == "up") up = true; else if (w == "down") down = true;
        else if (w == "left") left = true; else if (w == "right") right = true;
    }
    pressUp_ = up; pressDown_ = false;   // up = forward (held); down is a 180° turn, not reverse
    dpadUp_ = up; dpadDown_ = down; dpadLeft_ = left; dpadRight_ = right;
}

// Shared pointer body: two fingers can hold two wedges (forward + a turn) at once.
void VoxelScene::pointer(unsigned finger, float x, float y, int phase) {
    if (isUserPaused_ || dying_ || gameOver_) return;
    if (!controlsShown_) { if (phase == 0) fire(); return; } // gun hidden: a tap fires
    if (phase == 0) {
        if (radiusBetween({x, y}, joystickCenter_) <= joystickRadius_) { dpadSet(finger, x, y, 0); return; }
        if (radiusBetween({x, y}, fireButtonCenter_) <= fireButtonRadius_) fire();
        return;
    }
    if (dpadFinger_.count(finger)) dpadSet(finger, x, y, phase);   // move/up only steer D-pad fingers
}

// Real per-finger touch (phone). Marks touch active so the synthetic finger-0
// mouse pointer (the host emits both) stops fighting the real fingers.
void VoxelScene::touch(unsigned finger, float x, float y, int phase) {
    usingTouch_ = true;
    pointer(finger, x, y, phase);
}

// Desktop mouse = a single finger; ignored once a real touch has arrived.
void VoxelScene::mouseDown(float x, float y)    { if (usingTouch_) return; pointer(0, x, y, 0); }
void VoxelScene::mouseDragged(float x, float y) { if (usingTouch_) return; pointer(0, x, y, 1); }
void VoxelScene::mouseUp()                      { if (usingTouch_) return; pointer(0, 0.f, 0.f, 2); }

// MARK: - Rendering
//
// The raycaster math is ported verbatim from the SpriteKit master, which uses a
// y-up screen (0 at the bottom, viewMidY the horizon). Every y is converted to the
// SFML y-down target at draw time with screenY(); the geometry (DDA, perpendicular
// distance, wall heights, perspective) is identical.

void VoxelScene::render(sf::RenderTarget& target) {
    drawSky(target);

    double dirX = std::cos(angle_), dirY = std::sin(angle_);
    double planeX = -dirY * planeScale_, planeY = dirX * planeScale_;

    // Camera trails behind Pete; pull in if it would sit inside a wall.
    double back = camBack_;
    while (back > 0.05 && isWall(px_ - dirX * back, py_ - dirY * back)) back -= 0.1;
    camX_ = px_ - dirX * back; camY_ = py_ - dirY * back;

    drawFloor(target, dirX, dirY, planeX, planeY);
    auto wallQuads = renderVoxelWalls(dirX, dirY, planeX, planeY);
    projectSprites(dirX, dirY, planeX, planeY);

    // Interleave wall quads and sprites by depth (farthest first) so closer walls
    // correctly occlude farther sprites. Wall quads use dAvg (perp distance);
    // sprites use tY (also perp distance). Sort descending: largest distance first.
    struct Drawable { double depth; int kind; int idx; };
    // kind 0=wallQuad, 1=billboard, 2=shot, 3=boss
    std::vector<Drawable> order;
    order.reserve(wallQuads.size() + billboards_.size() + shots_.size() + bossProj_.size());
    for (size_t i = 0; i < wallQuads.size(); ++i)
        order.push_back({wallQuads[i].depth, 0, (int)i});
    for (size_t i = 0; i < billboards_.size(); ++i)
        if (billboards_[i].visible) order.push_back({billboards_[i].rawDepth, 1, (int)i});
    if (!dying_)
        for (size_t i = 0; i < shots_.size(); ++i)
            if (shots_[i].visible) order.push_back({shots_[i].rawDepth, 2, (int)i});
    for (size_t i = 0; i < bossProj_.size(); ++i)
        if (bossProj_[i].visible) order.push_back({bossProj_[i].rawDepth, 3, (int)i});
    std::sort(order.begin(), order.end(),
              [](const Drawable& a, const Drawable& b) { return a.depth > b.depth; });
    for (auto& d : order) {
        if (d.kind == 0) {
            auto& q = wallQuads[d.idx];
            sf::ConvexShape quad(4);
            quad.setPoint(0, {q.x0, screenY(q.y0)});
            quad.setPoint(1, {q.x1, screenY(q.y1)});
            quad.setPoint(2, {q.x2, screenY(q.y2)});
            quad.setPoint(3, {q.x3, screenY(q.y3)});
            quad.setFillColor(q.color);
            quad.setOutlineThickness(0);
            target.draw(quad);
        } else if (d.kind == 1) drawBillboardSprite(target, billboards_[d.idx]);
        else if (d.kind == 2) drawShotSprite(target, shots_[d.idx]);
        else if (d.kind == 3) drawBossBillboard(target, d.idx);
    }

    // Traveler emoji billboard (fish/treat): project its grid tile and draw it like the 2D modes,
    // occluded by the nearest wall across its footprint, behind Pete.
    {
        double invDet = 1.0 / (planeX * dirY - dirX * planeY);
        for (auto& tr : travelerSpawner_.travelers) {
            if (!tr.active && !tr.catching) continue;
            double wx = tr.grid.x + 0.5, wy = (rowsCount_ - 1 - tr.grid.y) + 0.5;
            double relX = wx - camX_, relY = wy - camY_;
            double tX = invDet * (dirY * relX - dirX * relY);
            double tY = invDet * (-planeY * relX + planeX * relY); // depth
            if (tY <= 0.15 || tY > 18) continue;
            int col = (int)((viewW_ / 2.f) * (float)(1 + tX / tY) / (viewW_ / columns_));
            if (col >= 0 && col < columns_) {
                double wallZ = zbuf_[col];
                for (int c = std::max(0, col - 1); c <= std::min(columns_ - 1, col + 1); ++c) wallZ = std::min(wallZ, zbuf_[c]);
                if (tY > wallZ + 0.3) continue; // wall occludes the traveler
            }
            float screenX = (viewW_ / 2.f) * (float)(1 + tX / tY);
            if (screenX <= -60 || screenX >= viewW_ + 60) continue;
            float targetH = (float)(viewH() / tY * 0.42);
            float floorYUp = viewMidY() - (float)(viewH() / tY) / 2.f;
            float scl = tr.catching ? tr.catchScale : 1.f;
            uint8_t a = (uint8_t)((tr.catching ? tr.catchAlpha : 1.f) * 255);
            drawEmoji(target, tr.emoji, sf::Vector2f(screenX, screenY(floorYUp + targetH * 0.5f)),
                      targetH * scl, sf::Color(255, 255, 255, a), tr.flipX);
        }
    }

    // Pete avatar: rear silhouette, always in front of every billboard (z=90), with
    // a vertical head-bob. During the death close-up he fades to 0.2 alpha.
    {
        static PixelPersonRenderer peteRenderer(peteBackConfig());
        float target_h = viewH() * 0.42f;
        auto m = peteRenderer.metrics();
        float scale = target_h / m.height;
        float peteBaseY = radarH_ + target_h / 2.f + 6.f; // y-up centre
        float bobY = (float)(std::sin(bob_) * 4.0);
        float cx = viewW_ / 2.f;
        float cy = screenY(peteBaseY + bobY);
        bool moving = pressUp_ || pressDown_;
        float alpha = dying_ ? 0.2f : 1.0f;
        peteRenderer.draw(target, {cx, cy}, false, moving, MoveDirection::None,
                          (float)peteWalkPhase_, alpha, scale);
        if (!dying_)
            drawCenteredText(target, peteDirName_, 22.f, sf::Color::White,
                             cx, screenY(peteBaseY + target_h / 2.f + 16.f));
    }

    // Death close-up: the REAL catching boss, scaled to Pete's size, centred in the
    // viewport, in front of everything (z above Pete). update() freezes the sim
    // while dying so the boss holds still exactly here.
    if (dying_ && deathBossIndex_ >= 0 && deathBossIndex_ < (int)bossController_.entities.size()) {
        auto& e = bossController_.entities[deathBossIndex_];
        auto m = e.renderer.metrics();
        float scale = viewH() * 0.42f / m.height;
        float cx = viewW_ / 2.f;
        // Grounded where Pete + the dots stand: plant the boss's soles on Pete's feet
        // line, Pete-sized, drawn over the faded Pete. No jump onto Pete's shoulders.
        PixelPersonRenderer peteRef(peteBackConfig());
        auto pm = peteRef.metrics();
        float peteScale = viewH() * 0.42f / pm.height;
        float peteFeetYUp = radarH_ + viewH() * 0.42f / 2.f + 6.f - pm.feetOffset * peteScale;
        float originYUp = peteFeetYUp + m.feetOffset * scale;
        e.renderer.draw(target, {cx, screenY(originYUp)}, e.facingLeft, false, MoveDirection::None,
                        0.f, 1.0f, scale);
    }

    // 3D-corridor score popups (Menlo-Bold 54, yellow): above the billboards but
    // below the minimap panel (z 12 < 200), so a popup descending into the radar is
    // covered by the panel — exactly like the SpriteKit ScorePopup z-order.
    for (auto& m : bigPops_) {
        uint8_t a = (uint8_t)(std::clamp(m.timer / 0.7f, 0.f, 1.f) * 255);
        drawCenteredText(target, m.text, m.fontSize, sf::Color(255, 231, 0, a),
                         m.pos.x, m.pos.y);
    }

    drawMap(target);
    drawControls(target);
    hud_.draw(target, (float)WINDOW_WIDTH, (float)WINDOW_HEIGHT);
}

void VoxelScene::drawSky(sf::RenderTarget& target) {
    // Sky: gradient from horizon (0.10,0.10,0.13) to ceiling (0.02,0.02,0.035).
    // Floor: flat region below the horizon, (0.11,0.12,0.13). Both above the radar.
    float skyBottom = viewMidY(), skyTop = viewHeight_; // y-up
    int n = std::max(1, (int)(skyTop - skyBottom));
    // Ceiling + floor derive from the level's cubicle colour (dark at the ceiling,
    // a touch brighter at the horizon) so the whole 3D environment matches the level.
    const Color cube = CUBICLE_COLORS[(state_.level - 1) % 12];
    sf::VertexArray sky(sf::Quads);
    auto lerp = [](float a, float b, float t) { return a + (b - a) * t; };
    for (int i = 0; i < n; ++i) {
        float t = (float)i / (float)std::max(1, n - 1); // 0 horizon .. 1 ceiling
        sf::Color col((uint8_t)(lerp(cube.r * 0.18f, cube.r * 0.05f, t) * 255),
                      (uint8_t)(lerp(cube.g * 0.18f, cube.g * 0.05f, t) * 255),
                      (uint8_t)(lerp(cube.b * 0.18f, cube.b * 0.05f, t) * 255));
        float yTop = screenY(skyBottom + i + 1);
        float yBot = screenY(skyBottom + i);
        sky.append(sf::Vertex({0.f, yTop}, col));
        sky.append(sf::Vertex({viewW_, yTop}, col));
        sky.append(sf::Vertex({viewW_, yBot}, col));
        sky.append(sf::Vertex({0.f, yBot}, col));
    }
    target.draw(sky);

    {
        const int glowN = 60;
        const float glowBottom = viewMidY();
        sf::VertexArray glow(sf::Quads);
        for (int i = 0; i < glowN; ++i) {
            float t = 1.0f - (float)i / (float)std::max(1, glowN - 1);
            uint8_t alpha = (uint8_t)(t * t * 0.55f * 255);
            sf::Color gc(255, (uint8_t)(0.82f * 255), (uint8_t)(0.35f * 255), alpha);
            float yTop = screenY(glowBottom + i + 1);
            float yBot = screenY(glowBottom + i);
            glow.append(sf::Vertex({0.f, yTop}, gc));
            glow.append(sf::Vertex({viewW_, yTop}, gc));
            glow.append(sf::Vertex({viewW_, yBot}, gc));
            glow.append(sf::Vertex({0.f, yBot}, gc));
        }
        target.draw(glow);

        const float glowH = (float)glowN;
        const float shaftW = viewW_ * 0.045f;
        const float shaftH = glowH * 0.85f;
        sf::Color shaftCol(255, (uint8_t)(0.92f * 255), (uint8_t)(0.60f * 255), (uint8_t)(0.18f * 255));
        for (int s = 0; s < 5; ++s) {
            float cx = viewW_ * 0.1f + s * (viewW_ * 0.8f / 4.f);
            float shaftTop = screenY(glowBottom + 4.f + shaftH);
            float shaftBot = screenY(glowBottom + 4.f);
            sf::RectangleShape shaft({shaftW, shaftBot - shaftTop});
            shaft.setPosition(cx - shaftW / 2.f, shaftTop);
            shaft.setFillColor(shaftCol);
            target.draw(shaft);
        }
    }

    sf::RectangleShape ground({viewW_, viewMidY() - radarH_});
    ground.setPosition(0.f, screenY(viewMidY())); // top of floor band (y-down)
    ground.setFillColor(sf::Color((uint8_t)(cube.r * 0.12f * 255), (uint8_t)(cube.g * 0.12f * 255),
                                  (uint8_t)(cube.b * 0.12f * 255))); // dark level-tinted floor base
    target.draw(ground);
}

// Floor-cast the maze floor as an alternating checker so the tile grid reads in 3D.
// Lodev-style: each device row below the horizon maps to a perpendicular distance d
// (from the wall projection: floor at d sits at y-up viewMidY - viewH/(2d)); the
// world position sweeps from the leftmost to the rightmost camera ray across the row.
// Cell parity (mapX+mapY) picks the shade. Painted before the walls, which overdraw
// the occluded far floor.
void VoxelScene::drawFloor(sf::RenderTarget& target, double dirX, double dirY,
                          double planeX, double planeY) {
    double rdx0 = dirX - planeX, rdy0 = dirY - planeY;   // leftmost ray (cameraX = -1)
    double rdx1 = dirX + planeX, rdy1 = dirY + planeY;   // rightmost ray (cameraX = +1)
    const float horizonDY = screenY(viewMidY());          // device-y of the horizon
    const float bottomDY  = screenY(radarH_);             // device-y of the floor band bottom
    const Color lc = CUBICLE_COLORS[(state_.level - 1) % 12];
    const sf::Color colA((uint8_t)(lc.r * 0.13f * 255), (uint8_t)(lc.g * 0.13f * 255), (uint8_t)(lc.b * 0.13f * 255)),
                    colB((uint8_t)(lc.r * 0.24f * 255), (uint8_t)(lc.g * 0.24f * 255), (uint8_t)(lc.b * 0.24f * 255)),
                    colFar((uint8_t)(lc.r * 0.19f * 255), (uint8_t)(lc.g * 0.19f * 255), (uint8_t)(lc.b * 0.19f * 255));
    const int W = (int)viewW_;
    sf::VertexArray quads(sf::Quads);
    int yStart = (int)std::ceil(horizonDY) + 1, yEnd = (int)std::floor(bottomDY);
    for (int dy = yStart; dy <= yEnd; ++dy) {
        float distFromHorizon = (float)dy - horizonDY;
        if (distFromHorizon <= 0.5f) continue;
        double d = viewH() * eyeHeight_ / distFromHorizon;     // perpendicular floor distance (matches the walls' eye height)
        if (d > 13) {   // checker cells shrink below ~1px here and alias to garbage; fill solid to the horizon
            float y0 = (float)dy, y1 = (float)dy + 1.f;
            quads.append(sf::Vertex({0.f, y0}, colFar));
            quads.append(sf::Vertex({(float)W, y0}, colFar));
            quads.append(sf::Vertex({(float)W, y1}, colFar));
            quads.append(sf::Vertex({0.f, y1}, colFar));
            continue;
        }
        double fx = camX_ + d * rdx0, fy = camY_ + d * rdy0;
        double stepX = d * (rdx1 - rdx0) / W, stepY = d * (rdy1 - rdy0) / W;
        int runStart = 0;
        int runParity = (((int)std::floor(fx)) + ((int)std::floor(fy))) & 1;
        for (int x = 1; x <= W; ++x) {
            int parity = -1;
            if (x < W) {
                double wx = fx + stepX * x, wy = fy + stepY * x;
                parity = (((int)std::floor(wx)) + ((int)std::floor(wy))) & 1;
            }
            if (parity != runParity) {
                sf::Color c = runParity ? colA : colB;
                float x0 = (float)runStart, x1 = (float)x, y0 = (float)dy, y1 = (float)dy + 1.f;
                quads.append(sf::Vertex({x0, y0}, c));
                quads.append(sf::Vertex({x1, y0}, c));
                quads.append(sf::Vertex({x1, y1}, c));
                quads.append(sf::Vertex({x0, y1}, c));
                runStart = x; runParity = parity;
            }
        }
    }
    target.draw(quads);
}

void VoxelScene::renderWalls(sf::RenderTarget& target, double dirX, double dirY,
                            double planeX, double planeY) {
    std::vector<float> cTop(columns_), cBot(columns_);
    std::vector<double> cDist(columns_);
    std::vector<int> cSide(columns_), cFace(columns_), cPar(columns_);
    std::vector<bool> cOpen(columns_);

    for (int i = 0; i < columns_; ++i) {
        double cameraX = 2.0 * (i + 0.5) / columns_ - 1.0;
        double rdx = dirX + planeX * cameraX, rdy = dirY + planeY * cameraX;
        int mapX = (int)std::floor(camX_), mapY = (int)std::floor(camY_);
        double ddx = rdx == 0 ? 1e30 : std::abs(1 / rdx);
        double ddy = rdy == 0 ? 1e30 : std::abs(1 / rdy);
        int stepX, stepY; double sideX, sideY;
        if (rdx < 0) { stepX = -1; sideX = (camX_ - mapX) * ddx; }
        else         { stepX = 1;  sideX = (mapX + 1 - camX_) * ddx; }
        if (rdy < 0) { stepY = -1; sideY = (camY_ - mapY) * ddy; }
        else         { stepY = 1;  sideY = (mapY + 1 - camY_) * ddy; }
        int side = 0, guardN = 0; bool hitWall = false;
        while (guardN < 256) {
            guardN++;
            if (sideX < sideY) { sideX += ddx; mapX += stepX; side = 0; }
            else               { sideY += ddy; mapY += stepY; side = 1; }
            if (mapY < 0 || mapY >= rowsCount_ || mapX < 0 || mapX >= colsCount_) break;
            if (map_[mapY][mapX] == Tile::wall) { hitWall = true; break; }
        }
        double perp = side == 0 ? (sideX - ddx) : (sideY - ddy);
        double d = hitWall ? std::max(0.05, perp) : 1e9;
        float lineH = std::min((float)viewH() * 4.f, (float)(viewH() / d));
        cTop[i] = viewMidY() + lineH / 2.f; // y-up
        cBot[i] = viewMidY() - lineH / 2.f;
        cDist[i] = d; cSide[i] = side; cOpen[i] = !hitWall;
        cFace[i] = hitWall ? (side == 0 ? (stepX > 0 ? mapX : mapX + 1) * 2
                                        : (stepY > 0 ? mapY : mapY + 1) * 2 + 1) : -1;
        cPar[i] = (mapX + mapY) & 1;   // wall-cell parity -> per-cell checker shade (aligns with the floor)
        zbuf_[i] = d;
    }

    float w = viewW_ / (float)columns_;
    // Cubicle/wall colour for this level, matching the 2D game (CUBICLE_COLORS by level);
    // shaded per-quad by depth + side so it reads as the same wall in first person.
    const Color cube = CUBICLE_COLORS[(state_.level - 1) % 12];
    sf::VertexArray walls(sf::Quads);
    int i = 0;
    while (i < columns_) {
        if (cOpen[i]) { i++; continue; }
        int j = i;
        while (j + 1 < columns_ && cFace[j + 1] == cFace[i] && cPar[j + 1] == cPar[i]) j++;
        float xL = i * w, xR = (j + 1) * w + 1; // 1px overlap hides AA seams
        float topL = cTop[i], topR = cTop[j], botL = cBot[i], botR = cBot[j];
        if (j > i) {
            float cxL = (i + 0.5f) * w, cxR = (j + 0.5f) * w;
            float mT = (cTop[j] - cTop[i]) / (cxR - cxL);
            float mB = (cBot[j] - cBot[i]) / (cxR - cxL);
            topL = cTop[i] + mT * (xL - cxL); topR = cTop[i] + mT * (xR - cxL);
            botL = cBot[i] + mB * (xL - cxL); botR = cBot[i] + mB * (xR - cxL);
        }
        int mid = (i + j) / 2;
        float f = std::max(0.12f, std::min(1.0f, 1.0f - (float)cDist[mid] / 16.f))
                  * (cSide[i] == 1 ? 0.62f : 1.0f)
                  * (cPar[i] ? 1.0f : 0.82f);   // adjacent cells alternate shade for grid readability
        sf::Color col((uint8_t)(cube.r * f * 255), (uint8_t)(cube.g * f * 255),
                      (uint8_t)(cube.b * f * 255));
        // y-up quad -> SFML y-down via screenY.
        walls.append(sf::Vertex({xL, screenY(botL)}, col));
        walls.append(sf::Vertex({xL, screenY(topL)}, col));
        walls.append(sf::Vertex({xR, screenY(topR)}, col));
        walls.append(sf::Vertex({xR, screenY(botR)}, col));
        i = j + 1;
    }
    target.draw(walls);
}

auto VoxelScene::renderVoxelWalls(double dirX, double dirY,
                                  double planeX, double planeY) -> std::vector<VQuad> {
    const Color cube = CUBICLE_COLORS[(state_.level - 1) % 12];
    const float vMid = viewMidY(), vH = viewH();
    const double wallH = wallHeightScale_;
    const double wallFar = maxVoxelDist_;

    std::vector<VQuad> quads;

    std::unordered_set<int> tops;
    for (int col = 0; col < columns_; ++col) {
        double cameraX = 2.0 * (col + 0.5) / columns_ - 1.0;
        double rdx = dirX + planeX * cameraX, rdy = dirY + planeY * cameraX;
        int mapX = (int)std::floor(camX_), mapY = (int)std::floor(camY_);
        double ddx = rdx == 0 ? 1e30 : std::abs(1 / rdx), ddy = rdy == 0 ? 1e30 : std::abs(1 / rdy);
        int stepX, stepY; double sideX, sideY;
        if (rdx < 0) { stepX = -1; sideX = (camX_ - mapX) * ddx; } else { stepX = 1; sideX = (mapX + 1 - mapX) * ddx; }
        if (rdy < 0) { stepY = -1; sideY = (camY_ - mapY) * ddy; } else { stepY = 1; sideY = (mapY + 1 - camY_) * ddy; }
        bool firstHit = true; int guardN = 0;
        while (guardN < 300) {
            guardN++;
            if (sideX < sideY) { sideX += ddx; mapX += stepX; } else { sideY += ddy; mapY += stepY; }
            if (mapY < 0 || mapY >= rowsCount_ || mapX < 0 || mapX >= colsCount_) break;
            double dEntry = (sideX - ddx < sideY - ddy) ? (sideX - ddx) : (sideY - ddy);
            if (dEntry > wallFar) break;
            if (map_[mapY][mapX] == Tile::wall) {
                double dN = std::max(0.05, dEntry);
                if (firstHit) { zbuf_[col] = dN; firstHit = false; }
                tops.insert(mapY * colsCount_ + mapX);
            }
        }
        if (firstHit) zbuf_[col] = 1e9;
    }
    int ptx = (int)std::floor(px_), pty = (int)std::floor(py_);
    for (int dy = -1; dy <= 1; ++dy)
        for (int dx = -1; dx <= 1; ++dx) {
            int tx = ptx + dx, ty = pty + dy;
            if (tx >= 0 && tx < colsCount_ && ty >= 0 && ty < rowsCount_ && map_[ty][tx] == Tile::wall)
                tops.insert(ty * colsCount_ + tx);
        }

    double invDet = 1.0 / (planeX * dirY - dirX * planeY);
    float capZ = (float)(wallHeightScale_ - eyeHeight_);

    for (int key : tops) {
        int tx = key % colsCount_, ty = key / colsCount_;
        double dtx0 = tx, dtx1 = tx + 1, dty0 = ty, dty1 = ty + 1;
        struct Face { int side; int faceV; int adx; int ady; };
        std::vector<Face> faces;
        if (camX_ <= dtx0) faces.push_back({0, tx, -1, 0});
        if (camX_ >= dtx1) faces.push_back({0, tx + 1, 1, 0});
        if (camY_ <= dty0) faces.push_back({1, ty, 0, -1});
        if (camY_ >= dty1) faces.push_back({1, ty + 1, 0, 1});
        for (auto& f : faces) {
            int adjX = tx + f.adx, adjY = ty + f.ady;
            bool exposed = adjX < 0 || adjX >= colsCount_ || adjY < 0 || adjY >= rowsCount_
                        || map_[adjY][adjX] != Tile::wall;
            if (!exposed) continue;
            double wx0 = f.side == 0 ? f.faceV : tx,     wy0 = f.side == 0 ? ty     : f.faceV;
            double wx1 = f.side == 0 ? f.faceV : tx + 1, wy1 = f.side == 0 ? ty + 1 : f.faceV;
            double rawA = invDet * (-planeY * (wx0 - camX_) + planeX * (wy0 - camY_));
            double rawB = invDet * (-planeY * (wx1 - camX_) + planeX * (wy1 - camY_));
            if (rawA < 0.1 && rawB < 0.1) continue;
            double tA = rawA < 0.1 ? (0.1 - rawA) / (rawB - rawA) : 0.0;
            double tB = rawB < 0.1 ? (0.1 - rawB) / (rawA - rawB) : 0.0;
            double eX0 = rawA < 0.1 ? wx0 + tA * (wx1 - wx0) : wx0;
            double eY0 = rawA < 0.1 ? wy0 + tA * (wy1 - wy0) : wy0;
            double eX1 = rawB < 0.1 ? wx1 + tB * (wx0 - wx1) : wx1;
            double eY1 = rawB < 0.1 ? wy1 + tB * (wy0 - wy1) : wy1;
            double eRA = std::max(0.1, rawA), eRB = std::max(0.1, rawB);
            double dAvg = (eRA + eRB) * 0.5;
            if (dAvg > wallFar) continue;
            double txA = invDet * (dirY * (eX0 - camX_) - dirX * (eY0 - camY_));
            double txB = invDet * (dirY * (eX1 - camX_) - dirX * (eY1 - camY_));
            float p0x = (float)(viewW_ / 2.0 * (1 + txA / eRA));
            float p0y = (float)(vMid + vH * (float)(-eyeHeight_) / (float)eRA);
            float p1x = (float)(viewW_ / 2.0 * (1 + txA / eRA));
            float p1y = (float)(vMid + vH * (float)(wallH - eyeHeight_) / (float)eRA);
            float p2x = (float)(viewW_ / 2.0 * (1 + txB / eRB));
            float p2y = (float)(vMid + vH * (float)(wallH - eyeHeight_) / (float)eRB);
            float p3x = (float)(viewW_ / 2.0 * (1 + txB / eRB));
            float p3y = (float)(vMid + vH * (float)(-eyeHeight_) / (float)eRB);
            int par = f.side == 0 ? (f.faceV + ty) & 1 : (tx + f.faceV) & 1;
            float faceF = (f.side == 1 ? 0.62f : 1.0f) * (par == 1 ? 1.0f : 0.82f);
            float fogT = std::min(1.0f, (float)(dAvg / wallFar)) * 0.85f;
            float cr = cube.r * faceF * (1.0f - fogT);
            float cg = cube.g * faceF * (1.0f - fogT);
            float cb = cube.b * faceF * (1.0f - fogT);
            sf::Color col((uint8_t)(cr * 255), (uint8_t)(cg * 255), (uint8_t)(cb * 255));
            quads.push_back({p0x,p0y, p1x,p1y, p2x,p2y, p3x,p3y, col, dAvg, false});
            const float topT = 0.18f, botT = 0.32f, hMarg = 0.18f;
            float lTx = p1x, lTy = p1y + (p0y - p1y) * topT;
            float lBx = p1x, lBy = p1y + (p0y - p1y) * botT;
            float rTx = p2x, rTy = p2y + (p3y - p2y) * topT;
            float rBx = p2x, rBy = p2y + (p3y - p2y) * botT;
            float gp0x = lBx + (rBx - lBx) * hMarg,       gp0y = lBy + (rBy - lBy) * hMarg;
            float gp1x = lTx + (rTx - lTx) * hMarg,       gp1y = lTy + (rTy - lTy) * hMarg;
            float gp2x = lTx + (rTx - lTx) * (1.f - hMarg), gp2y = lTy + (rTy - lTy) * (1.f - hMarg);
            float gp3x = lBx + (rBx - lBx) * (1.f - hMarg), gp3y = lBy + (rBy - lBy) * (1.f - hMarg);
            float gv = std::max(0.1f, std::min(1.0f, 1.0f - (float)(dAvg / wallFar))) * 0.62f;
            sf::Color grayC((uint8_t)(gv * 255), (uint8_t)(gv * 255), (uint8_t)(gv * 255));
            quads.push_back({gp0x,gp0y, gp1x,gp1y, gp2x,gp2y, gp3x,gp3y, grayC, dAvg - 0.001, false});
        }
    }

    const int corners[4][2] = {{0,0},{1,0},{1,1},{0,1}};
    for (int key : tops) {
        double cx = key % colsCount_, cy = key / colsCount_;
        float qx[4], qy[4]; double dsum = 0;
        for (int k = 0; k < 4; ++k) {
            double relX = (cx + corners[k][0]) - camX_, relY = (cy + corners[k][1]) - camY_;
            double raw = invDet * (-planeY * relX + planeX * relY);
            double depth = std::max(0.05, raw);
            dsum += raw;
            double transX = invDet * (dirY * relX - dirX * relY);
            qx[k] = (float)(viewW_ / 2.0 * (1 + transX / depth));
            qy[k] = (float)(vMid + vH * capZ / depth);
        }
        if (dsum / 4 < -0.5) continue;
        double dAvg = std::max(0.05, dsum / 4);
        if (dAvg > wallFar) continue;
        int par = ((int)cx + (int)cy) & 1;
        float f = (par == 1 ? 1.0f : 0.82f);
        float br = cube.r * f, bg = cube.g * f, bb = cube.b * f;
        br += (1.0f - br) * 0.3f; bg += (1.0f - bg) * 0.3f; bb += (1.0f - bb) * 0.3f;
        float capFogT = std::min(1.0f, (float)(dAvg / wallFar)) * 0.85f;
        br *= (1.0f - capFogT); bg *= (1.0f - capFogT); bb *= (1.0f - capFogT);
        sf::Color col((uint8_t)(br * 255), (uint8_t)(bg * 255), (uint8_t)(bb * 255));
        quads.push_back({qx[0],qy[0], qx[1],qy[1], qx[2],qy[2], qx[3],qy[3], col, dAvg, true});
    }

    std::sort(quads.begin(), quads.end(), [](const VQuad& a, const VQuad& b) {
        if (a.isCap != b.isCap) return !a.isCap;
        return a.depth > b.depth;
    });
    return quads;
}

void VoxelScene::projectSprites(double dirX, double dirY, double planeX, double planeY) {
    double invDet = 1.0 / (planeX * dirY - dirX * planeY);

    auto project = [&](double x, double y, double worldH,
                       bool& visible, float& screenXOut, float& scaleOut,
                       float& floorYOut, float& depthOut, double& rawDepthOut, float nativeH) {
        visible = false;
        double relX = x - camX_, relY = y - camY_;
        double tX = invDet * (dirY * relX - dirX * relY);
        double tY = invDet * (-planeY * relX + planeX * relY); // depth
        if (tY <= 0.15) return;
        int col = (int)((viewW_ / 2.f) * (float)(1 + tX / tY) / (viewW_ / columns_));
        if (col >= 0 && col < columns_) {
            double wallZ = zbuf_[col];
            for (int c = std::max(0, col - 4); c <= std::min(columns_ - 1, col + 4); ++c)
                wallZ = std::min(wallZ, zbuf_[c]);
            if (tY > wallZ + 0.3) return; // wall occludes
        }
        if (tY > 18) return; // far cull
        float screenX = (viewW_ / 2.f) * (float)(1 + tX / tY);
        if (screenX <= -60 || screenX >= viewW_ + 60) return;
        float targetH = (float)(viewH() / tY * worldH);
        visible = true;
        screenXOut = screenX;
        scaleOut = targetH / nativeH;
        floorYOut = viewMidY() - (float)(viewH() / tY) * (float)eyeHeight_;
        depthOut = std::min(40.f, (float)(2 + 30 / tY));
        rawDepthOut = tY;
    };

    // Pellets / gold / water / machines / brown box.
    for (auto& b : billboards_) {
        if (!b.alive) { b.visible = false; continue; }
        float nativeH = (b.kind == Tile::dot || b.kind == Tile::hideout) ? 8.f * 1.24f
                       : (b.kind == Tile::goldDisc || b.kind == Tile::waterPellet) ? 27.f
                       : 128.f;
        project(b.x, b.y, b.worldH, b.visible, b.screenX, b.scale, b.floorY, b.depthZ, b.rawDepth, nativeH);
    }
    // Shots (water pellets, waterPelletVisual radius 9 -> halo r*1.35 -> frame 24.3).
    for (auto& s : shots_) {
        if (!s.alive) { s.visible = false; continue; }
        project(s.x, s.y, 0.32, s.visible, s.screenX, s.scale, s.floorY, s.depthZ, s.rawDepth, 9.f * 2.f * 1.35f);
    }

    // Bosses: worldH 0.3 (no size cap), feet on the floor via the LOCAL feet offset.
    bossProj_.assign(bossController_.entities.size(), BossProj{false, 0, 0, 0, 0, 0, 0.0});
    for (size_t i = 0; i < bossController_.entities.size(); ++i) {
        auto& e = bossController_.entities[i];
        if (!e.isActive && !e.isCaptured && !e.captureReturning) continue;
        if (i >= bossGrid_.size()) continue;
        float nativeH = std::max(1.f, e.renderer.metrics().height);
        BossProj bp{false, 0, 0, 0, 0, 0, 0.0};
        project(bossGrid_[i].first, bossGrid_[i].second, 0.3,
                bp.visible, bp.screenX, bp.scale, bp.floorY, bp.depthZ, bp.rawDepth, nativeH);
        bp.targetH = bp.scale * nativeH;
        bossProj_[i] = bp;
    }
}

void VoxelScene::drawBillboardSprite(sf::RenderTarget& target, const Billboard& b) {
    // Feet planted on the floor row: positionY = floorY - bottom*scale, where bottom
    // is the LOCAL frame.minY (centred sprites pass -nativeH/2), matching the master.
    // The throb (gold/water/water-gun) multiplies the rendered size like the
    // SpriteKit child scale action; pellets are small so feet stay planted.
    uint8_t a = (uint8_t)(b.alpha * 255);
    float cx = b.screenX;
    float t = animTime_;
    float goldThrob = 1.0f + 0.25f * (0.5f - 0.5f * std::cos(t * 8.976f));
    float pelletThrob = 1.0f + 0.30f * (0.5f - 0.5f * std::cos(t * 7.854f));
    if (b.kind == Tile::dot || b.kind == Tile::hideout) {
        // SpriteFactory.pelletCube(size: 8): a solid box in head-on 1-point
        // perspective. Front is a true yellow square; the only other visible face
        // is a symmetric gold trapezoid top whose side edges converge straight up to
        // a single vanishing point centred above the box. The node's accumulated
        // frame is size*(1 + 0.24) tall, so the billed nativeH/bottom follow that.
        const float size = 8.f;
        float nativeH = size * 1.24f, bottom = -nativeH / 2.f;
        float originY = screenY(b.floorY - bottom * b.scale); // local (0,0) in y-down
        float sc = b.scale;
        float h = size / 2.f;
        float topH = size * 0.24f;
        float backHalf = h * 0.5f;
        // Local y-up point -> SFML y-down screen point about the node origin.
        auto P = [&](float lx, float ly) {
            return sf::Vertex({cx + lx * sc, originY - ly * sc});
        };
        sf::Color gold(209, 158, 20, a);   // calibratedRed 0.82, green 0.62, blue 0.08
        sf::Color yellow(255, 231, 0, a);  // systemYellow
        sf::ConvexShape topFace(4);        // gold trapezoid (z=0, behind front)
        topFace.setPoint(0, P(-h, h).position);
        topFace.setPoint(1, P(h, h).position);
        topFace.setPoint(2, P(backHalf, h + topH).position);
        topFace.setPoint(3, P(-backHalf, h + topH).position);
        topFace.setFillColor(gold);
        target.draw(topFace);
        sf::ConvexShape frontFace(4);      // yellow front square (z=1, on top)
        frontFace.setPoint(0, P(-h, -h).position);
        frontFace.setPoint(1, P(h, -h).position);
        frontFace.setPoint(2, P(h, h).position);
        frontFace.setPoint(3, P(-h, h).position);
        frontFace.setFillColor(yellow);
        target.draw(frontFace);
    } else if (b.kind == Tile::goldDisc || b.kind == Tile::waterPellet) {
        // SpriteFactory.goldDiscVisual / waterPelletVisual (radius 10): a soft halo
        // (r*1.35), a solid core (r) with a thin stroke, and a white specular
        // highlight (r*0.3) offset up-left. The throb scales the whole disc.
        bool gold = (b.kind == Tile::goldDisc);
        float r = 10.f * b.scale * (gold ? goldThrob : pelletThrob);
        const float nativeH = 27.f, bottom = -nativeH / 2.f; // halo r*1.35 -> frame 27
        float cy = screenY(b.floorY - bottom * b.scale);     // node origin (centred), feet via -nativeH/2
        auto disc = [&](float radius, sf::Color fill, float strokeW = 0.f,
                        sf::Color stroke = sf::Color::Transparent,
                        float ox = 0.f, float oy = 0.f) {
            sf::CircleShape c(radius, 28);
            c.setOrigin(radius, radius);
            c.setPosition(cx + ox, cy - oy); // oy is y-up, flip to y-down
            c.setFillColor(fill);
            if (strokeW > 0.f) { c.setOutlineThickness(strokeW); c.setOutlineColor(stroke); }
            target.draw(c);
        };
        sf::Color haloCol = gold ? sf::Color(255, 231, 0, (uint8_t)(0.30f * a))
                                 : sf::Color(50, 200, 240, (uint8_t)(0.25f * a)); // systemCyan
        sf::Color coreCol = gold ? sf::Color(255, 231, 0, (uint8_t)(0.85f * a))
                                 : sf::Color(50, 200, 240, (uint8_t)(0.85f * a));
        sf::Color strokeCol = gold ? sf::Color(178, 127, 0, a)   // bossShoeGold 0.70,0.50,0.0
                                   : sf::Color(10, 122, 255, a);  // systemBlue
        float strokeW = std::max(1.f, (gold ? 1.0f : 1.5f) * b.scale);
        disc(r * 1.35f, haloCol);
        disc(r, coreCol, strokeW, strokeCol);
        disc(r * 0.3f, sf::Color(255, 255, 255, (uint8_t)(0.75f * a)), 0.f,
             sf::Color::Transparent, -r * 0.28f, r * 0.28f);
    } else {
        // Emoji billboard (machine / brown box / water gun). nativeH 128 (the
        // SpriteKit emoji point size); draw at targetSize = nativeH*scale. The water
        // gun power-up throbs like the gold disc.
        float nativeH = 128.f, bottom = -nativeH / 2.f;
        float cy = screenY(b.floorY - bottom * b.scale);
        float throb = (b.kind == Tile::waterGun) ? goldThrob : 1.0f;
        float targetSize = nativeH * b.scale * throb;
        drawEmoji(target, pickupEmoji(b.kind), {cx, cy}, targetSize,
                  sf::Color(255, 255, 255, a));
    }
}

void VoxelScene::drawShotSprite(sf::RenderTarget& target, const Shot& s) {
    // SpriteFactory.waterPelletVisual(radius: 9): halo (r*1.35) + core (r, blue
    // stroke 1.5) + white specular (r*0.3) offset up-left.
    float r = 9.f * s.scale;
    float cx = s.screenX;
    const float nativeH = 9.f * 2.f * 1.35f, bottom = -nativeH / 2.f; // halo r*1.35
    float cy = screenY(s.floorY - bottom * s.scale);                  // centred origin
    auto disc = [&](float radius, sf::Color fill, float strokeW = 0.f,
                    sf::Color stroke = sf::Color::Transparent, float ox = 0.f, float oy = 0.f) {
        sf::CircleShape c(radius, 24);
        c.setOrigin(radius, radius);
        c.setPosition(cx + ox, cy - oy);
        c.setFillColor(fill);
        if (strokeW > 0.f) { c.setOutlineThickness(strokeW); c.setOutlineColor(stroke); }
        target.draw(c);
    };
    disc(r * 1.35f, sf::Color(50, 200, 240, 64));                          // systemCyan @ 0.25
    disc(r, sf::Color(50, 200, 240, 217), std::max(1.f, 1.5f * s.scale),   // systemCyan @ 0.85
         sf::Color(10, 122, 255, 255));                                    // systemBlue stroke
    disc(r * 0.3f, sf::Color(255, 255, 255, 191), 0.f, sf::Color::Transparent,
         -r * 0.28f, r * 0.28f);                                           // white specular @ 0.75
}

void VoxelScene::drawBossBillboard(sf::RenderTarget& target, int bossIndex) {
    if (dying_) return; // death close-up draws the catcher itself; hide world bosses
    if (bossIndex >= (int)bossProj_.size() || !bossProj_[bossIndex].visible) return;
    auto& e = bossController_.entities[bossIndex];
    const BossProj& bp = bossProj_[bossIndex];

    // Feet planted on the floor via the LOCAL feet offset (frame.minY); centred Pete
    // metrics give feetOffset DOWN from origin, so the y-up local bottom is -feetOffset.
    float bottom = -e.renderer.metrics().feetOffset;
    // Post-spawn pulse (matches the 2D BossController): a freshly respawned boss throbs
    // while it can't yet catch Pete (spawn grace), then settles to full size and goes live.
    float scale = bp.scale;
    if (e.throbTimer > 0.0f) {
        float progress = 1.0f - e.throbTimer / SPAWN_THROB_DUR;
        scale *= 1.0f + 0.18f * std::abs(std::sin(progress * 3.14159265f * 3.0f));
    }
    float cx = bp.screenX;
    float cy = screenY(bp.floorY - bottom * scale);   // feet stay planted as it throbs

    // freezeLook(): eyes/tie centred (lookDir None), but the legs/arms keep WALKING
    // as the boss glides down the corridor toward Pete (e.isMoving / e.walkPhase),
    // matching the SpriteKit boss node whose walk action runs while the look is frozen.
    float alpha = e.fadeInAlpha;
    if (e.isCaptured || e.captureReturning) alpha = e.captureAlpha;
    e.renderer.draw(target, {cx, cy}, e.facingLeft, e.isMoving, MoveDirection::None,
                    e.walkPhase, alpha, scale);

    // Nameplate above the boss (flee shows the next capture value in yellow).
    float fontSize = std::max(13.f, std::min(24.f, bp.targetH * 0.16f));
    bool flee = bossController_.isInFleeMode(bossIndex);
    std::string tag = flee ? std::to_string(100 * (bossController_.captureStreak + 1)) : e.name;
    sf::Color tagColor = flee ? PixelPersonRenderer::toSfColor(YELLOW) : sf::Color::White;
    drawCenteredText(target, tag, fontSize, tagColor,
                     cx, screenY(bp.floorY + bp.targetH + fontSize * 0.7f));
}

void VoxelScene::drawMap(sf::RenderTarget& target) {
    // Panel: dark background spanning the radar band, drawn ABOVE all 3D sprites so
    // nothing ever draws over the minimap.
    sf::RectangleShape panel({viewW_, radarH_});
    panel.setPosition(0.f, screenY(radarH_));
    panel.setFillColor(sf::Color(10, 10, 13)); // (0.04,0.04,0.05)
    target.draw(panel);

    float cell = mapCell_ * mapScale_;

    // Floor checkerboard + walls.
    for (int r = 0; r < rowsCount_; ++r) {
        for (int c = 0; c < (int)map_[r].size(); ++c) {
            sf::Vector2f p = mapLocal(c + 0.5, r + 0.5);
            sf::RectangleShape floor({cell, cell});
            floor.setOrigin(cell / 2.f, cell / 2.f);
            floor.setPosition(p);
            bool alt = (c + r) % 2 == 0;
            floor.setFillColor(alt ? sf::Color(28, 31, 33) : sf::Color(23, 26, 28));
            target.draw(floor);
            if (map_[r][c] == Tile::wall) {
                sf::RectangleShape wall({cell, cell});
                wall.setOrigin(cell / 2.f, cell / 2.f);
                wall.setPosition(p);
                const Color& cub = CUBICLE_COLORS[(state_.level - 1) % 12];   // current level's colour
                wall.setFillColor(sf::Color((uint8_t)(cub.r * 255 * 0.55f),
                                            (uint8_t)(cub.g * 255 * 0.55f),
                                            (uint8_t)(cub.b * 255 * 0.55f)));
                target.draw(wall);
            }
        }
    }

    // Pickups (dots + machines/gold/water), hidden when collected.
    float t = animTime_;
    float goldScale = 1.0f + 0.25f * (0.5f - 0.5f * std::cos(t * 8.976f));
    for (int r = 0; r < rowsCount_; ++r) {
        for (int c = 0; c < (int)map_[r].size(); ++c) {
            char ch = map_[r][c];
            int key = mapKey(c, r);
            if (hiddenPickups_.count(key)) continue;
            sf::Vector2f p = mapLocal(c + 0.5, r + 0.5);
            float alpha = 1.f;
            for (auto& b : billboards_)
                if ((int)b.x == c && (int)b.y == r) alpha = b.alpha;
            uint8_t a = (uint8_t)(alpha * 255);
            if (ch == Tile::dot || ch == Tile::hideout) {
                float r2 = mapCell_ * 0.1f * mapScale_;
                sf::CircleShape dot(r2, 10);
                dot.setOrigin(r2, r2);
                dot.setPosition(p);
                dot.setFillColor(sf::Color(255, 231, 0, a));
                target.draw(dot);
            } else if (ch == Tile::goldDisc || ch == Tile::waterPellet) {
                bool gold = (ch == Tile::goldDisc);
                float r2 = mapCell_ * (gold ? 0.28f : 0.32f) * mapScale_ * goldScale;
                sf::CircleShape core(r2, 16);
                core.setOrigin(r2, r2);
                core.setPosition(p);
                core.setFillColor(gold ? sf::Color(255, 231, 0, a) : sf::Color(0, 200, 240, a));
                target.draw(core);
            } else if (pickupEmoji(ch).size() > 0) {
                drawEmoji(target, pickupEmoji(ch), p, mapCell_ * 0.7f * mapScale_,
                          sf::Color(255, 255, 255, a));
            }
        }
    }

    // Bosses on the radar (flee palette mirrored via the controller's renderer).
    for (size_t i = 0; i < bossController_.entities.size(); ++i) {
        auto& e = bossController_.entities[i];
        if (!e.isActive && !e.isCaptured && !e.captureReturning) continue;
        if (i >= bossGrid_.size()) continue;
        auto g = bossGrid_[i];
        sf::Vector2f p = mapLocal(g.first, g.second);
        e.renderer.draw(target, p, e.facingLeft, e.isMoving, e.lookDir, e.walkPhase,
                        1.0f, mapScale_ * 0.9f);
    }

    // Shots on the radar.
    for (auto& s : shots_) {
        if (!s.alive) continue;
        sf::Vector2f p = mapLocal(s.x, s.y);
        float r2 = mapCell_ * 0.22f * mapScale_;
        sf::CircleShape dot(r2, 12);
        dot.setOrigin(r2, r2);
        dot.setPosition(p);
        dot.setFillColor(sf::Color(50, 200, 240, 217));
        target.draw(dot);
    }

    // Pete on the radar.
    {
        static PixelPersonRenderer mapPete(PersonConfig{PETE_BODY, PETE_TIE, PETE_HAIR,
                                                        PETE_SHOE_OUT, PETE_PANTS, SKIN_COLOR});
        sf::Vector2f p = mapLocal(px_, py_);
        bool moving = pressUp_ || pressDown_;
        MoveDirection face = workerDir_();
        mapPete.draw(target, p, face == MoveDirection::Left, moving, face,
                     (float)peteWalkPhase_, 1.0f, mapScale_ * 0.9f);

        const float r = 11.7f;
        float throb = 1.0f + 0.125f * (1.0f - std::cos(animTime_ * 6.2832f / 0.7f));
        sf::ConvexShape arrow(4);
        arrow.setPoint(0, sf::Vector2f(0.f,        -r));
        arrow.setPoint(1, sf::Vector2f(-r * 0.55f,  r * 0.55f));
        arrow.setPoint(2, sf::Vector2f(0.f,          r * 0.2f));
        arrow.setPoint(3, sf::Vector2f( r * 0.55f,  r * 0.55f));
        arrow.setFillColor(sf::Color::White);
        arrow.setOutlineThickness(1.5f);
        arrow.setOutlineColor(sf::Color(0, 0, 0, 179));
        arrow.setOrigin(0.f, 0.f);
        const float pad = 14.f;
        sf::Vector2f ap = p;
        if      (face == MoveDirection::Right) ap.x += pad;
        else if (face == MoveDirection::Left)  ap.x -= pad;
        else if (face == MoveDirection::Down)  ap.y += pad;
        else                                   ap.y -= pad;
        arrow.setPosition(ap);
        arrow.setScale(throb, throb);
        float deg = 0.f;
        if      (face == MoveDirection::Right) deg =  90.f;
        else if (face == MoveDirection::Left)  deg = 270.f;
        else if (face == MoveDirection::Down)  deg = 180.f;
        arrow.setRotation(deg);
        target.draw(arrow);
    }

    // Traveler on the radar.
    for (auto& tr : travelerSpawner_.travelers) {
        if (!tr.active && !tr.catching) continue;
        sf::Vector2f p = mapLocal(tr.pixelPos.x / 32.0, tr.pixelPos.y / 32.0);
        drawEmoji(target, tr.emoji, p, mapCell_ * 1.2f * mapScale_, sf::Color::White, tr.flipX);
    }

    // Minimap mini score popups (fontSize 40, scaled into the radar like mapLayer).
    for (auto& m : miniPops_) {
        uint8_t a = (uint8_t)(std::clamp(m.timer / 0.7f, 0.f, 1.f) * 255);
        drawCenteredText(target, m.text, m.fontSize * mapScale_, sf::Color(255, 231, 0, a),
                         m.pos.x, m.pos.y);
    }
}

void VoxelScene::drawControls(sf::RenderTarget& target) {
    if (!controlsShown_) return;

    // Fire button ring (centers are already in SFML y-down logical coords).
    sf::CircleShape ring(fireButtonRadius_, 64);
    ring.setOrigin(fireButtonRadius_, fireButtonRadius_);
    ring.setPosition(fireButtonCenter_);
    ring.setFillColor(sf::Color(255, 255, 255, 36));  // white @ 0.14
    ring.setOutlineThickness(2.f);
    ring.setOutlineColor(sf::Color(255, 255, 255, 128)); // white @ 0.5
    target.draw(ring);

    // D-pad base outline.
    const float PI = 3.14159265f;
    sf::CircleShape base(joystickRadius_, 64);
    base.setOrigin(joystickRadius_, joystickRadius_);
    base.setPosition(joystickCenter_);
    base.setFillColor(sf::Color(255, 255, 255, 15));   // white @ 0.06
    base.setOutlineThickness(2.f);
    base.setOutlineColor(sf::Color(255, 255, 255, 128));
    target.draw(base);

    if (ControlMode::showsStick()) {   // STICK: a round follow-thumb instead of the wedge cross
        float tr = joystickRadius_ * 0.42f;
        sf::CircleShape thumb(tr, 48);
        thumb.setOrigin(tr, tr);
        thumb.setPosition(joystickThumb_);
        thumb.setFillColor(sf::Color(255, 255, 255, 56));    // white @ 0.22
        thumb.setOutlineThickness(2.f);
        thumb.setOutlineColor(sf::Color(255, 255, 255, 153)); // white @ 0.6
        target.draw(thumb);
        return;
    }

    // Four ring-sector wedges (X-split, meeting at the diagonals); active ones brighten.
    struct Wedge { float ang; bool on; };
    Wedge wedges[4] = {{-PI / 2, dpadUp_}, {PI / 2, dpadDown_}, {0.f, dpadRight_}, {PI, dpadLeft_}};
    for (const auto& w : wedges) {
        float a0 = w.ang - PI / 4, a1 = w.ang + PI / 4;
        const int steps = 14;
        sf::VertexArray strip(sf::TriangleStrip);
        sf::Color fill(255, 255, 255, w.on ? 87 : 31);   // 0.34 : 0.12
        for (int i = 0; i <= steps; ++i) {
            float t = a0 + (a1 - a0) * (float)i / steps;
            strip.append(sf::Vertex({joystickCenter_.x + std::cos(t) * joystickDeadzone_,
                                     joystickCenter_.y + std::sin(t) * joystickDeadzone_}, fill));
            strip.append(sf::Vertex({joystickCenter_.x + std::cos(t) * joystickRadius_,
                                     joystickCenter_.y + std::sin(t) * joystickRadius_}, fill));
        }
        target.draw(strip);
    }

    // X boundary lines (the four diagonals).
    sf::VertexArray xlines(sf::Lines);
    sf::Color line(255, 255, 255, 128);
    for (int k = 0; k < 4; ++k) {
        float t = PI / 4 + (float)k * PI / 2;   // 45 / 135 / 225 / 315
        xlines.append(sf::Vertex({joystickCenter_.x + std::cos(t) * joystickDeadzone_,
                                  joystickCenter_.y + std::sin(t) * joystickDeadzone_}, line));
        xlines.append(sf::Vertex({joystickCenter_.x + std::cos(t) * joystickRadius_,
                                  joystickCenter_.y + std::sin(t) * joystickRadius_}, line));
    }
    target.draw(xlines);

    // Direction arrow (triangle) at each wedge centre.
    float midR = (joystickDeadzone_ + joystickRadius_) / 2.f, s = 13.f;
    for (const auto& w : wedges) {
        sf::ConvexShape tri(3);
        tri.setPoint(0, {std::cos(w.ang) * s, std::sin(w.ang) * s});
        tri.setPoint(1, {std::cos(w.ang + 2.5f) * s, std::sin(w.ang + 2.5f) * s});
        tri.setPoint(2, {std::cos(w.ang - 2.5f) * s, std::sin(w.ang - 2.5f) * s});
        tri.setPosition(joystickCenter_.x + std::cos(w.ang) * midR, joystickCenter_.y + std::sin(w.ang) * midR);
        tri.setFillColor(sf::Color(255, 255, 255, 178));
        target.draw(tri);
    }
}

} // namespace bm
