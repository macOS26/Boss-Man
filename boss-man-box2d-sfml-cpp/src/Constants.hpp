#pragma once
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <cmath>

namespace bm {

// Tile characters (matching original Strings.swift Tile enum)
namespace Tile {
    constexpr char floor       = ' ';
    constexpr char dot         = '.';
    constexpr char wall        = '#';
    constexpr char hideout     = 'H';
    constexpr char printer    = 'P';
    constexpr char fax        = 'F';
    constexpr char coverSheet = 'C';
    constexpr char bookBinder = 'M';
    constexpr char brownBox   = 'D';
    constexpr char goldDisc   = 'O';
    constexpr char worker     = 'W';
    constexpr char boss1      = '1';
    constexpr char boss2      = '2';
    constexpr char boss3      = '3';
    constexpr char boss4      = '4';
    constexpr char waterGun   = 'G';
    constexpr char waterPellet = 'A';
}

// Timing
constexpr float TILE_SIZE       = 32.0f;
constexpr float WORKER_MOVE_DUR = 0.14f;
constexpr float BOSS_MOVE_INTERVAL = 0.36f;
constexpr float BOSS_MOVE_DURATION = 0.22f;
// Tunnel speed ramp: the slow floor is 1/slowdown of full speed on the two
// steps adjacent to a tunnel mouth (worker 4 => 0.25, boss 8 => 0.125).
constexpr float WORKER_TUNNEL_SLOWDOWN = 4.0f;
constexpr float BOSS_TUNNEL_SLOWDOWN   = 8.0f;
constexpr float GOLD_DISC_DUR  = 20.0f;
constexpr float SPAWN_SHIELD_DUR = 3.0f;
constexpr float SPAWN_FREEZE_DUR = 2.0f;
constexpr float SPAWN_THROB_DUR  = 1.0f; // post-spawn pulse: 3x scale 1.0->1.18
constexpr float MACHINE_COOLDOWN = 15.0f; // collected machine dims, then ungrays
constexpr float DETECTION_RANGE  = 10.0f;
constexpr int   GRID_COLS        = 37;
constexpr int   GRID_ROWS        = 17;
constexpr int   WINDOW_WIDTH     = 1184;
constexpr int   WINDOW_HEIGHT    = 666;  // 16:9 to match SpriteKit scene 1183x665.44
#ifdef __APPLE__
const std::string WINDOW_TITLE = "BOSS-MAN MAC";
#else
const std::string WINDOW_TITLE = "BOSS-MAN PC";
#endif
constexpr int   HUD_HEIGHT       = 100;
constexpr int   MAX_LIVES        = 5;
constexpr int   STARTING_LIVES   = 3;
constexpr int   WATER_GUN_PELLETS = 8;
constexpr float WATER_DROPLET_SPEED = 320.0f;
constexpr float WATER_DROPLET_MAX_DIST = 576.0f;
constexpr float WATER_DROPLET_RADIUS = 5.0f;

// Worker default spawn
struct GridPos {
    int x, y;
    bool operator==(const GridPos& o) const { return x == o.x && y == o.y; }
    bool operator!=(const GridPos& o) const { return !(*this == o); }
};

constexpr GridPos WORKER_SPAWN = {18, 7};

// Gold disc default positions
inline std::vector<GridPos> defaultGoldDiscPositions() {
    return {{2,15}, {33,15}, {2,1}, {33,1}};
}

// Machine names
namespace Machine {
    const std::string PRINTER     = "TPS Printer";
    const std::string FAX         = "TPS Fax Machine";
    const std::string COVER_SHEET = "TPS Cover Sheet";
    const std::string BOOK_BINDER = "TPS Book Binder";
    const std::string BROWN_BOX   = "TPS Delivery Box";

    const std::vector<std::string> REQUIRED = {PRINTER, FAX, COVER_SHEET, BOOK_BINDER};

