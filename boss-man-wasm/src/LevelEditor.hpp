#pragma once
#include <SFML/Graphics.hpp>
#include <string>
#include <vector>
#include "Constants.hpp"
#include "LevelStore.hpp"

namespace bm {

// A palette entry: the level-file character it paints and the label shown in the
// editor's palette list. Mirrors EditorTile in LevelEditorScene.swift.
struct EditorTile {
    char character;
    std::string displayName;
};

// Faithful C++/SFML port of LevelEditorScene.swift. Owns its own editing state and
// renders the right-hand tool panel plus a 37x17 grid drawn with the same visuals
// as the game maze. The Game routes events/update/draw here while in the editor
// state and reacts to playRequested / backRequested.
class LevelEditor {
public:
    explicit LevelEditor(LevelStore& store) : store_(store) {}

    // Load a level into the editor (clamped/wrapped to the level list).
    void open(int levelIndex);

    void handleEvent(const sf::Event& event, const sf::RenderWindow& window);
    void update(float dt);
    void draw(sf::RenderTarget& target);

    // Signals consumed (and cleared) by the Game.
    bool playRequested = false; // launch the game at currentLevelIndex+1 (practice)
    bool backRequested = false; // return to the title screen

    int currentLevelIndex = 0;

private:
    // ---- layout constants (SpriteKit values) ----
    static constexpr float W = (float)WINDOW_WIDTH;
    static constexpr float H = (float)WINDOW_HEIGHT;
    static constexpr float PANEL_WIDTH = 148.f;
    static constexpr float MARGIN = 12.f;
    static constexpr int   MAX_UNDO = 50;

    LevelStore& store_;

    // ---- editing state ----
    std::vector<std::string> mapRows;
    int gridRows = LevelStore::MAP_ROWS;
    int gridCols = LevelStore::MAP_COLS;
    char selectedTile = Tile::wall;
    float tileSize = 32.f;
    float gridOffsetX = 12.f; // SpriteKit Y-up offset (bottom-left origin)
    float gridOffsetY = 12.f;

    std::vector<std::vector<std::string>> undoStack;
    std::vector<std::vector<std::string>> redoStack;
    std::vector<std::string> clipboard;
    bool hasClipboard = false;
    size_t lastSavedHash = 0;

    // ---- transient UI timers / toasts ----
    std::string statusText;
    float saveGreenTimer = 0.f;      // save button flashes green
    float statusRevertTimer_ = 0.f;  // after SAVED!, revert the status line to the tile name
    float autosaveTimer = 60.f;      // periodic autosave countdown
    float autosaveLabelTimer = 0.f;  // shows "AUTOSAVE 1 min" on the save button
    std::vector<float> buttonFlash;  // per-button brighten timer, indexed by button

    // mouse drag tracking
    bool mouseLeftDown = false;
    bool mouseRightDown = false;

    // ---- helpers ----
    void loadCurrentLevel();
    void saveCurrentLevel();
    void prevLevel();
    void nextLevel();
    void undo();
    void redo();
    void copyLevel();
    void pasteLevel();
    void confirmClearLevel();
    void playCurrentLevel();
    void backToTitle();
    void pushUndoSnapshot();
    void autosaveIfDirty();
    void performAutosave();
    size_t mapHash() const;

    char charAt(int row, int col) const;
    void setChar(int row, int col, char ch);
    void paintAt(sf::Vector2f loc, char tile);
    void paintRightClick(sf::Vector2f loc);
    void handleClick(sf::Vector2f loc); // palette/button/paint dispatch on mouse-down
    void selectTileChar(char ch);

    sf::Vector2f mapMouse(const sf::RenderWindow& window, int x, int y) const;

    // geometry of palette swatches / buttons (SFML, Y-down)
    sf::FloatRect paletteRectSFML(int i) const;
    sf::FloatRect buttonRectSFML(int i) const;

    // rendering
    void drawPanel(sf::RenderTarget& t);
    void drawGrid(sf::RenderTarget& t);
    void drawTileContent(sf::RenderTarget& t, char ch, float cx, float cy, float size,
                         bool paletteSwatch);
    void flashButton(int index);
};

} // namespace bm
