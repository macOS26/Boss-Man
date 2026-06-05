#pragma once
#include <array>
#include <string>
#include <cstdlib>
#include "AppPaths.hpp"
#if defined(BOSS_MAN_WEB)
#include "WebStore.hpp"
#else
#include <fstream>
#endif

namespace bm {

// Era/zoom selection, mirroring MazeZoom in the SpriteKit master (Strings.swift).
// The persisted value is the era year, not a zoom percent: the cycle walks the
// four eras 1980 -> 1982 -> 1983 -> 1993. 1993 is the DOOM sentinel (first-person
// 3D path); the other eras drive the 2D follow-camera at zoomPercent. Invalid /
// unset storage collapses to defaultEra, matching MazeZoom.current.
struct MazeZoom {
    static constexpr int doom = 1993;   // RAYCAST 3D (single-hit raycaster)
    static constexpr int voxel = 1994;  // VOXEL 3D (overhead voxel-span view)
    static constexpr int defaultEra = 1983;
    static constexpr std::array<int, 5> cycle{1980, 1982, 1983, 1993, 1994};

    static int current();
    static bool isDoom() { return current() == doom; }
    static bool isVoxel() { return current() == voxel; }
    static bool is3D() { return isDoom() || isVoxel(); }   // either first-person bonus
    // The 2D follow-camera zoom for each era (100 = no camera). Ms. Pac-Man = 150%,
    // Jr. Pac-Man = 200%; Pac-Man is classic 100%, the 3D modes use the 3D path instead.
    static int zoomPercent() {
        switch (current()) {
            case 1982: return 150;
            case 1983: return 200;
            default:   return 100;
        }
    }
    static std::string label() {
        switch (current()) {
            case 1980: return "FULLVIEW 2D";
            case 1982: return "ZOOMLENSE 2D";
            case 1983: return "MACROLENSE 2D";
            case 1993: return "RAYCAST 3D";
            case 1994: return "VOXEL 3D";
            default:   return std::to_string(current());
        }
    }
    static void advance();
    static bool inCycle(int z) {
        for (int e : cycle) if (e == z) return true;
        return false;
    }
};

// Title-screen toggles, persisted like the high score (settings.txt = "S,L,H,E").
// bossTracksSquare defaults true (classic glide-then-dwell cadence, matching the
// shipped behaviour); waterGunLeft defaults false (fire button on the right);
// waterGunHide defaults false (the third Water Gun state hides the fire button);
// the era slot defaults to MazeZoom::defaultEra (Strings.swift MazeZoom.current).
class Settings {
public:
    static bool bossTracksSquare() { ensure(); return inst().square_; }
    static bool waterGunLeft()     { ensure(); return inst().left_; }
    static bool waterGunHide()     { ensure(); return inst().hide_; }
    static void setBossTracksSquare(bool v) { ensure(); inst().square_ = v; save(); }
    static void setWaterGunLeft(bool v)     { ensure(); inst().left_ = v; save(); }
    static void setWaterGunHide(bool v)     { ensure(); inst().hide_ = v; save(); }

    // The stored era year (one of MazeZoom::cycle). Backs MazeZoom::current.
    static int mazeEra() { ensure(); return inst().era_; }
    static void setMazeEra(int e) { ensure(); inst().era_ = e; save(); }

    // The 2D follow-camera zoom for the current era; consumers read this fresh at
    // level-build time (100 = full board, no follow camera).
    static int mazeZoom() { return MazeZoom::zoomPercent(); }
    static void advanceMazeZoom() { MazeZoom::advance(); }

private:
    bool square_ = true;
    bool left_ = false;
    bool hide_ = false;
    int era_ = MazeZoom::defaultEra;
    bool loaded_ = false;

    static Settings& inst() { static Settings s; return s; }

    static void ensure() {
        Settings& s = inst();
        if (s.loaded_) return;
        s.loaded_ = true;
        std::string str;
#if defined(BOSS_MAN_WEB)
        str = storeGet("settings.txt");
#else
        std::ifstream f(appSupportPath("settings.txt"));
        if (f.is_open()) std::getline(f, str);
#endif
        if (str.size() >= 3) { s.square_ = (str[0] != '0'); s.left_ = (str[2] != '0'); }
        if (str.size() >= 5) { s.hide_ = (str[4] != '0'); }
        auto comma = str.rfind(',');
        if (comma != std::string::npos && str.find(',') != comma) {
            int z = std::atoi(str.c_str() + comma + 1);
            if (MazeZoom::inCycle(z)) s.era_ = z;
            else if (z == 150) s.era_ = 1982;   // legacy zoom-percent storage
            else if (z == 200) s.era_ = 1983;
            else if (z == 100) s.era_ = 1980;
        }
    }

    static void save() {
        Settings& s = inst();
        std::string str = std::string(s.square_ ? "1" : "0") + "," + (s.left_ ? "1" : "0") + "," + (s.hide_ ? "1" : "0") + "," + std::to_string(s.era_);
#if defined(BOSS_MAN_WEB)
        storeSet("settings.txt", str);
#else
        std::ofstream f(appSupportPath("settings.txt"));
        if (f.is_open()) f << str;
#endif
    }

    friend struct MazeZoom;
};

inline int MazeZoom::current() {
    int z = Settings::mazeEra();
    return inCycle(z) ? z : defaultEra;
}

inline void MazeZoom::advance() {
    int cur = current();
    size_t i = 0;
    for (size_t k = 0; k < cycle.size(); ++k) if (cycle[k] == cur) { i = k; break; }
    Settings::setMazeEra(cycle[(i + 1) % cycle.size()]);
}

} // namespace bm
