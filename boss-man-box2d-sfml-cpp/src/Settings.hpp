#pragma once
#include <string>
#include "AppPaths.hpp"
#if !defined(BOSS_MAN_WEB)
#include <fstream>
#endif

namespace bm {

#if defined(BOSS_MAN_WEB)
std::string storeGet(const std::string& key);
void storeSet(const std::string& key, const std::string& value);
#endif

// Title-screen toggles, persisted like the high score (settings.txt = "S,L").
// bossTracksSquare defaults true (classic glide-then-dwell cadence, matching the
// shipped behaviour); waterGunLeft defaults false (fire button on the right).
class Settings {
public:
    static bool bossTracksSquare() { ensure(); return inst().square_; }
    static bool waterGunLeft()     { ensure(); return inst().left_; }
    static void setBossTracksSquare(bool v) { ensure(); inst().square_ = v; save(); }
    static void setWaterGunLeft(bool v)     { ensure(); inst().left_ = v; save(); }

private:
    bool square_ = true;
    bool left_ = false;
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
    }

    static void save() {
        Settings& s = inst();
        std::string str = std::string(s.square_ ? "1" : "0") + "," + (s.left_ ? "1" : "0");
#if defined(BOSS_MAN_WEB)
        storeSet("settings.txt", str);
#else
        std::ofstream f(appSupportPath("settings.txt"));
        if (f.is_open()) f << str;
#endif
    }
};

} // namespace bm
