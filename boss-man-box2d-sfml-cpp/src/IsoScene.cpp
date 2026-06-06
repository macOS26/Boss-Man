#include "IsoScene.hpp"
#include "SoundManager.hpp"
#include "PixelPersonRenderer.hpp"
#include "EmojiText.hpp"
#include "Assets.hpp"
#include "UiScale.hpp"
#include "Settings.hpp"
#include <SFML/Window/Keyboard.hpp>
#include <algorithm>
#include <cmath>

namespace bm {

namespace {

constexpr int K_ESC = sf::Keyboard::Escape, K_P = sf::Keyboard::P, K_SPACE = sf::Keyboard::Space;
constexpr int K_LEFT = sf::Keyboard::Left, K_RIGHT = sf::Keyboard::Right;
constexpr int K_UP = sf::Keyboard::Up, K_DOWN = sf::Keyboard::Down;
constexpr int K_A = sf::Keyboard::A, K_D = sf::Keyboard::D, K_W = sf::Keyboard::W, K_S = sf::Keyboard::S;

const std::string EMO_PRINTER = "\xf0\x9f\x96\xa8\xef\xb8\x8f";
const std::string EMO_FAX     = "\xf0\x9f\x93\xa0";
const std::string EMO_COVER   = "\xf0\x9f\x93\x84";
const std::string EMO_BINDER  = "\xf0\x9f\x93\x9a";
const std::string EMO_BOX     = "\xf0\x9f\x93\xa6";
const std::string EMO_GUN     = "\xf0\x9f\x94\xab";

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

PersonConfig peteFrontConfig() {
    PersonConfig cfg{PETE_BODY, PETE_TIE, PETE_HAIR, PETE_SHOE_OUT, PETE_PANTS, SKIN_COLOR};
    cfg.walkExaggeration = 1.0f;
    return cfg;
}

sf::Color mul(Color c, float f) {
    return sf::Color((uint8_t)(c.r * f * 255), (uint8_t)(c.g * f * 255), (uint8_t)(c.b * f * 255));
}

void quad(sf::VertexArray& va, sf::Vector2f a, sf::Vector2f b, sf::Vector2f c, sf::Vector2f d, sf::Color col) {
    va.append(sf::Vertex(a, col));
    va.append(sf::Vertex(b, col));
    va.append(sf::Vertex(c, col));
    va.append(sf::Vertex(d, col));
}

// Layered power-up disc, matching SpriteFactory.goldDiscVisual / waterPelletVisual:
// soft halo (coreR*1.35), solid core (coreR) with a thin stroke, white specular
// (coreR*0.3) offset up-left. `c` is the disc CENTRE in y-down screen space.
void drawPowerDisc(sf::RenderTarget& t, sf::Vector2f c, float coreR, bool gold, uint8_t a) {
    auto disc = [&](float radius, sf::Color fill, float strokeW, sf::Color stroke, float ox, float oy) {
        sf::CircleShape s(radius, 28);
        s.setOrigin(radius, radius);
        s.setPosition(c.x + ox, c.y - oy);   // oy is y-up
        s.setFillColor(fill);
        if (strokeW > 0.f) { s.setOutlineThickness(strokeW); s.setOutlineColor(stroke); }
        t.draw(s);
    };
    sf::Color halo = gold ? sf::Color(255, 231, 0, (uint8_t)(0.30f * a)) : sf::Color(50, 200, 240, (uint8_t)(0.25f * a));
    sf::Color core = gold ? sf::Color(255, 231, 0, (uint8_t)(0.85f * a)) : sf::Color(50, 200, 240, (uint8_t)(0.85f * a));
    sf::Color strokeC = gold ? sf::Color(178, 127, 0, a) : sf::Color(10, 122, 255, a);
    float strokeW = std::max(1.f, coreR * (gold ? 0.10f : 0.14f));
    disc(coreR * 1.35f, halo, 0.f, sf::Color::Transparent, 0.f, 0.f);
    disc(coreR, core, strokeW, strokeC, 0.f, 0.f);
    disc(coreR * 0.3f, sf::Color(255, 255, 255, (uint8_t)(0.75f * a)), 0.f, sf::Color::Transparent,
         -coreR * 0.28f, coreR * 0.28f);
}

} // namespace

IsoScene::IsoScene(SoundManager& sound, RoundState& state,
                   const std::vector<std::string>& mapRows, int highScore)
    : sound_(sound), state_(state), map_(mapRows), gridMap_(32.f), highScore_(highScore) {
    rowsCount_ = (int)map_.size();
    colsCount_ = rowsCount_ > 0 ? (int)map_[0].size() : 0;
    viewW_ = (float)WINDOW_WIDTH;
    viewHeight_ = (float)WINDOW_HEIGHT;

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

    placeStart();
    setupProjection();
    setupControllers();
    buildIso();
    buildPickups();
    buildRadar();
    travelerSpawner_.setSound(&sound_);
    travelerSpawner_.reset();
    travelerSpawner_.scheduleVisits(state_.level, *pathfinder_);

    hud_.compactHud = true;
    refreshHUD();

    if (ControlMode::showsControl()) {
        controlsShown_ = true;
        bool fireOnLeft = !ControlMode::onLeft();
        float bottomY = viewHeight_ - (fireButtonRadius_ + 15.f);
        fireButtonCenter_ = sf::Vector2f(fireOnLeft ? fireButtonRadius_ : viewW_ - fireButtonRadius_, bottomY);
        joystickCenter_ = sf::Vector2f(fireOnLeft ? viewW_ - joystickRadius_ : joystickRadius_,
                                       viewHeight_ - (joystickRadius_ + 15.f));
        joystickThumb_ = joystickCenter_;
    }

    sound_.startBackgroundMusic(false);
}

// MARK: - Map helpers

char IsoScene::tileAtRaster(int c, int r) const {
    if (r < 0 || r >= rowsCount_ || c < 0 || c >= (int)map_[r].size()) return Tile::wall;
    return map_[r][c];
}
bool IsoScene::isWall(double x, double y) const {
    int c = (int)std::floor(x), r = (int)std::floor(y);
    if (r < 0 || r >= rowsCount_ || c < 0 || c >= (int)map_[r].size()) return true;
    return map_[r][c] == Tile::wall;
}
bool IsoScene::open(int c, int r) const {
    if (r < 0 || r >= rowsCount_ || c < 0 || c >= (int)map_[r].size()) return false;
    return map_[r][c] != Tile::wall;
}

// MARK: - Projection (parallel isometric, mirrors IsoScene.swift)

void IsoScene::setupProjection() {
    const double zoom = 2.4;
    isoTW_ = viewW_ / std::max(1, colsCount_) * zoom;
    isoTH_ = isoTW_ * 0.62;
    isoWH_ = isoTW_ * 0.46 - 2;
    pVpY_ = isoTH_ * 6;
}
double IsoScene::persp(double rowEdge) const {
    return pFocal_ / (pFocal_ + ((double)rowsCount_ - rowEdge));
}
sf::Vector2f IsoScene::proj(double colEdge, double rowEdge, double y) const {
    double p = persp(rowEdge);
    double x0 = (colEdge - colsCount_ / 2.0) * isoTW_;
    double y0 = -rowEdge * isoTH_ + y * isoWH_;
    return {(float)(x0 * p), (float)(pVpY_ + (y0 - pVpY_) * p)};
}

// MARK: - Setup

void IsoScene::placeStart() {
    int sc = 1, sr = 1; bool found = false;
    for (int r = 0; r < rowsCount_ && !found; ++r)
        for (int c = 0; c < (int)map_[r].size(); ++c)
            if (map_[r][c] == Tile::worker) { sc = c; sr = r; found = true; break; }
    if (!found)
        for (int r = 0; r < rowsCount_ && !found; ++r)
            for (int c = 0; c < (int)map_[r].size(); ++c)
                if (map_[r][c] != Tile::wall) { sc = c; sr = r; found = true; break; }
    px_ = sc + 0.5; py_ = sr + 0.5;
    spawnPx_ = px_; spawnPy_ = py_;
}

void IsoScene::setupControllers() {
    gridMap_.yOffset = 0.f;
    gridMap_.setRows(map_);
    pathfinder_ = std::make_unique<Pathfinder>(gridMap_);

    int sc = (int)std::floor(spawnPx_), sr = (int)std::floor(spawnPy_);
    GridPos spawnGrid{sc, rowsCount_ - 1 - sr};
    worker_ = std::make_unique<WorkerController>(spawnGrid, gridMap_);
    worker_->lastTileCallback = [this](GridPos g) { workerDidEnterTile(g); };
    worker_->applySpawnShield();

    bossController_.setSound(&sound_);
    bossController_.setDelegate(this);
    std::vector<std::pair<int, GridPos>> overrides;
    for (int r = 0; r < rowsCount_; ++r) {
        int gridY = rowsCount_ - 1 - r;
        for (int c = 0; c < (int)map_[r].size(); ++c) {
            char ch = map_[r][c];
            if (ch >= '1' && ch <= '4') overrides.push_back({ch - '1', GridPos{c, gridY}});
        }
    }
    bossController_.spawn(1, gridMap_, *pathfinder_, overrides);
    bossGrid_.assign(bossController_.entities.size(), {0.0, 0.0});
}

// MARK: - Maze geometry (built once into per-row quad arrays, painter sub-order)

void IsoScene::buildIso() {
    const Color cube = CUBICLE_COLORS[(state_.level - 1) % 12];
    Color cubeP[2] = {Color{cube.r * 0.82f, cube.g * 0.82f, cube.b * 0.82f, 1.f}, cube};
    sf::Color topP[2], frontP[2], sideP[2];
    for (int p = 0; p < 2; ++p) {
        topP[p]   = mul(cubeP[p], 1.0f);
        frontP[p] = mul(cubeP[p], 0.70f);
        sideP[p]  = mul(cubeP[p], 0.50f);
    }
    const sf::Color floorP[2] = {sf::Color(18, 18, 18), sf::Color(36, 36, 36)}; // white 0.07 / 0.14
    const sf::Color trimCol(128, 128, 128);                                     // systemGray
    const double mid = colsCount_ / 2.0;

    mazeRows_.assign(rowsCount_, sf::VertexArray(sf::Quads));
    dotColsPerRow_.assign(rowsCount_, {});
    dotRows_.assign(rowsCount_, sf::VertexArray(sf::Quads));

    // Bilinear point inside a quad (bl,br,tr,tl) for the trim band.
    auto L = [](sf::Vector2f bl, sf::Vector2f br, sf::Vector2f tr, sf::Vector2f tl, float u, float v) {
        float bx = bl.x + (br.x - bl.x) * u, by = bl.y + (br.y - bl.y) * u;
        float tx = tl.x + (tr.x - tl.x) * u, ty = tl.y + (tr.y - tl.y) * u;
        return sf::Vector2f(bx + (tx - bx) * v, by + (ty - by) * v);
    };

    for (int r = 0; r < rowsCount_; ++r) {
        std::vector<sf::Vertex> floorV, sideV, frontV, topV, trimV;
        for (int c = 0; c < std::min(colsCount_, (int)map_[r].size()); ++c) {
            char ch = map_[r][c];
            int par = (c + r) & 1;
            sf::Vector2f fNW = proj(c, r, 0), fNE = proj(c + 1, r, 0),
                         fSE = proj(c + 1, r + 1, 0), fSW = proj(c, r + 1, 0);
            if (ch == Tile::wall) {
                sf::Vector2f tNW = proj(c, r, 1), tNE = proj(c + 1, r, 1),
                             tSE = proj(c + 1, r + 1, 1), tSW = proj(c, r + 1, 1);
                auto push = [](std::vector<sf::Vertex>& v, sf::Vector2f a, sf::Vector2f b,
                               sf::Vector2f cc, sf::Vector2f d, sf::Color col) {
                    v.push_back({a, col}); v.push_back({b, col}); v.push_back({cc, col}); v.push_back({d, col});
                };
                push(frontV, fSW, fSE, tSE, tSW, frontP[par]);
                if (c + 0.5 < mid)      push(sideV, fNE, fSE, tSE, tNE, sideP[par]);
                else if (c + 0.5 > mid) push(sideV, fNW, fSW, tSW, tNW, sideP[par]);
                push(topV, tNW, tNE, tSE, tSW, topP[par]);
                // Cubicle trim band across the top face.
                push(trimV, L(tSW, tSE, tNE, tNW, 0.18f, 0.64f), L(tSW, tSE, tNE, tNW, 0.82f, 0.64f),
                            L(tSW, tSE, tNE, tNW, 0.82f, 0.78f), L(tSW, tSE, tNE, tNW, 0.18f, 0.78f), trimCol);
            } else {
                floorV.push_back({fNW, floorP[par]}); floorV.push_back({fNE, floorP[par]});
                floorV.push_back({fSE, floorP[par]}); floorV.push_back({fSW, floorP[par]});
                if (isDotTile(ch)) dotColsPerRow_[r].push_back(c);
            }
        }
        // Concatenate in painter sub-order: floor, side, front, top, trim.
        auto& va = mazeRows_[r];
        for (auto& v : floorV) va.append(v);
        for (auto& v : sideV)  va.append(v);
        for (auto& v : frontV) va.append(v);
        for (auto& v : topV)   va.append(v);
        for (auto& v : trimV)  va.append(v);

        if (!dotColsPerRow_[r].empty()) {
            isoDotsLeft_ += (int)dotColsPerRow_[r].size();
            rebuildDotRow(r);
        }
    }
}

void IsoScene::appendDotFaces(sf::VertexArray& va, int c, int r, bool gold) const {
    const sf::Color dotTop(255, 231, 0), dotFront(178, 162, 0), dotSide(127, 115, 0);
    double h = (gold ? 0.28 : 0.20) * 0.85;
    double cx0 = c + 0.5, ry0 = r + 0.5, mid = colsCount_ / 2.0;
    double yT = ((gold ? 1.2 : 0.95) * 0.85 * isoWH_ - 9) / std::max(1.0, isoWH_);
    auto lift = [](sf::Vector2f p) { return sf::Vector2f(p.x, p.y + 10.f); }; // matches Swift position.y += 10
    sf::Vector2f bNW = lift(proj(cx0 - h, ry0 - h, 0)), bNE = lift(proj(cx0 + h, ry0 - h, 0)),
                 bSE = lift(proj(cx0 + h, ry0 + h, 0)), bSW = lift(proj(cx0 - h, ry0 + h, 0));
    sf::Vector2f uNW = lift(proj(cx0 - h, ry0 - h, yT)), uNE = lift(proj(cx0 + h, ry0 - h, yT)),
                 uSE = lift(proj(cx0 + h, ry0 + h, yT)), uSW = lift(proj(cx0 - h, ry0 + h, yT));
    quad(va, bSW, bSE, uSE, uSW, dotFront);
    if (cx0 < mid)      quad(va, bNE, bSE, uSE, uNE, dotSide);
    else if (cx0 > mid) quad(va, bNW, bSW, uSW, uNW, dotSide);
    quad(va, uNW, uNE, uSE, uSW, dotTop);
}

void IsoScene::rebuildDotRow(int r) {
    sf::VertexArray va(sf::Quads);
    for (int c : dotColsPerRow_[r]) {
        if (isoDotCollected_.count(mapKey(c, r))) continue;
        appendDotFaces(va, c, r, map_[r][c] == Tile::goldDisc);
    }
    dotRows_[r] = va;
}

void IsoScene::buildPickups() {
    for (int r = 0; r < rowsCount_; ++r)
        for (int c = 0; c < (int)map_[r].size(); ++c) {
            char ch = map_[r][c];
            switch (ch) {
            case Tile::waterGun: case Tile::printer: case Tile::fax:
            case Tile::coverSheet: case Tile::bookBinder: case Tile::brownBox:
            case Tile::waterPellet: case Tile::goldDisc:
                pickups_.push_back({ch, c, r, true, 1.f});
                break;
            default: break;
            }
        }
}

// MARK: - HUD / gold disc / pause

void IsoScene::refreshHUD() {
    hud_.score = state_.score; hud_.highScore = state_.highScore; hud_.level = state_.level;
    hud_.collectedDots = state_.collectedDots; hud_.dotCount = state_.dotCount;
    hud_.tpsReports = state_.tpsReportsDelivered; hud_.reportItems = state_.reportItems;
    hud_.lives = state_.lives;
    hud_.waterGunActive = waterGun_.isActive; hud_.waterGunVisible = waterGunPickedUp_;
    hud_.waterGunPellets = waterGun_.pelletsRemaining; hud_.goldDiscActive = false;
}
void IsoScene::startGoldDiscMode() {
    goldDiscActive_ = true; bossController_.setGoldDiscActive(true);
    sound_.startGoldDiscBass(false); frightenSecondsLeft_ = goldDiscDuration_;
    hud_.showMessage(Message::GOLD_DISC_ACTIVE, 3.f); refreshHUD();
}
void IsoScene::endGoldDiscMode() {
    goldDiscActive_ = false; bossController_.setGoldDiscActive(false);
    sound_.stopGoldDiscBass(); frightenSecondsLeft_ = 0;
    hud_.showMessage(Message::GOLD_DISC_ENDED, 2.f); refreshHUD();
}
void IsoScene::togglePause() {
    isUserPaused_ = !isUserPaused_;
    if (isUserPaused_) { hud_.showMessage(Message::PAUSED, 9999.f); sound_.pauseAudio(); }
    else { hud_.showMessage("", 0.1f); sound_.resumeAudio(); }
}

// MARK: - Boss droplet evasion

MoveDirection IsoScene::dropletAxisThreatening(GridPos bossGrid) {
    for (auto& s : shots_) {
        if (!s.alive) continue;
        GridPos d{(int)std::floor(s.x), rowsCount_ - 1 - (int)std::floor(s.y)};
        MoveDirection dir = s.dirX > 0 ? MoveDirection::Right : s.dirX < 0 ? MoveDirection::Left
                          : (s.dirY > 0 ? MoveDirection::Down : MoveDirection::Up);
        if (dropletThreatens(d, dir, bossGrid)) return dir;
    }
    return MoveDirection::None;
}
bool IsoScene::dropletThreatens(GridPos d, MoveDirection dir, GridPos b) const {
    const int range = 8;
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
    if (dist > range) return false;
    GridPos step = d;
    for (int i = 0; i < dist; ++i) {
        step = {step.x + del.x, step.y + del.y};
        if (!gridMap_.isWalkable(step)) return false;
    }
    return true;
}

// MARK: - Per-frame

void IsoScene::update(float dt) {
    if (isUserPaused_ || gameOver_) { hud_.update(dt); return; }
    const float fixed = 1.f / 60.f;
    simAccumulator_ += dt;
    int guard = 0;
    while (simAccumulator_ >= fixed && guard < 4) {
        simAccumulator_ -= fixed; guard++;
        if (dying_) { updateDeath(); continue; }
        step();
    }
    animTime_ += dt;
    hud_.update(dt);
    for (auto& m : miniPops_) { m.timer -= dt; m.pos.y -= 60.f * dt; }
    miniPops_.erase(std::remove_if(miniPops_.begin(), miniPops_.end(),
        [](const MiniPop& m) { return m.timer <= 0; }), miniPops_.end());
    for (auto& m : bigPops_) { m.timer -= dt; m.pos.y -= (m.fontSize * 1.55f / 0.7f) * dt; }
    bigPops_.erase(std::remove_if(bigPops_.begin(), bigPops_.end(),
        [](const MiniPop& m) { return m.timer <= 0; }), bigPops_.end());
}

void IsoScene::step() {
    const float dt = 1.f / 60.f;
    worker_->update(dt, gridMap_);
    px_ = worker_->pixelPos.x / 32.0;
    py_ = worker_->pixelPos.y / 32.0;

    // Smooth traveler tracking (continuous raster centre + facing flip on horizontal moves).
    bool wasActive = travActive_;
    travActive_ = false;
    for (auto& tr : travelerSpawner_.travelers) {
        if (!tr.active && !tr.catching) continue;
        double nc = tr.pixelPos.x / 32.0, nr = tr.pixelPos.y / 32.0;
        double dx = nc - travCol_;
        if (wasActive && std::abs(dx) > 0.001 && std::abs(dx) < 2)
            travFlip_ = tr.facesRight ? (dx < 0 ? -1.f : 1.f) : (dx < 0 ? 1.f : -1.f);
        travCol_ = nc; travRow_ = nr; travEmoji_ = tr.emoji;
        travPoints_ = tr.points; travFacesRight_ = tr.facesRight; travActive_ = true;
        break;
    }

    moveShots();
    bossController_.update(1.0 / 60.0, gridMap_, *pathfinder_, workerGrid_(), workerDir_(),
                          goldDiscActive_, peteShielded_);
    travelerSpawner_.update(1.0 / 60.0, gridMap_);

    bossGrid_.assign(bossController_.entities.size(), {0.0, 0.0});
    for (size_t i = 0; i < bossController_.entities.size(); ++i)
        bossGrid_[i] = {(double)bossController_.entities[i].pixelPos.x / 32.0,
                        (double)bossController_.entities[i].pixelPos.y / 32.0};

    peteShielded_ = false;
    for (size_t i = 0; i < bossController_.entities.size(); ++i)
        if (bossController_.entities[i].isActive && bossController_.isImmobilized((int)i)) {
            peteShielded_ = true; break;
        }

    checkBossCatch();
    for (auto& tr : travelerSpawner_.travelers) {
        if (tr.active && !tr.catching && tr.grid == workerGrid_()) {
            travelerSpawner_.catchTraveler(tr);
            state_.bumpScore(tr.points); sound_.playFishOrTreat(); popPoints(tr.points); refreshHUD();
        }
    }

    if (frightenSecondsLeft_ > 0) {
        frightenSecondsLeft_ -= 1.0 / 60.0;
        if (frightenSecondsLeft_ <= 0) endGoldDiscMode();
    }
}

GridPos IsoScene::workerGrid_() const {
    return GridPos{(int)std::floor(px_), rowsCount_ - 1 - (int)std::floor(py_)};
}
MoveDirection IsoScene::workerDir_() const {
    return worker_->direction;
}

void IsoScene::checkBossCatch() {
    int pgx = (int)std::floor(px_), pgy = rowsCount_ - 1 - (int)std::floor(py_);
    for (size_t i = 0; i < bossController_.entities.size(); ++i) {
        auto& e = bossController_.entities[i];
        if (!e.isActive) continue;
        if ((int)e.grid.x != pgx || (int)e.grid.y != pgy) continue;
        if (bossController_.isImmobilized((int)i)) continue;
        if (bossController_.isInFleeMode((int)i)) {
            bossController_.capture((int)i, gridMap_);
            int pts = 100 * bossController_.captureStreak;
            state_.bumpScore(pts); sound_.playCaptureBoss(bossController_.captureStreak);
            popPoints(pts); refreshHUD();
        } else if (!peteShielded_) {
            startDeath((int)i); return;
        }
    }
}

void IsoScene::startDeath(int bossIndex) {
    if (dying_) return;
    dying_ = true; deathBossIndex_ = bossIndex;
    sound_.playCaughtByBoss();
    if (goldDiscActive_) endGoldDiscMode();
    deathFramesLeft_ = deathFrames_;
}
void IsoScene::updateDeath() {
    deathFramesLeft_--;
    if (deathFramesLeft_ <= 0) finishDeath();
}
void IsoScene::finishDeath() {
    dying_ = false; deathBossIndex_ = -1;
    state_.lives -= 1; refreshHUD();
    if (state_.lives <= 0) {
        gameOver_ = true; sound_.stopBackgroundMusic(); sound_.stopGoldDiscBass(); sound_.playGameOver();
        return;
    }
    int sc = (int)std::floor(spawnPx_), sr = (int)std::floor(spawnPy_);
    GridPos spawnGrid{sc, rowsCount_ - 1 - sr};
    worker_->teleport(spawnGrid, gridMap_);
    worker_->resetMotion();
    worker_->applySpawnShield();
    px_ = spawnPx_; py_ = spawnPy_;
    bossController_.teleportAllToSpawn(gridMap_, *pathfinder_);
    bossGrid_.assign(bossController_.entities.size(), {0.0, 0.0});
}

// MARK: - Water gun

void IsoScene::fire() {
    if (worker_->direction == MoveDirection::None) return;
    if (!waterGun_.consumePellet()) return;
    sound_.playWaterGunShoot(); refreshHUD();
    auto del = bm::delta(worker_->direction);
    shots_.push_back(Shot{px_, py_, del.x, del.y, true, 0.f});
}
void IsoScene::moveShots() {
    const double speed = 0.22;
    for (auto& s : shots_) {
        if (!s.alive) continue;
        s.x += s.dirX * speed; s.y += s.dirY * speed; s.spin += 0.22f;
        if (isWall(s.x, s.y)) { s.alive = false; continue; }
        int sgx = (int)std::floor(s.x), sgy = rowsCount_ - 1 - (int)std::floor(s.y);
        for (size_t i = 0; i < bossController_.entities.size(); ++i) {
            auto& e = bossController_.entities[i];
            if (!e.isActive) continue;
            if ((int)e.grid.x == sgx && (int)e.grid.y == sgy) {
                bossController_.splash((int)i, gridMap_, *pathfinder_);
                s.alive = false; sound_.playWaterGunSplash();
                state_.bumpScore(50); popPoints(50); refreshHUD();
                break;
            }
        }
    }
    shots_.erase(std::remove_if(shots_.begin(), shots_.end(),
        [](const Shot& s) { return !s.alive; }), shots_.end());
}

// MARK: - Pickups (event-driven: WorkerController fires this on each tile arrival)

void IsoScene::hidePickup(int col, int row) {
    int key = mapKey(col, row);
    for (auto& p : pickups_) if (p.col == col && p.row == row) p.alive = false;
    hiddenPickups_.insert(key);
}

void IsoScene::workerDidEnterTile(GridPos grid) {
    int c = grid.x, r = rowsCount_ - 1 - grid.y;
    if (r < 0 || r >= rowsCount_ || c < 0 || c >= (int)map_[r].size()) return;
    int key = mapKey(c, r);
    char ch = map_[r][c];
    if (isDotTile(ch)) {
        if (isoDotCollected_.count(key)) return;
        isoDotCollected_.insert(key); isoDotsLeft_--;
        rebuildDotRow(r); hiddenPickups_.insert(key);
        sound_.playDotBlip(); state_.collectedDots++; state_.bumpScore(1); refreshHUD();
        return;
    }
    switch (ch) {
    case Tile::goldDisc:
        if (collected_.count(key)) return;
        collected_.insert(key); sound_.playGoldDisc(); state_.collectedGoldDiscs++;
        state_.bumpScore(5); popPoints(5); hidePickup(c, r); startGoldDiscMode(); refreshHUD();
        break;
    case Tile::waterGun:
        if (collected_.count(key)) return;
        collected_.insert(key); waterGun_.activate(); waterGunPickedUp_ = true;
        sound_.playWaterGunPickup(); state_.bumpScore(75); popPoints(75); hidePickup(c, r); refreshHUD();
        break;
    case Tile::waterPellet:
        if (collected_.count(key)) return;
        collected_.insert(key); state_.bumpScore(50); sound_.playWaterGunPickup(); popPoints(50);
        if (waterGunPickedUp_) waterGun_.reloadPellets(8);
        hidePickup(c, r); refreshHUD();
        break;
    case Tile::printer:    collectMachine(Machine::PRINTER, key, c, r); break;
    case Tile::fax:        collectMachine(Machine::FAX, key, c, r); break;
    case Tile::coverSheet: collectMachine(Machine::COVER_SHEET, key, c, r); break;
    case Tile::bookBinder: collectMachine(Machine::BOOK_BINDER, key, c, r); break;
    case Tile::brownBox:   collectTPSReport(c, r); break;
    default: break;
    }
}

void IsoScene::collectMachine(const std::string& name, int key, int col, int row) {
    bool required = false;
    for (auto& n : Machine::REQUIRED) if (n == name) { required = true; break; }
    if (!required || state_.reportItems.count(name)) return;
    collected_.insert(key); state_.reportItems.insert(name);
    int itemIndex = (int)state_.reportItems.size() - 1;
    if (itemIndex < (int)(sizeof(REPORT_ITEM_POINTS) / sizeof(int))) {
        int pts = REPORT_ITEM_POINTS[itemIndex];
        state_.bumpScore(pts); state_.currentReportScore += pts; popPoints(pts);
    }
    sound_.playMachine(name);
    for (auto& p : pickups_) if (p.col == col && p.row == row) p.alpha = 0.55f;
    refreshHUD();
}

void IsoScene::collectTPSReport(int col, int row) {
    if (state_.reportItems.size() != Machine::REQUIRED.size()) {
        hud_.showMessage(Message::NEED_TPS, 5.f);
        return;
    }
    state_.tpsReportsDelivered += 1; state_.reportItems.clear();
    int tpsPoints = state_.level * 100 + 100;
    state_.bumpScore(tpsPoints); state_.currentReportScore = 0; popPoints(tpsPoints);
    sound_.playTpsDeliver();
    bool gainedLife = state_.lives < MAX_LIVES;
    if (gainedLife) state_.lives += 1;
    resetCollectedMachines(); refreshHUD();
    hud_.showMessage(Message::TPS_READY, 3.f);
}
void IsoScene::resetCollectedMachines() {
    for (int r = 0; r < rowsCount_; ++r)
        for (int c = 0; c < (int)map_[r].size(); ++c) {
            char ch = map_[r][c];
            if (ch == Tile::printer || ch == Tile::fax || ch == Tile::coverSheet || ch == Tile::bookBinder) {
                collected_.erase(mapKey(c, r));
                for (auto& p : pickups_) if (p.col == c && p.row == r) p.alpha = 1.f;
            }
        }
}

void IsoScene::popPoints(int n) {
    sf::Vector2f foot = toScreen(proj(px_, py_, 0));
    bigPops_.push_back(MiniPop{"+" + std::to_string(n),
                               {foot.x, foot.y - (float)isoTW_}, 0.7f, std::max(30.f, (float)(isoTW_ * 0.45))});
    sf::Vector2f petePos = mapLocal(px_, py_);
    miniPops_.push_back(MiniPop{"+" + std::to_string(n), petePos, 0.7f, 40.f});
}

// MARK: - Minimap helper

sf::Vector2f IsoScene::mapLocal(double x, double y) const {
    float lx = (float)x * mapCell_;
    float ly = ((float)rowsCount_ - (float)y) * mapCell_;
    float sx = mapOrigin_.x + lx * mapScale_;
    float sy = viewHeight_ - (mapOrigin_.y + ly * mapScale_);
    return {sx, sy};
}

// The radar floor checker + walls never change, so batch them into ONE vertex array
// built once (was ~600 RectangleShapes / draw calls per frame).
void IsoScene::buildRadar() {
    float mapH = (float)rowsCount_ * mapCell_, mapW = (float)colsCount_ * mapCell_;
    mapScale_ = (radarH_ - 8.f) / mapH;
    mapOrigin_ = sf::Vector2f((viewW_ - mapW * mapScale_) / 2.f, 4.f);
    float h = mapCell_ * mapScale_ / 2.f;
    const Color cub = CUBICLE_COLORS[(state_.level - 1) % 12];
    sf::Color wallCol = mul(cub, 0.55f);
    radarStaticVA_ = sf::VertexArray(sf::Quads);
    for (int r = 0; r < rowsCount_; ++r)
        for (int c = 0; c < (int)map_[r].size(); ++c) {
            sf::Vector2f p = mapLocal(c + 0.5, r + 0.5);
            sf::Color fc = ((c + r) % 2 == 0) ? sf::Color(28, 31, 33) : sf::Color(23, 26, 28);
            quad(radarStaticVA_, {p.x - h, p.y - h}, {p.x + h, p.y - h}, {p.x + h, p.y + h}, {p.x - h, p.y + h}, fc);
            if (map_[r][c] == Tile::wall)
                quad(radarStaticVA_, {p.x - h, p.y - h}, {p.x + h, p.y - h}, {p.x + h, p.y + h}, {p.x - h, p.y + h}, wallCol);
        }
}

// MARK: - Input

void IsoScene::keyDown(int code, bool isRepeat) {
    if (gameOver_) return;
    if (code == K_ESC) { wantsExit_ = true; return; }
    if (code == K_P) { togglePause(); return; }
    if (isUserPaused_) return;
    if (code == K_SPACE) { if (!isRepeat) fire(); return; }
    if (code == K_UP || code == K_W)    worker_->queueDirection(MoveDirection::Up);
    else if (code == K_RIGHT || code == K_D) worker_->queueDirection(MoveDirection::Right);
    else if (code == K_DOWN || code == K_S)  worker_->queueDirection(MoveDirection::Down);
    else if (code == K_LEFT || code == K_A)  worker_->queueDirection(MoveDirection::Left);
}
void IsoScene::keyUp(int) {}

static float radiusBetween(sf::Vector2f a, sf::Vector2f b) {
    float dx = a.x - b.x, dy = a.y - b.y; return std::sqrt(dx * dx + dy * dy);
}
std::string IsoScene::dpadWedgeAt(float x, float y) const {
    float dx = x - joystickCenter_.x, dy = y - joystickCenter_.y;
    float mag = std::sqrt(dx * dx + dy * dy);
    if (mag < joystickDeadzone_ || mag > joystickRadius_) return "";
    if (std::abs(dy) >= std::abs(dx)) return dy < 0 ? "up" : "down";
    return dx > 0 ? "right" : "left";
}
void IsoScene::dpadSet(unsigned finger, float x, float y, int phase) {
    std::string prev = dpadFinger_.count(finger) ? dpadFinger_[finger] : std::string();
    std::string w = (phase == 2) ? std::string() : dpadWedgeAt(x, y);
    if (w.empty()) dpadFinger_.erase(finger); else dpadFinger_[finger] = w;
    if (phase == 2) joystickThumb_ = joystickCenter_;
    else {
        float dx = x - joystickCenter_.x, dy = y - joystickCenter_.y;
        float mag = std::sqrt(dx * dx + dy * dy), lim = joystickRadius_ * 0.58f;
        joystickThumb_ = (mag > lim && mag > 0.f)
            ? sf::Vector2f(joystickCenter_.x + dx / mag * lim, joystickCenter_.y + dy / mag * lim)
            : sf::Vector2f(x, y);
    }
    if (!w.empty() && w != prev) {
        if (w == "up")         worker_->queueDirection(MoveDirection::Up);
        else if (w == "right") worker_->queueDirection(MoveDirection::Right);
        else if (w == "down")  worker_->queueDirection(MoveDirection::Down);
        else if (w == "left")  worker_->queueDirection(MoveDirection::Left);
    }
    applyDpad();
}
void IsoScene::applyDpad() {
    bool up = false, down = false, left = false, right = false;
    for (auto& fw : dpadFinger_) {
        const std::string& w = fw.second;
        if (w == "up") up = true; else if (w == "down") down = true;
        else if (w == "left") left = true; else if (w == "right") right = true;
    }
    dpadUp_ = up; dpadDown_ = down; dpadLeft_ = left; dpadRight_ = right;
}
void IsoScene::pointer(unsigned finger, float x, float y, int phase) {
    if (isUserPaused_ || dying_ || gameOver_) return;
    if (!controlsShown_) { if (phase == 0) fire(); return; }
    if (phase == 0) {
        if (radiusBetween({x, y}, joystickCenter_) <= joystickRadius_) { dpadSet(finger, x, y, 0); return; }
        if (radiusBetween({x, y}, fireButtonCenter_) <= fireButtonRadius_) fire();
        return;
    }
    if (dpadFinger_.count(finger)) dpadSet(finger, x, y, phase);
}
void IsoScene::touch(unsigned finger, float x, float y, int phase) { usingTouch_ = true; pointer(finger, x, y, phase); }
void IsoScene::mouseDown(float x, float y)    { if (usingTouch_) return; pointer(0, x, y, 0); }
void IsoScene::mouseDragged(float x, float y) { if (usingTouch_) return; pointer(0, x, y, 1); }
void IsoScene::mouseUp()                      { if (usingTouch_) return; pointer(0, 0.f, 0.f, 2); }

// MARK: - Rendering

void IsoScene::render(sf::RenderTarget& target) {
    drawSky(target);

    // Pin Pete to the centre of the play area; the whole maze translates around him.
    float anchorY = radarH_ + viewArea() * 0.5f;        // y-up
    sf::Vector2f foot = proj(px_, py_, 0);
    worldOffX_ = viewW_ / 2.f - foot.x;
    worldOffY_ = anchorY - foot.y;

    sf::Transform xf;
    xf.translate(worldOffX_, viewHeight_ - worldOffY_);
    xf.scale(1.f, -1.f);
    sf::RenderStates rs(xf);

    // Painter order: each row's static maze + dots, then the dynamic sprites in that row.
    for (int r = 0; r < rowsCount_; ++r) {
        if (mazeRows_[r].getVertexCount()) target.draw(mazeRows_[r], rs);
        if (dotRows_[r].getVertexCount())  target.draw(dotRows_[r], rs);
        drawSpritesForRow(target, r);
    }

    // Iso-world score popups (drawn above the maze, below the radar panel).
    for (auto& m : bigPops_) {
        uint8_t a = (uint8_t)(std::clamp(m.timer / 0.7f, 0.f, 1.f) * 255);
        drawCenteredText(target, m.text, m.fontSize, sf::Color(255, 231, 0, a), m.pos.x, m.pos.y);
    }

    drawMap(target);
    drawControls(target);
    hud_.draw(target, (float)WINDOW_WIDTH, (float)WINDOW_HEIGHT);
}

void IsoScene::placeIsoSprite(const std::string& emoji, double col, double row, double targetH,
                              sf::RenderTarget& target, double lift, sf::Color color, bool flipX) {
    double sz = targetH * perspScale(row);
    sf::Vector2f footScreen = toScreen(proj(col, row, lift));
    drawEmoji(target, emoji, sf::Vector2f(footScreen.x, footScreen.y - (float)(sz * 0.5)), (float)sz, color, flipX);
}

void IsoScene::drawIsoPerson(PixelPersonRenderer& r, double col, double row, double targetH,
                             sf::RenderTarget& target, bool facingLeft, bool walking,
                             MoveDirection lookDir, float walkPhase, float alpha, float extraScale) {
    float nativeH = std::max(1.f, r.metrics().height);
    float s = (float)(targetH * perspScale(row)) / nativeH * extraScale;
    sf::Vector2f footScreen = toScreen(proj(col, row, 0));
    float originY = footScreen.y - 3.f - r.metrics().feetOffset * s;   // feet planted (3px lift like the master)
    r.draw(target, {footScreen.x, originY}, facingLeft, walking, lookDir, walkPhase, alpha, s);
}

void IsoScene::drawSpritesForRow(sf::RenderTarget& target, int row) {
    double spriteH = isoTW_ * 0.95;

    // Stationary pickups planted on this row.
    for (auto& p : pickups_) {
        if (!p.alive || p.row != row) continue;
        double col = p.col + 0.5, rw = p.row + 0.5;
        uint8_t a = (uint8_t)(p.alpha * 255);
        if (p.kind == Tile::goldDisc || p.kind == Tile::waterPellet) {
            bool gold = (p.kind == Tile::goldDisc);
            double peak = gold ? 1.18 : 1.25;                 // throbbing(peak, 0.5) -> 1s period
            double throb = 1.0 + (peak - 1.0) * (0.5 - 0.5 * std::cos(animTime_ * 6.2832));
            float baseHalo = (float)(isoTW_ * 0.35 * perspScale(rw));   // disc height = isoTW*0.7 (placeIsoSprite targetH)
            sf::Vector2f foot = toScreen(proj(col, rw, 0));
            sf::Vector2f c(foot.x, foot.y - baseHalo - 6.f);  // feet planted on the floor + the Swift +6 lift
            drawPowerDisc(target, c, (float)(baseHalo / 1.35 * throb), gold, a);
        } else {
            double sz = isoTW_ * 0.7;
            double throb = (p.kind == Tile::waterGun) ? 1.0 + 0.18 * (0.5 - 0.5 * std::cos(animTime_ * 6.0)) : 1.0;
            sf::Vector2f footScreen = toScreen(proj(col, rw, 0));
            footScreen.y -= 6.f;
            float drawSz = (float)(sz * perspScale(rw) * throb);
            drawEmoji(target, pickupEmoji(p.kind), sf::Vector2f(footScreen.x, footScreen.y - drawSz * 0.5f),
                      drawSz, sf::Color(255, 255, 255, a));
        }
    }

    // Shots (cyan water pellets): same layered disc, height isoTW*0.34, lifted 0.55, feet planted.
    for (auto& s : shots_) {
        if (!s.alive || (int)std::floor(s.y) != row) continue;
        float baseHalo = (float)(isoTW_ * 0.17 * perspScale(s.y));
        sf::Vector2f foot = toScreen(proj(s.x, s.y, 0.55));
        drawPowerDisc(target, sf::Vector2f(foot.x, foot.y - baseHalo), baseHalo / 1.35f, false, 255);
    }

    // Traveler (fish/treat).
    if (travActive_ && !travEmoji_.empty() && (int)std::floor(travRow_) == row) {
        double sz = isoTW_ * 0.9 * perspScale(travRow_);
        sf::Vector2f footScreen = toScreen(proj(travCol_, travRow_, 0));
        footScreen.y -= 3.f;
        drawEmoji(target, travEmoji_, sf::Vector2f(footScreen.x, footScreen.y - (float)(sz * 0.5)),
                  (float)sz, sf::Color::White, travFlip_ < 0);
        drawCenteredText(target, std::to_string(travPoints_), std::max(9.f, (float)(isoTW_ * 0.34)),
                         sf::Color(255, 231, 0), footScreen.x, footScreen.y - (float)sz - 8.f);
    }

    // Bosses.
    for (size_t i = 0; i < bossController_.entities.size(); ++i) {
        auto& e = bossController_.entities[i];
        if (!e.isActive && !e.isCaptured && !e.captureReturning) continue;
        if (i >= bossGrid_.size()) continue;
        double bcol = bossGrid_[i].first, brow = bossGrid_[i].second;
        if ((int)std::floor(brow) != row) continue;
        float extra = 1.f;
        if (e.throbTimer > 0.0f) {
            float progress = 1.0f - e.throbTimer / SPAWN_THROB_DUR;
            extra = 1.0f + 0.18f * std::abs(std::sin(progress * 3.14159265f * 3.0f));
        }
        float alpha = e.fadeInAlpha;
        if (e.isCaptured || e.captureReturning) alpha = e.captureAlpha;
        drawIsoPerson(e.renderer, bcol, brow, spriteH, target, e.facingLeft, e.isMoving,
                      e.lookDir, e.walkPhase, alpha, extra);
        if (!e.name.empty()) {
            sf::Vector2f foot = toScreen(proj(bcol, brow, 0));
            float fs = std::max(13.f, std::min(24.f, (float)(spriteH * perspScale(brow) * 0.16)));
            bool flee = bossController_.isInFleeMode((int)i);
            std::string tag = flee ? std::to_string(100 * (bossController_.captureStreak + 1)) : e.name;
            sf::Color tagColor = flee ? PixelPersonRenderer::toSfColor(YELLOW) : sf::Color::White;
            drawCenteredText(target, tag, fs, tagColor, foot.x,
                             foot.y - (float)(spriteH * perspScale(brow)) - fs * 0.7f);
        }
    }

    // Pete (always on his own row).
    if ((int)std::floor(py_) == row) {
        static PixelPersonRenderer pete(peteFrontConfig());
        bool walking = worker_->isMoving;
        drawIsoPerson(pete, px_, py_, spriteH, target, worker_->facingLeft, walking,
                      worker_->direction, worker_->walkPhase, dying_ ? 0.2f : 1.0f, 1.f);
        sf::Vector2f foot = toScreen(proj(px_, py_, 0));
        if (!dying_)
            drawCenteredText(target, Worker::PETE, std::max(13.f, (float)(spriteH * perspScale(py_) * 0.18)),
                             sf::Color::White, foot.x, foot.y - (float)(spriteH * perspScale(py_)) - 10.f);
    }
}

void IsoScene::drawSky(sf::RenderTarget& target) {
    // Dark office background above the radar (the maze + radar panel paint over it).
    const Color cube = CUBICLE_COLORS[(state_.level - 1) % 12];
    sf::RectangleShape bg({viewW_, viewHeight_});
    bg.setPosition(0.f, 0.f);
    bg.setFillColor(sf::Color((uint8_t)(cube.r * 0.05f * 255), (uint8_t)(cube.g * 0.05f * 255),
                              (uint8_t)(cube.b * 0.05f * 255)));
    target.draw(bg);
}

void IsoScene::drawMap(sf::RenderTarget& target) {
    sf::RectangleShape panel({viewW_, radarH_});
    panel.setPosition(0.f, viewHeight_ - radarH_);
    panel.setFillColor(sf::Color(10, 10, 13));
    target.draw(panel);

    target.draw(radarStaticVA_);   // batched floor checker + walls (one draw call)

    // Dots batched into one vertex array (one draw call instead of ~200 circles).
    {
        float dh = mapCell_ * 0.1f * mapScale_;
        sf::VertexArray dotsVA(sf::Quads);
        for (int r = 0; r < rowsCount_; ++r)
            for (int c = 0; c < (int)map_[r].size(); ++c) {
                if (!isDotTile(map_[r][c]) || isoDotCollected_.count(mapKey(c, r))) continue;
                sf::Vector2f p = mapLocal(c + 0.5, r + 0.5);
                quad(dotsVA, {p.x - dh, p.y - dh}, {p.x + dh, p.y - dh},
                     {p.x + dh, p.y + dh}, {p.x - dh, p.y + dh}, sf::Color(255, 231, 0));
            }
        if (dotsVA.getVertexCount()) target.draw(dotsVA);
    }

    for (auto& p : pickups_) {
        if (!p.alive) continue;
        int key = mapKey(p.col, p.row);
        if (hiddenPickups_.count(key)) continue;
        sf::Vector2f pos = mapLocal(p.col + 0.5, p.row + 0.5);
        uint8_t a = (uint8_t)(p.alpha * 255);
        if (p.kind == Tile::goldDisc || p.kind == Tile::waterPellet) {
            bool gold = (p.kind == Tile::goldDisc);
            float r2 = mapCell_ * (gold ? 0.28f : 0.32f) * mapScale_;
            sf::CircleShape core(r2, 14); core.setOrigin(r2, r2); core.setPosition(pos);
            core.setFillColor(gold ? sf::Color(255, 231, 0, a) : sf::Color(0, 200, 240, a));
            target.draw(core);
        } else {
            drawEmoji(target, pickupEmoji(p.kind), pos, mapCell_ * 0.7f * mapScale_, sf::Color(255, 255, 255, a));
        }
    }
    for (size_t i = 0; i < bossController_.entities.size(); ++i) {
        auto& e = bossController_.entities[i];
        if (!e.isActive && !e.isCaptured && !e.captureReturning) continue;
        if (i >= bossGrid_.size()) continue;
        sf::Vector2f p = mapLocal(bossGrid_[i].first, bossGrid_[i].second);
        e.renderer.draw(target, p, e.facingLeft, e.isMoving, e.lookDir, e.walkPhase, 1.0f, mapScale_ * 0.9f);
    }
    for (auto& s : shots_) {
        if (!s.alive) continue;
        sf::Vector2f p = mapLocal(s.x, s.y);
        float r2 = mapCell_ * 0.22f * mapScale_;
        sf::CircleShape dot(r2, 12); dot.setOrigin(r2, r2); dot.setPosition(p);
        dot.setFillColor(sf::Color(50, 200, 240, 217));
        target.draw(dot);
    }
    if (travActive_ && !travEmoji_.empty()) {
        sf::Vector2f p = mapLocal(travCol_, travRow_);
        drawEmoji(target, travEmoji_, p, mapCell_ * 0.8f * mapScale_, sf::Color::White, travFlip_ < 0);
    }
    {
        static PixelPersonRenderer mapPete(peteFrontConfig());
        sf::Vector2f p = mapLocal(px_, py_);
        mapPete.draw(target, p, worker_->facingLeft, worker_->isMoving, worker_->direction,
                     worker_->walkPhase, 1.0f, mapScale_ * 0.9f);
    }
    for (auto& m : miniPops_) {
        uint8_t a = (uint8_t)(std::clamp(m.timer / 0.7f, 0.f, 1.f) * 255);
        drawCenteredText(target, m.text, m.fontSize * mapScale_, sf::Color(255, 231, 0, a), m.pos.x, m.pos.y);
    }
}

void IsoScene::drawControls(sf::RenderTarget& target) {
    if (!controlsShown_) return;
    const float PI = 3.14159265f;
    sf::CircleShape ring(fireButtonRadius_, 64);
    ring.setOrigin(fireButtonRadius_, fireButtonRadius_); ring.setPosition(fireButtonCenter_);
    ring.setFillColor(sf::Color(255, 255, 255, 36));
    ring.setOutlineThickness(2.f); ring.setOutlineColor(sf::Color(255, 255, 255, 128));
    target.draw(ring);

    sf::CircleShape base(joystickRadius_, 64);
    base.setOrigin(joystickRadius_, joystickRadius_); base.setPosition(joystickCenter_);
    base.setFillColor(sf::Color(255, 255, 255, 15));
    base.setOutlineThickness(2.f); base.setOutlineColor(sf::Color(255, 255, 255, 128));
    target.draw(base);

    if (ControlMode::showsStick()) {
        float tr = joystickRadius_ * 0.42f;
        sf::CircleShape thumb(tr, 48);
        thumb.setOrigin(tr, tr); thumb.setPosition(joystickThumb_);
        thumb.setFillColor(sf::Color(255, 255, 255, 56));
        thumb.setOutlineThickness(2.f); thumb.setOutlineColor(sf::Color(255, 255, 255, 153));
        target.draw(thumb);
        return;
    }
    struct Wedge { float ang; bool on; };
    Wedge wedges[4] = {{-PI / 2, dpadUp_}, {PI / 2, dpadDown_}, {0.f, dpadRight_}, {PI, dpadLeft_}};
    for (const auto& w : wedges) {
        float a0 = w.ang - PI / 4, a1 = w.ang + PI / 4;
        const int steps = 14;
        sf::VertexArray strip(sf::TriangleStrip);
        sf::Color fill(255, 255, 255, w.on ? 87 : 31);
        for (int i = 0; i <= steps; ++i) {
            float t = a0 + (a1 - a0) * (float)i / steps;
            strip.append(sf::Vertex({joystickCenter_.x + std::cos(t) * joystickDeadzone_,
                                     joystickCenter_.y + std::sin(t) * joystickDeadzone_}, fill));
            strip.append(sf::Vertex({joystickCenter_.x + std::cos(t) * joystickRadius_,
                                     joystickCenter_.y + std::sin(t) * joystickRadius_}, fill));
        }
        target.draw(strip);
    }
    sf::VertexArray xlines(sf::Lines);
    sf::Color line(255, 255, 255, 128);
    for (int k = 0; k < 4; ++k) {
        float t = PI / 4 + (float)k * PI / 2;
        xlines.append(sf::Vertex({joystickCenter_.x + std::cos(t) * joystickDeadzone_,
                                  joystickCenter_.y + std::sin(t) * joystickDeadzone_}, line));
        xlines.append(sf::Vertex({joystickCenter_.x + std::cos(t) * joystickRadius_,
                                  joystickCenter_.y + std::sin(t) * joystickRadius_}, line));
    }
    target.draw(xlines);
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