    const std::unordered_map<std::string, std::string> DISPLAY_NAMES = {
        {PRINTER, "Printer"}, {FAX, "Fax"},
        {COVER_SHEET, "Cover Sheet"}, {BOOK_BINDER, "Book Binder"}
    };
}

// Machine name lookup by tile character. Construct-on-first-use: building this as
// an inline global copied the Machine:: strings before they were initialized
// (static-init-order fiasco), leaving the values empty. A function-local static is
// initialized on first call, after the namespace constants exist.
inline const std::unordered_map<char, std::string>& MACHINE_NAMES_BY_TILE() {
    static const std::unordered_map<char, std::string> m = {
        {Tile::printer,    Machine::PRINTER},
        {Tile::fax,        Machine::FAX},
        {Tile::coverSheet, Machine::COVER_SHEET},
        {Tile::bookBinder, Machine::BOOK_BINDER},
        {Tile::brownBox,   Machine::BROWN_BOX}
    };
    return m;
}

// Boss names. These are compile-time string literals (not std::string) on
// purpose: BOSS_BLUEPRINTS below is an inline global whose dynamic initialization
// can run before namespace-scope std::string constants are constructed (the same
// static-init-order trap documented for MACHINE_NAMES_BY_TILE). Copying a
// const char* literal into BossBlueprint::name has no such ordering dependency,
// so the boss name tags are never empty.
namespace Boss {
    inline constexpr const char* BILL = "BILL";
    inline constexpr const char* DOM  = "DOM";
    inline constexpr const char* BOB  = "BOB";
    inline constexpr const char* STAN = "STAN";
}

// Worker
namespace Worker {
    const std::string PETE = "PETE";
}

// Report item points
constexpr int REPORT_ITEM_POINTS[] = {10, 25, 50, 100};

// Cubicle colors (RGB)
struct Color {
    float r, g, b, a;
    constexpr Color(float r_=0, float g_=0, float b_=0, float a_=1)
        : r(r_), g(g_), b(b_), a(a_) {}
};

inline constexpr Color CUBICLE_COLORS[] = {
    {0.04f, 0.48f, 1.0f, 1.0f},   // blue
    {0.16f, 0.73f, 0.78f, 1.0f},  // teal
    {0.35f, 0.24f, 0.73f, 1.0f},  // indigo
    {0.20f, 0.78f, 0.35f, 1.0f},  // green
    {1.0f, 0.41f, 0.71f, 1.0f},   // pink
    {0.63f, 0.42f, 0.21f, 1.0f},  // brown
    {0.58f, 0.30f, 0.82f, 1.0f},  // purple
    {1.0f, 0.27f, 0.23f, 1.0f},   // red
    {1.0f, 0.55f, 0.0f, 1.0f},    // orange
    {1.0f, 0.91f, 0.34f, 1.0f},   // yellow
    {0.03f, 0.80f, 0.94f, 1.0f},  // cyan
    {0.56f, 0.56f, 0.58f, 1.0f}   // gray
};

inline constexpr Color SKIN_COLOR    = {0.96f, 0.78f, 0.62f, 1.0f};
inline constexpr Color SHOE_COLOR    = {0.12f, 0.08f, 0.05f, 1.0f};
inline constexpr Color BLACK         = {0.0f, 0.0f, 0.0f, 1.0f};
inline constexpr Color WHITE         = {1.0f, 1.0f, 1.0f, 1.0f};
inline constexpr Color PETE_BODY     = {0.04f, 0.48f, 1.0f, 1.0f};   // systemBlue
inline constexpr Color PETE_TIE      = {1.0f, 0.55f, 0.0f, 1.0f};    // systemOrange
inline constexpr Color PETE_HAIR     = {0.25f, 0.15f, 0.08f, 1.0f};  // dark brown
inline constexpr Color PETE_PANTS    = {0.70f, 0.45f, 0.18f, 1.0f};  // khaki
inline constexpr Color PETE_SHOE_OUT = {1.0f, 1.0f, 1.0f, 1.0f};     // white outline
inline constexpr Color YELLOW        = {1.0f, 0.91f, 0.34f, 1.0f};
inline constexpr Color RED           = {1.0f, 0.27f, 0.23f, 1.0f};
inline constexpr Color GREEN         = {0.20f, 0.78f, 0.35f, 1.0f};
inline constexpr Color CYAN          = {0.03f, 0.80f, 0.94f, 1.0f};
inline constexpr Color DARK_BG       = {0.06f, 0.06f, 0.07f, 1.0f};

// Boss flee colors
inline constexpr Color FLEE_BODY = {0.04f*0.8f, 0.48f*0.8f, 1.0f*0.8f, 1.0f};
// Frighten-mode tie shares FLEE_SKIN: same blue tint as the face/hands.
inline constexpr Color FLEE_TIE  = {0.62f, 0.78f, 0.96f, 1.0f};
inline constexpr Color FLEE_EYE  = {0.02f, 0.24f, 0.50f, 1.0f};
// Frighten-mode face/hands tint. SKIN_COLOR is {0.96, 0.78, 0.62};
// FLEE_SKIN swaps R and B so per-channel brightness sums match exactly.
inline constexpr Color FLEE_SKIN = {0.62f, 0.78f, 0.96f, 1.0f};
inline constexpr Color BOSS_SHOE_GOLD = {0.70f, 0.50f, 0.0f, 1.0f};
inline constexpr Color BOSS_HAIR     = {0.55f, 0.45f, 0.35f, 1.0f}; // medium brown

// Boss identity + behavior. The spawn/home position is intentionally NOT stored
// here: it comes only from the level map ('1'..'4' tiles), so a boss's home lives
// in level data, never in code. This is deliberate — a hardcoded spawn here once
// let a level with no boss tile fall back to a fixed corner (Bill at 34,15).
struct BossBlueprint {
    std::string name;
    Color bodyColor;
    Color tieColor;
    Color pantsColor;
    int personality; // 0=directChase, 1=ambush, 2=flanker, 3=timidScatter
    float speed;
};

inline const BossBlueprint BOSS_BLUEPRINTS[] = {
    {Boss::BILL, {1.0f,0.27f,0.23f,1.0f}, {0.0f,0.0f,0.0f,1.0f}, {0.33f,0.33f,0.33f,1.0f}, 0, 0.90f},
    {Boss::DOM,  {1.0f,0.41f,0.71f,0.75f}, {0.35f,0.0f,0.53f,1.0f}, {0.33f,0.33f,0.33f,1.0f}, 1, 0.80f},
    {Boss::BOB,  {0.16f,0.73f,0.78f,1.0f}, {0.0f,0.0f,0.80f,1.0f}, {0.33f,0.33f,0.33f,1.0f}, 2, 0.70f},
    {Boss::STAN, {1.0f,0.55f,0.0f,1.0f},   {0.90f,0.0f,0.0f,1.0f}, {0.33f,0.33f,0.33f,1.0f}, 3, 0.60f}
};

// Messages
namespace Message {
    const std::string INTRO             = "Collect office dots and finish the TPS report!";
    const std::string PRACTICE_MODE     = "PRACTICE MODE - score not saved";
    const std::string PAUSED            = "Paused - press P to resume";
    const std::string NEED_TPS          = "Turn in at least 1 TPS report to complete the level!";
    const std::string BROWN_BOX_HINT    = "Brown boxes collect finished TPS reports.";
    const std::string TPS_READY         = "TPS report complete! Deliver it to a brown box.";
    const std::string NEW_GAME          = "New game! Collect dots and TPS reports.";
    const std::string GOLD_DISC_ACTIVE  = "Gold disc! Capture the bosses for 20 seconds.";
    const std::string GOLD_DISC_ENDED   = "Gold disc mode ended.";
    const std::string WATER_GUN_ACTIVE  = "Water gun! Shoot the bosses.";
    const std::string WATER_GUN_ENDED   = "Water gun empty.";
    const std::string WATER_GUN_EXPIRED = "Water gun time expired.";
    const std::string WATER_GUN_BLUE    = "Water pistol unavailable in blue boss mode.";
    const std::string BOSS_SPLASHED     = "SPLASH!";
    const std::string GAME_OVER         = "GAME OVER";
    const std::string PROMPT_NEW_GAME   = "PRESS P TO START A NEW GAME";
    const std::string PROMPT_TITLE      = "PRESS ESC FOR TITLE SCREEN";
}

// Title scene
namespace Title {
    const std::string GAME_TITLE = "BOSS-MAN";
    const std::string PRESS_SPACE = "P to Play | E for Editor";
}

// Level names
inline std::vector<std::string> levelNames() {
    std::vector<std::string> names;
    for (int i = 1; i <= 24; ++i)
        names.push_back("Level " + std::to_string(i));
    return names;
}

// Traveler definitions
struct TravelerDef {
    std::string emoji;
    int points;
    bool facesRight = false; // does the glyph naturally face right? (only the stapler)
};

inline const TravelerDef TRAVELERS[] = {
    {"\xf0\x9f\x90\x9f",       100},   // 🐟 Fish
    {"\xf0\x9f\x8d\xa9",       200},   // 🍩 Donut
    {"\xe2\x98\x95",           400},   // ☕ Coffee
    {"\xf0\x9f\xa5\xa4",       800},   // 🥤 Soda
    {"\xf0\x9f\x8d\x8e",       1000},  // 🍎 Apple
    {"\xe2\x9c\x82\xef\xb8\x8f",2000, true}, // ✂️ Stapler (faces right)
    {"\xf0\x9f\x8d\x89",       3000},  // 🍉 Melon
    {"\xf0\x9f\xa7\x87",       4000},  // 🧇 Waffle
    {"\xf0\x9f\x8d\xa6",       5000},  // 🍦 Ice Cream
    {"\xf0\x9f\x8e\x82",       6000},  // 🍰 Cake
    {"\xf0\x9f\x91\x80",       7000},  // 👀 Eyes
    {"\xf0\x9f\x91\x81\xef\xb8\x8f",8000}, // 👁️ Big Eye
};

inline constexpr int TRAVELER_COUNT = 12;

} // namespace bm