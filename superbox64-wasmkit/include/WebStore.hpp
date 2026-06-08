#pragma once
#include <string>
#include "abi.h"

namespace bm {

// localStorage-backed key/value, the web stand-in for save files. Keys are the
// former filenames (e.g. "highscore.txt", "leaderboard.txt", "levels.json").

inline std::string storeGet(const std::string& key) {
    int len = store_get(key.c_str(), (int)key.size(), nullptr, 0);
    if (len < 0) return {};
    std::string s(len, '\0');
    if (len > 0) store_get(key.c_str(), (int)key.size(), s.data(), len);
    return s;
}

inline void storeSet(const std::string& key, const std::string& val) {
    store_set(key.c_str(), (int)key.size(), val.data(), (int)val.size());
}

} // namespace bm
