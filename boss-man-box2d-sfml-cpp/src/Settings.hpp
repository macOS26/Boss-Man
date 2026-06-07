#pragma once
#include <array>
#include <string>
#include <cstdlib>
#include <vector>
#include "AppPaths.hpp"
#if defined(BOSS_MAN_WEB)
#include "WebStore.hpp"
#else
#include <fstream>
#endif

namespace bm {

// Era/zoom selection, mirroring MazeZoom in the SpriteKit master (Strings.swift).
// The persisted value is the era year, not a zoom percent: the cycle walks the
// eras WIDE -> ZOOM -> MACRO -> ISO -> RAY -> VOXEL. ISO/RAY/VOXEL are the 3D
// sentinels; the other eras drive the 2D follow-camera at zoomPercent. Invalid /
// unset storage collapses to defaultEra, matching MazeZoom.current.
struct MazeZoom {
    static constexpr int iso = 1985;    // ISO 3D (isometric painter view) — selectable; renders via the raycaster until the C++ Iso port lands (like VOXEL)
    static constexpr int doom = 1993;   // RAYCAST 3D (single-hit raycaster)
    static constexpr int voxel = 1994;  // VOXEL 3D (overhead voxel-span view)
    static constexpr int defaultEra = 1983;
    static constexpr std::array<int, 6> cycle{1980, 1982, 1983, 1985, 1993, 1994};

    static int current();
    static bool isDoom() { return current() == doom; }
    static bool isVoxel() { return current() == voxel; }
    static bool isIso() { return current() == iso; }
    static bool is3D() { return isDoom() || isVoxel() || isIso(); }   // any full-screen scene mode
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
            case 1980: return "LUMBERGH";
            case 1982: return "TWO BOBS";
            case 1983: return "MILTON";
            case 1985: return "WONDERLAND";
            case 1993: return "SEVERANCE";
            case 1994: return "LABYRINTH";
            default:   return std::to_string(current());
        }
    }
    static void advance();
    static bool inCycle(int z) {
        for (int e : cycle) if (e == z) return true;
        return false;
    }
};

// On-screen control widget, mirroring ControlMode in Strings.swift. HIDDEN means
// no widget: swipe-to-move + tap-to-fire; STICK/DPAD show the widget + the fire
// button and turn swipe/tap-fire off. onLeft = movement widget on the left, fire
// button on the opposite side. Persisted as the 0-4 ordinal.
struct ControlMode {
    enum Mode { Hidden = 0, StickLeft = 1, StickRight = 2, DpadLeft = 3, DpadRight = 4 };
    static constexpr int count = 5;
    static Mode current();
    static bool showsControl() { return current() != Hidden; }
    static bool showsStick() { Mode m = current(); return m == StickLeft || m == StickRight; }
    static bool showsDpad()  { Mode m = current(); return m == DpadLeft  || m == DpadRight; }
    static bool isHidden()   { return current() == Hidden; }
    static bool onLeft()     { Mode m = current(); return m == StickLeft || m == DpadLeft; }
    static std::string label() {
        switch (current()) {
            case StickLeft:  return "STICK LEFT";
            case StickRight: return "STICK RIGHT";
            case DpadLeft:   return "DPAD LEFT";
            case DpadRight:  return "DPAD RIGHT";
            default:         return "HIDDEN";
        }
    }
    static void advance();
};

// Title-screen toggles, persisted like the high score (settings.txt = "S,C,E"):
// bossTracksSquare defaults true (classic glide-then-dwell cadence); the control
// slot defaults to ControlMode::Hidden; the era slot defaults to MazeZoom::defaultEra.
class Settings {
public:
    static bool bossTracksSquare() { ensure(); return inst().square_; }
    static void setBossTracksSquare(bool v) { ensure(); inst().square_ = v; save(); }

    static int controlModeRaw()    { ensure(); return inst().control_; }
    static void setControlModeRaw(int v) { ensure(); inst().control_ = ((v % ControlMode::count) + ControlMode::count) % ControlMode::count; save(); }

    // The stored era year (one of MazeZoom::cycle). Backs MazeZoom::current.
    static int mazeEra() { ensure(); return inst().era_; }
    static void setMazeEra(int e) { ensure(); inst().era_ = e; save(); }

    // The 2D follow-camera zoom for the current era; consumers read this fresh at
    // level-build time (100 = full board, no follow camera).
    static int mazeZoom() { return MazeZoom::zoomPercent(); }
    static void advanceMazeZoom() { MazeZoom::advance(); }

private:
    bool square_ = true;
    int control_ = ControlMode::Hidden;
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
        // Split on commas. New format: square, control(0-4), era. Robust to the
        // legacy 4-field "S,L,H,E" — control reads field 1, era is the last field.
        std::vector<std::string> fld;
        size_t a = 0, b;
        while ((b = str.find(',', a)) != std::string::npos) { fld.push_back(str.substr(a, b - a)); a = b + 1; }
        fld.push_back(str.substr(a));
        if (!fld.empty() && !fld[0].empty()) s.square_ = (fld[0] != "0");
        if (fld.size() >= 2) {
            int c = std::atoi(fld[1].c_str());
            if (c >= 0 && c < ControlMode::count) s.control_ = c;
        }
        if (fld.size() >= 2) {
            int z = std::atoi(fld.back().c_str());
            if (MazeZoom::inCycle(z)) s.era_ = z;
            else if (z == 150) s.era_ = 1982;   // legacy zoom-percent storage
            else if (z == 200) s.era_ = 1983;
            else if (z == 100) s.era_ = 1980;
        }
    }

    static void save() {
        Settings& s = inst();
        std::string str = std::string(s.square_ ? "1" : "0") + "," + std::to_string(s.control_) + "," + std::to_string(s.era_);
#if defined(BOSS_MAN_WEB)
        storeSet("settings.txt", str);
#else
        std::ofstream f(appSupportPath("settings.txt"));
        if (f.is_open()) f << str;
#endif
    }

    friend struct MazeZoom;
    friend struct ControlMode;
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

inline ControlMode::Mode ControlMode::current() {
    int c = Settings::controlModeRaw();
    return (c >= 0 && c < count) ? (Mode)c : Hidden;
}

inline void ControlMode::advance() {
    Settings::setControlModeRaw((Settings::controlModeRaw() + 1) % count);
}

} // namespace bm
