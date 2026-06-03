#pragma once
#include <string>
#include <cstdlib>
#include "AppPaths.hpp"
#if defined(BOSS_MAN_WEB)
#include "WebStore.hpp"
#else
#include <fstream>
#endif

namespace bm {

// Title-screen toggles, persisted like the high score (settings.txt = "S,L,H,Z").
// bossTracksSquare defaults true (classic glide-then-dwell cadence, matching the
// shipped behaviour); waterGunLeft defaults false (fire button on the right);
// waterGunHide defaults false (the third Water Gun state hides the fire button);
// mazeZoom defaults 100 (full board, no follow camera; cycles 100->150->200).
class Settings {
public:
    static bool bossTracksSquare() { ensure(); return inst().square_; }
    static bool waterGunLeft()     { ensure(); return inst().left_; }
    static bool waterGunHide()     { ensure(); return inst().hide_; }
    static void setBossTracksSquare(bool v) { ensure(); inst().square_ = v; save(); }
    static void setWaterGunLeft(bool v)     { ensure(); inst().left_ = v; save(); }
    static void setWaterGunHide(bool v)     { ensure(); inst().hide_ = v; save(); }

    // Read fresh at level-build time. Invalid/unset storage collapses to 100.
    static int mazeZoom() {
        ensure();
        int z = inst().zoom_;
        return (z == 100 || z == 150 || z == 200) ? z : 100;
    }
    // Walk 100 -> 150 -> 200 -> 100.
    static void advanceMazeZoom() {
        ensure();
        int z = mazeZoom();
        inst().zoom_ = (z == 100) ? 150 : (z == 150 ? 200 : 100);
        save();
    }

private:
    bool square_ = true;
    bool left_ = false;
    bool hide_ = false;
    int zoom_ = 100;
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
            if (z == 100 || z == 150 || z == 200) s.zoom_ = z;
        }
    }

    static void save() {
        Settings& s = inst();
        std::string str = std::string(s.square_ ? "1" : "0") + "," + (s.left_ ? "1" : "0") + "," + (s.hide_ ? "1" : "0") + "," + std::to_string(s.zoom_);
#if defined(BOSS_MAN_WEB)
        storeSet("settings.txt", str);
#else
        std::ofstream f(appSupportPath("settings.txt"));
        if (f.is_open()) f << str;
#endif
    }
};

} // namespace bm
