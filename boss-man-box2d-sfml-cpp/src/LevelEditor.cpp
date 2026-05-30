#include "LevelEditor.hpp"
#include "PixelPersonRenderer.hpp"
#include "EmojiText.hpp"
#include "UiScale.hpp"
#include "Assets.hpp"
#include "MacWindow.hpp"
#include "MoveDirection.hpp"
#include <algorithm>
#include <cmath>
#include <functional>

namespace bm {

namespace {

// Palette entries, in the exact order of EditorTile.all in LevelEditorScene.swift.
const std::vector<EditorTile>& editorTiles() {
    static const std::vector<EditorTile> tiles = {
        {Tile::floor,       "Floor"},
        {Tile::dot,         "Dot"},
        {Tile::wall,        "Wall"},
        {Tile::hideout,     "Hideout"},
        {Tile::printer,     "TPS Printer"},
        {Tile::fax,         "TPS Fax Machine"},
        {Tile::coverSheet,  "TPS Cover Sheet"},
        {Tile::bookBinder,  "TPS Book Binder"},
        {Tile::brownBox,    "TPS Delivery Box"},
        {Tile::goldDisc,    "Gold Disc"},
        {Tile::worker,      "Hero Pete"},
        {Tile::boss1,       "Boss Bill"},
        {Tile::boss2,       "Boss Dom"},
        {Tile::boss3,       "Boss Bob"},
        {Tile::boss4,       "Boss Stan"},
        {Tile::waterGun,    "Water Gun"},
        {Tile::waterPellet, "Water Pellets"},
    };
    return tiles;
}

struct ButtonDef { std::string label; sf::Color color; };

// Buttons, in the exact order of btnData in LevelEditorScene.swift.
const std::vector<ButtonDef>& editorButtons() {
    static const std::vector<ButtonDef> buttons = {
        {"PREV  <",   sf::Color(107, 107, 107)},
        {"NEXT  >",   sf::Color( 87,  87,  87)},
        {"UNDO  Z",   sf::Color( 66,  66,  66)},
        {"REDO  Y",   sf::Color( 46,  46,  46)},
        {"CLEAR del", sf::Color(153,  38,  38)},
        {"RESET R",   sf::Color(153,  89,  26)},
        {"SAVE  S",   sf::Color( 38, 115,  38)},
        {"COPY  C",   sf::Color( 51, 102,  77)},
        {"PASTE V",   sf::Color( 64,  89,  77)},
        {"SHOW",      sf::Color( 64,  89, 115)},
        {"PLAY  P",   sf::Color( 38,  38, 140)},
        {"BACK  ESC", sf::Color(115, 102,  38)},
    };
    return buttons;
}
enum Btn { B_PREV, B_NEXT, B_UNDO, B_REDO, B_CLEAR, B_RESET, B_SAVE, B_COPY, B_PASTE, B_REVEAL, B_PLAY, B_BACK };

// Machine / item emoji, matching Strings.Emoji and MazeRenderer.
const std::string EMO_PRINTER = "\xf0\x9f\x96\xa8\xef\xb8\x8f"; // 🖨️
const std::string EMO_FAX     = "\xf0\x9f\x93\xa0";             // 📠
const std::string EMO_COVER   = "\xf0\x9f\x93\x84";             // 📄
const std::string EMO_BINDER  = "\xf0\x9f\x93\x9a";             // 📚
const std::string EMO_BOX     = "\xf0\x9f\x93\xa6";             // 📦
const std::string EMO_GUN     = "\xf0\x9f\x94\xab";             // 🔫

std::string emojiForChar(char ch) {
    switch (ch) {
    case Tile::printer:    return EMO_PRINTER;
    case Tile::fax:        return EMO_FAX;
    case Tile::coverSheet: return EMO_COVER;
    case Tile::bookBinder: return EMO_BINDER;
    case Tile::brownBox:   return EMO_BOX;
    case Tile::waterGun:   return EMO_GUN;
    default:               return std::string(1, ch);
    }
}

std::string displayNameFor(char ch) {
    for (const auto& t : editorTiles())
        if (t.character == ch) return t.displayName;
    return "Floor";
}

const sf::Font& editorFont(bool bold) {
    static sf::Font boldF, regF;
    static bool boldLoaded = false, regLoaded = false;
    if (bold) {
        if (!boldLoaded)
            boldLoaded = loadFont(boldF, "assets/fonts/JetBrainsMono-Bold.ttf");
        return boldF;
    }
    if (!regLoaded)
        regLoaded = loadFont(regF, "assets/fonts/JetBrainsMono-Bold.ttf");
    return regF;
}

// halign: 0=left, 1=center, 2=right. Always vertically centered at (x,y).
// Rasterized at size*uiScale and counter-scaled to stay crisp on Retina.
void drawText(sf::RenderTarget& t, const std::string& s, unsigned size, sf::Color color,
              float x, float centerY, int halign, bool bold, uint8_t alpha = 255) {
    if (s.empty()) return;
    float dpi = uiScale();
    sf::Text txt;
    txt.setFont(editorFont(bold));
    txt.setString(sf::String::fromUtf8(s.begin(), s.end()));
    txt.setCharacterSize((unsigned)(size * dpi));
    color.a = alpha;
    txt.setFillColor(color);
    auto lb = txt.getLocalBounds();
    float ox = (halign == 0) ? lb.left : (halign == 2 ? lb.left + lb.width : lb.left + lb.width / 2.f);
    txt.setOrigin(ox, lb.top + lb.height / 2.f);
    txt.setScale(1.f / dpi, 1.f / dpi);
    txt.setPosition(x, centerY);
    t.draw(txt);
}

float measureWidth(const std::string& s, unsigned size, bool bold) {
    sf::Text txt;
    txt.setFont(editorFont(bold));
    txt.setString(sf::String::fromUtf8(s.begin(), s.end()));
    txt.setCharacterSize(size);
    return txt.getLocalBounds().width;
}

sf::Color toSf(Color c, float alphaMul = 1.f) {
    return sf::Color((uint8_t)(c.r * 255), (uint8_t)(c.g * 255), (uint8_t)(c.b * 255),
                     (uint8_t)(c.a * 255 * alphaMul));
}

// Floor checkerboard color for the editor (parity = row + col), matching
// LevelEditorScene.floorColor(forParity:).
sf::Color floorColorFor(int parity) {
    return (parity % 2 == 0) ? sf::Color(28, 31, 33) : sf::Color(23, 26, 28);
}

const float PANEL_X = (float)WINDOW_WIDTH - 148.f - 4.f; // 1032
const float PANEL_CX = PANEL_X + 148.f / 2.f + 2.f;      // 1108

} // namespace

// ----------------------------------------------------------------------------

void LevelEditor::open(int levelIndex) {
    auto names = levelNames();
    int n = (int)names.size();
    currentLevelIndex = ((levelIndex % n) + n) % n;
    selectedTile = Tile::wall;
    playRequested = false;
    backRequested = false;
    mouseLeftDown = mouseRightDown = false;
    saveGreenTimer = 0.f;
    autosaveLabelTimer = 0.f;
    autosaveTimer = 60.f;
    buttonFlash.assign(editorButtons().size(), 0.f);
    loadCurrentLevel();
}

void LevelEditor::loadCurrentLevel() {
    auto names = levelNames();
    if (currentLevelIndex < 0 || currentLevelIndex >= (int)names.size()) currentLevelIndex = 0;
    undoStack.clear();
    redoStack.clear();

    auto rows = store_.loadLevel(names[currentLevelIndex]);
    if (rows.empty()) rows = LevelStore::normalize({});
    mapRows = LevelStore::normalize(rows);
    gridRows = LevelStore::MAP_ROWS;
    gridCols = LevelStore::MAP_COLS;

    // Grid layout (SpriteKit rebuildGrid math).
    float availWidth = W - PANEL_WIDTH - MARGIN * 2 - 8;
    float availHeight = H - MARGIN * 2;
    float fitW = gridCols > 0 ? availWidth / gridCols : 32.f;
    float fitH = gridRows > 0 ? availHeight / gridRows : 32.f;
    tileSize = std::max(std::min(fitW, fitH), 4.f);
    float totalW = gridCols * tileSize;
    float totalH = gridRows * tileSize;
    gridOffsetX = (availWidth - totalW) / 2.f + MARGIN;
    gridOffsetY = (availHeight - totalH) / 2.f + MARGIN;

    statusText = "Tile: " + displayNameFor(selectedTile);
    lastSavedHash = mapHash();
}

size_t LevelEditor::mapHash() const {
    std::string joined;
    for (size_t i = 0; i < mapRows.size(); ++i) {
        if (i) joined.push_back('\n');
        joined += mapRows[i];
    }
    return std::hash<std::string>{}(joined);
}

char LevelEditor::charAt(int row, int col) const {
    if (row < 0 || row >= (int)mapRows.size()) return Tile::floor;
    if (col < 0 || col >= (int)mapRows[row].size()) return Tile::floor;
    return mapRows[row][col];
}

void LevelEditor::setChar(int row, int col, char ch) {
    if (row < 0 || row >= (int)mapRows.size()) return;
    if (col < 0 || col >= (int)mapRows[row].size()) return;
    mapRows[row][col] = ch;
}

// ---- undo / redo / clipboard ----

void LevelEditor::pushUndoSnapshot() {
    undoStack.push_back(mapRows);
    if ((int)undoStack.size() > MAX_UNDO) undoStack.erase(undoStack.begin());
    redoStack.clear();
}

void LevelEditor::undo() {
    if (undoStack.empty()) { statusText = "Nothing to undo"; return; }
    redoStack.push_back(mapRows);
    mapRows = undoStack.back();
    undoStack.pop_back();
    statusText = "Undo";
}

void LevelEditor::redo() {
    if (redoStack.empty()) { statusText = "Nothing to redo"; return; }
    undoStack.push_back(mapRows);
    mapRows = redoStack.back();
    redoStack.pop_back();
    statusText = "Redo";
}

void LevelEditor::copyLevel() {
    clipboard = mapRows;
    hasClipboard = true;
    statusText = "Copied";
}

void LevelEditor::pasteLevel() {
    if (!hasClipboard || clipboard.empty()) { statusText = "Nothing to paste"; return; }
    pushUndoSnapshot();
    mapRows = clipboard;
    statusText = "Pasted";
}

void LevelEditor::confirmClearLevel() {
    bool ok = true;
#ifdef __APPLE__
    ok = macConfirmDialog("Clear this level?",
                          "This wipes every tile to floor. You can undo immediately with \xE2\x8C\x98Z.",
                          "Clear", "Cancel");
#endif
    if (!ok) return;
    pushUndoSnapshot();
    for (auto& row : mapRows) row.assign(gridCols, Tile::floor);
}

// Revert this level to its built-in layout (undoable with Z). Mirrors the wasm
// editor master's resetCurrentLevel.
void LevelEditor::resetCurrentLevel() {
    auto names = levelNames();
    if (currentLevelIndex < 0 || currentLevelIndex >= (int)names.size()) return;
    pushUndoSnapshot();
    store_.resetLevel(names[currentLevelIndex]);
    mapRows = LevelStore::normalize(store_.loadLevel(currentLevelIndex));
    statusText = "Reset to built-in (Z to undo)";
}

// ---- save / load / level navigation ----

void LevelEditor::saveCurrentLevel() {
    auto names = levelNames();
    if (currentLevelIndex < 0 || currentLevelIndex >= (int)names.size()) return;
    store_.saveLevel(names[currentLevelIndex], mapRows);
    lastSavedHash = mapHash();
    saveGreenTimer = 0.5f;
    statusText = "SAVED!";
    // statusRevert handled in update() via saveGreenTimer companion below.
    statusRevertTimer_ = 1.0f;
}

void LevelEditor::autosaveIfDirty() {
    if (mapHash() != lastSavedHash) saveCurrentLevel();
}

void LevelEditor::performAutosave() {
    saveCurrentLevel();
    statusRevertTimer_ = 0.f; // don't let the 1s SAVED! revert fight the autosave toast
    statusText = "AUTOSAVE 1 min";
    autosaveLabelTimer = 3.0f;
}

void LevelEditor::prevLevel() {
    autosaveIfDirty();
    int n = (int)levelNames().size();
    currentLevelIndex = (currentLevelIndex - 1 + n) % n;
    loadCurrentLevel();
}

void LevelEditor::nextLevel() {
    autosaveIfDirty();
    int n = (int)levelNames().size();
    currentLevelIndex = (currentLevelIndex + 1) % n;
    loadCurrentLevel();
}

void LevelEditor::playCurrentLevel() {
    autosaveIfDirty();
    playRequested = true;
}

void LevelEditor::backToTitle() {
    autosaveIfDirty();
    backRequested = true;
}

// ---- painting ----

void LevelEditor::selectTileChar(char ch) {
    selectedTile = ch;
    statusText = "Tile: " + displayNameFor(ch);
}

void LevelEditor::paintAt(sf::Vector2f loc, char tile) {
    int col = (int)std::floor((loc.x - gridOffsetX) / tileSize);
    float locSkY = H - loc.y;
    int row = gridRows - 1 - (int)std::floor((locSkY - gridOffsetY) / tileSize);
    if (row < 0 || row >= gridRows || col < 0 || col >= gridCols) return;
    if (charAt(row, col) != tile) setChar(row, col, tile);
}

void LevelEditor::paintRightClick(sf::Vector2f loc) {
    int col = (int)std::floor((loc.x - gridOffsetX) / tileSize);
    float locSkY = H - loc.y;
    int row = gridRows - 1 - (int)std::floor((locSkY - gridOffsetY) / tileSize);
    if (row < 0 || row >= gridRows || col < 0 || col >= gridCols) return;
    char current = charAt(row, col);
    char tile;
    if (current == Tile::dot)       tile = Tile::wall;
    else if (current == Tile::wall) tile = Tile::dot;
    else                            tile = Tile::dot;
    paintAt(loc, tile);
}

void LevelEditor::flashButton(int index) {
    if (index >= 0 && index < (int)buttonFlash.size()) buttonFlash[index] = 0.5f;
}

void LevelEditor::handleClick(sf::Vector2f loc) {
    // 1) palette hit?
    const auto& tiles = editorTiles();
    for (int i = 0; i < (int)tiles.size(); ++i) {
        if (paletteRectSFML(i).contains(loc)) { selectTileChar(tiles[i].character); return; }
    }
    // 2) button hit?
    const auto& buttons = editorButtons();
    for (int i = 0; i < (int)buttons.size(); ++i) {
        if (!buttonRectSFML(i).contains(loc)) continue;
        flashButton(i);
        switch (i) {
        case B_PREV:   prevLevel(); break;
        case B_NEXT:   nextLevel(); break;
        case B_UNDO:   undo(); break;
        case B_REDO:   redo(); break;
        case B_CLEAR:  confirmClearLevel(); break;
        case B_RESET:  resetCurrentLevel(); break;
        case B_SAVE:   saveCurrentLevel(); break;
        case B_COPY:   copyLevel(); break;
        case B_PASTE:  pasteLevel(); break;
        case B_REVEAL: store_.revealInFinder(); break;
        case B_PLAY:   playCurrentLevel(); break;
        case B_BACK:   backToTitle(); break;
        }
        return;
    }
    // 3) otherwise paint
    paintAt(loc, selectedTile);
}

// ---- input ----

sf::Vector2f LevelEditor::mapMouse(const sf::RenderWindow& window, int x, int y) const {
    return window.mapPixelToCoords(sf::Vector2i(x, y));
}

void LevelEditor::handleEvent(const sf::Event& event, const sf::RenderWindow& window) {
    switch (event.type) {
    case sf::Event::MouseButtonPressed: {
        sf::Vector2f loc = mapMouse(window, event.mouseButton.x, event.mouseButton.y);
        if (event.mouseButton.button == sf::Mouse::Left) {
            mouseLeftDown = true;
            pushUndoSnapshot();           // matches SpriteKit mouseDown
            handleClick(loc);
        } else if (event.mouseButton.button == sf::Mouse::Right) {
            mouseRightDown = true;
            paintRightClick(loc);
        }
        break;
    }
    case sf::Event::MouseButtonReleased:
        if (event.mouseButton.button == sf::Mouse::Left)  mouseLeftDown = false;
        if (event.mouseButton.button == sf::Mouse::Right) mouseRightDown = false;
        break;
    case sf::Event::MouseMoved: {
        sf::Vector2f loc = mapMouse(window, event.mouseMove.x, event.mouseMove.y);
        if (mouseLeftDown)       paintAt(loc, selectedTile);
        else if (mouseRightDown) paintRightClick(loc);
        break;
    }
    case sf::Event::KeyPressed: {
        // Bare-key shortcuts (no Cmd). The wasm editor is the master for the
        // right panel; browsers reserve Cmd/Ctrl combos, so it dropped the
        // modifier and C++ matches so the controls are identical cross-platform.
        switch (event.key.code) {
        case sf::Keyboard::Left:  flashButton(B_PREV); prevLevel(); return;
        case sf::Keyboard::Right: flashButton(B_NEXT); nextLevel(); return;
        case sf::Keyboard::Escape: backToTitle(); return;
        case sf::Keyboard::BackSpace: flashButton(B_CLEAR); confirmClearLevel(); return;
        case sf::Keyboard::S: flashButton(B_SAVE);  saveCurrentLevel(); return;
        case sf::Keyboard::P: flashButton(B_PLAY);  playCurrentLevel(); return;
        case sf::Keyboard::C: flashButton(B_COPY);  copyLevel(); return;
        case sf::Keyboard::V: flashButton(B_PASTE); pasteLevel(); return;
        case sf::Keyboard::Z: flashButton(B_UNDO);  undo(); return;
        case sf::Keyboard::Y: flashButton(B_REDO);  redo(); return;
        case sf::Keyboard::R: flashButton(B_RESET); resetCurrentLevel(); return;
        case sf::Keyboard::Num1: case sf::Keyboard::Numpad1: selectedTile = Tile::wall; break;
        case sf::Keyboard::Num2: case sf::Keyboard::Numpad2: selectedTile = Tile::dot; break;
        case sf::Keyboard::Num3: case sf::Keyboard::Numpad3: selectedTile = Tile::hideout; break;
        case sf::Keyboard::Num4: case sf::Keyboard::Numpad4: selectedTile = Tile::printer; break;
        case sf::Keyboard::Num5: case sf::Keyboard::Numpad5: selectedTile = Tile::fax; break;
        case sf::Keyboard::Num6: case sf::Keyboard::Numpad6: selectedTile = Tile::coverSheet; break;
        case sf::Keyboard::Num7: case sf::Keyboard::Numpad7: selectedTile = Tile::bookBinder; break;
        case sf::Keyboard::Num8: case sf::Keyboard::Numpad8: selectedTile = Tile::brownBox; break;
        case sf::Keyboard::Num0: case sf::Keyboard::Numpad0: selectedTile = Tile::floor; break;
        default: break;
        }
        // SpriteKit keyDown tail: updatePaletteHighlight() resets the status line.
        statusText = "Tile: " + displayNameFor(selectedTile);
        break;
    }
    default: break;
    }
}

// ---- update ----

void LevelEditor::update(float dt) {
    if (saveGreenTimer > 0.f) saveGreenTimer -= dt;
    for (auto& f : buttonFlash) if (f > 0.f) f -= dt;

    if (statusRevertTimer_ > 0.f) {
        statusRevertTimer_ -= dt;
        if (statusRevertTimer_ <= 0.f) statusText = "Tile: " + displayNameFor(selectedTile);
    }
    if (autosaveLabelTimer > 0.f) {
        autosaveLabelTimer -= dt;
        if (autosaveLabelTimer <= 0.f) statusText = "Tile: " + displayNameFor(selectedTile);
    }

    autosaveTimer -= dt;
    if (autosaveTimer <= 0.f) {
        performAutosave();
        autosaveTimer = 60.f;
    }
}

// ---- geometry (SFML, Y-down) ----

sf::FloatRect LevelEditor::paletteRectSFML(int i) const {
    // SpriteKit swatch bottom-left y = 553 - 17i; SFML top = 96 + 17i.
    return sf::FloatRect(PANEL_X + 8.f, 96.f + 17.f * i, PANEL_WIDTH - 12.f, 17.f);
}

sf::FloatRect LevelEditor::buttonRectSFML(int i) const {
    // SpriteKit button bottom-left y = 251 - 19i; SFML top = 398 + 19i.
    return sf::FloatRect(PANEL_X + 8.f, 398.f + 19.f * i, PANEL_WIDTH - 12.f, 17.f);
}

// ---- rendering ----

void LevelEditor::draw(sf::RenderTarget& t) {
    // Scene background: NSColor(white: 0.08).
    sf::RectangleShape bg({W, H});
    bg.setFillColor(sf::Color(20, 20, 20));
    t.draw(bg);
    drawGrid(t);
    drawPanel(t);
}

void LevelEditor::drawGrid(sf::RenderTarget& t) {
    // People (Pete + bosses) are taller than a tile, so their feet would be
    // clipped by the next row's floor. Draw all floors + flat content first, then
    // the people on top in a second pass so their feet are never cut off.
    struct PendingPerson { char ch; float cx, cy; };
    std::vector<PendingPerson> people;

    for (int row = 0; row < gridRows; ++row) {
        for (int col = 0; col < gridCols; ++col) {
            float xSk = gridOffsetX + col * tileSize + tileSize / 2.f;
            float ySk = gridOffsetY + (gridRows - 1 - row) * tileSize + tileSize / 2.f;
            float cx = xSk;
            float cy = H - ySk;

            // Floor (parity = row + col) with a hairline grid edge drawn inward.
            sf::RectangleShape floor({tileSize, tileSize});
            floor.setPosition(cx - tileSize / 2.f, cy - tileSize / 2.f);
            floor.setFillColor(floorColorFor(row + col));
            floor.setOutlineColor(sf::Color(41, 41, 41));
            floor.setOutlineThickness(-0.5f);
            t.draw(floor);

            char ch = charAt(row, col);
            if (ch == Tile::worker || ch == Tile::boss1 || ch == Tile::boss2 ||
                ch == Tile::boss3 || ch == Tile::boss4) {
                people.push_back({ch, cx, cy});
            } else {
                drawTileContent(t, ch, cx, cy, tileSize, false);
            }
        }
    }

    for (const auto& p : people)
        drawTileContent(t, p.ch, p.cx, p.cy, tileSize, false);
}

void LevelEditor::drawTileContent(sf::RenderTarget& t, char ch, float cx, float cy,
                                  float size, bool paletteSwatch) {
    (void)paletteSwatch;
    switch (ch) {
    case Tile::wall: {
        Color cub = CUBICLE_COLORS[currentLevelIndex % 12];
        float inset = size * 0.04f;
        float lw = 1.5f;
        float side = size - inset * 2.f - lw; // shrink so the outline grows back to the inset square
        sf::RectangleShape body({side, side});
        body.setOrigin(side / 2.f, side / 2.f);
        body.setPosition(cx, cy);
        body.setFillColor(toSf(cub, 0.55f));
        body.setOutlineColor(toSf(cub));
        body.setOutlineThickness(lw);
        t.draw(body);

        float trimH = std::max(2.f, size * 0.12f);
        float trimW = size - size * 0.32f;
        sf::RectangleShape trim({trimW, trimH});
        // SpriteKit rect bottom-left (-size/2+size*0.16, size*0.20); top edge = y + h.
        trim.setPosition(cx - size / 2.f + size * 0.16f, cy - size * 0.20f - trimH);
        trim.setFillColor(sf::Color(142, 142, 147)); // systemGray
        t.draw(trim);
        break;
    }
    case Tile::dot: {
        float d = std::max(2.f, size * 0.20f);
        sf::RectangleShape dot({d, d});
        dot.setOrigin(d / 2.f, d / 2.f);
        dot.setPosition(cx, cy);
        dot.setFillColor(sf::Color(255, 231, 0)); // systemYellow
        t.draw(dot);
        break;
    }
    case Tile::hideout:
        drawText(t, "H", (unsigned)std::round(size * 0.85f), sf::Color(175, 82, 222),
                 cx, cy, 1, true);
        break;
    case Tile::goldDisc: {
        float r = size * 0.28f;
        sf::CircleShape halo(r * 1.35f, 48);
        halo.setFillColor(sf::Color(255, 231, 0, 77));
        halo.setPosition(cx - halo.getRadius(), cy - halo.getRadius());
        t.draw(halo);
        sf::CircleShape core(r, 48);
        core.setFillColor(sf::Color(255, 231, 0, 217));
        core.setOutlineColor(sf::Color(178, 127, 0));
        core.setOutlineThickness(1.f);
        core.setPosition(cx - r, cy - r);
        t.draw(core);
        sf::CircleShape spec(r * 0.3f, 24);
        spec.setFillColor(sf::Color(255, 255, 255, 191));
        spec.setPosition(cx - r * 0.28f - spec.getRadius(), cy - r * 0.28f - spec.getRadius());
        t.draw(spec);
        break;
    }
    case Tile::waterPellet: {
        float r = size * 0.32f;
        sf::CircleShape halo(r * 1.35f, 48);
        halo.setFillColor(sf::Color(0, 200, 240, 64));
        halo.setPosition(cx - halo.getRadius(), cy - halo.getRadius());
        t.draw(halo);
        sf::CircleShape core(r, 48);
        core.setFillColor(sf::Color(0, 200, 240, 217));
        core.setOutlineColor(sf::Color(4, 122, 255));
        core.setOutlineThickness(1.5f);
        core.setPosition(cx - r, cy - r);
        t.draw(core);
        sf::CircleShape spec(r * 0.3f, 24);
        spec.setFillColor(sf::Color(255, 255, 255, 191));
        spec.setPosition(cx - r * 0.28f - spec.getRadius(), cy - r * 0.28f - spec.getRadius());
        t.draw(spec);
        break;
    }
    case Tile::printer: case Tile::fax: case Tile::coverSheet:
    case Tile::bookBinder: case Tile::brownBox: case Tile::waterGun:
        drawEmoji(t, emojiForChar(ch), {cx, cy}, size * 0.72f);
        break;
    case Tile::worker: {
        PersonConfig cfg;
        cfg.bodyColor = PETE_BODY; cfg.tieColor = PETE_TIE; cfg.hairColor = PETE_HAIR;
        cfg.shoeOutlineColor = PETE_SHOE_OUT; cfg.pantsColor = PETE_PANTS;
        cfg.walkExaggeration = 0.f; cfg.wearsSunglasses = false; cfg.headYOffset = 0.f;
        PixelPersonRenderer(cfg).draw(t, {cx, cy}, false, false, MoveDirection::None,
                                      0.f, 1.f, size / 38.f);
        break;
    }
    case Tile::boss1: case Tile::boss2: case Tile::boss3: case Tile::boss4: {
        int bi = ch - '1';
        const BossBlueprint& bp = BOSS_BLUEPRINTS[bi];
        PersonConfig cfg;
        cfg.bodyColor = bp.bodyColor; cfg.tieColor = bp.tieColor; cfg.hairColor = BOSS_HAIR;
        cfg.shoeOutlineColor = BOSS_SHOE_GOLD; cfg.pantsColor = bp.pantsColor;
        cfg.walkExaggeration = 0.f; cfg.wearsSunglasses = false; cfg.headYOffset = 1.f;
        PixelPersonRenderer(cfg).draw(t, {cx, cy}, false, false, MoveDirection::None,
                                      0.f, 1.f, size / 38.f);
        break;
    }
    default: break;
    }
}

void LevelEditor::drawPanel(sf::RenderTarget& t) {
    // Panel background.
    sf::RectangleShape panel({PANEL_WIDTH + 4.f, H});
    panel.setPosition(PANEL_X, 0.f);
    panel.setFillColor(sf::Color(38, 38, 38, 247));
    panel.setOutlineColor(sf::Color(89, 89, 89));
    panel.setOutlineThickness(-2.f);
    t.draw(panel);

    // Headings.
    const sf::Color systemBlue(10, 122, 255);
    drawText(t, "LEVEL EDITOR", 13, sf::Color::White, PANEL_CX, 24.f, 1, true);
    auto names = levelNames();
    std::string levelName = names[currentLevelIndex];
    drawText(t, levelName, 11, systemBlue, PANEL_CX, 46.f, 1, true);
    drawText(t, "(" + std::to_string(currentLevelIndex + 1) + "/" + std::to_string(names.size()) + ")",
             11, systemBlue, PANEL_CX, 60.f, 1, true);
    drawText(t, statusText, 10, sf::Color(255, 255, 0), PANEL_CX, 78.f, 1, false);

    // Traveler glyph to the right of the level name.
    {
        const TravelerDef& tr = TRAVELERS[currentLevelIndex % TRAVELER_COUNT];
        float labelW = measureWidth(levelName, 11, true);
        float glyphX = PANEL_CX + labelW / 2.f + 14.f;
        drawEmoji(t, tr.emoji, {glyphX, 46.f}, 11.f, sf::Color::White, tr.facesRight);
    }

    // Palette swatches.
    const auto& tiles = editorTiles();
    int selectedIdx = -1;
    for (int i = 0; i < (int)tiles.size(); ++i) {
        sf::FloatRect r = paletteRectSFML(i);
        sf::RectangleShape sw({r.width, r.height});
        sw.setPosition(r.left, r.top);
        sw.setFillColor(floorColorFor(0));
        sw.setOutlineColor(sf::Color(102, 102, 102));
        sw.setOutlineThickness(-1.f);
        t.draw(sw);

        float previewX = PANEL_X + 8.f + (17.f - 6.f) / 2.f + 3.f; // 1048.5
        float previewCY = r.top + r.height / 2.f;
        drawTileContent(t, tiles[i].character, previewX, previewCY, 17.f - 6.f, true);

        drawText(t, tiles[i].displayName, 10, sf::Color::White,
                 PANEL_X + 8.f + 17.f + 4.f, previewCY, 0, true);

        if (tiles[i].character == selectedTile) selectedIdx = i;
    }
    // Selected-tile highlight overlay.
    if (selectedIdx >= 0) {
        sf::FloatRect r = paletteRectSFML(selectedIdx);
        sf::RectangleShape hl({r.width - 4.f, r.height - 4.f});
        hl.setPosition(r.left + 2.f, r.top + 2.f);
        hl.setFillColor(sf::Color(255, 255, 0, 26));
        hl.setOutlineColor(sf::Color(255, 255, 0));
        hl.setOutlineThickness(-1.f);
        t.draw(hl);
    }

    // Buttons.
    const auto& buttons = editorButtons();
    for (int i = 0; i < (int)buttons.size(); ++i) {
        sf::FloatRect r = buttonRectSFML(i);
        sf::Color fill = buttons[i].color;
        if (i == B_SAVE && saveGreenTimer > 0.f) {
            fill = sf::Color(0, 255, 0);
        } else if (i < (int)buttonFlash.size() && buttonFlash[i] > 0.f) {
            // Brighten toward white by 45%, like flashButton().
            fill = sf::Color(
                (uint8_t)(fill.r + (255 - fill.r) * 0.45f),
                (uint8_t)(fill.g + (255 - fill.g) * 0.45f),
                (uint8_t)(fill.b + (255 - fill.b) * 0.45f));
        }
        sf::RectangleShape btn({r.width, r.height});
        btn.setPosition(r.left, r.top);
        btn.setFillColor(fill);
        t.draw(btn);

        std::string label = buttons[i].label;
        if (i == B_SAVE && autosaveLabelTimer > 0.f) label = "AUTOSAVE 1 min";
        drawText(t, label, 9, sf::Color::White, PANEL_X + 15.f, r.top + r.height / 2.f, 0, true);
    }
}

} // namespace bm
