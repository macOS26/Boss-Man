#include "LevelStore.hpp"
#include "Constants.hpp"
#include "AppPaths.hpp"
#include <nlohmann/json.hpp>
#include <algorithm>
#if defined(BOSS_MAN_WEB)
#include "WebStore.hpp"
#else
#include "MacWindow.hpp"
#include <fstream>
#endif

namespace bm {

std::string LevelStore::fileURL() {
    return appSupportPath("levels.json"); // ~/Library/Application Support/Boss-Man
}

std::vector<std::string> LevelStore::normalize(const std::vector<std::string>& rows) {
    std::vector<std::string> out;
    out.reserve(MAP_ROWS);
    for (const auto& row : rows) {
        if ((int)row.size() == MAP_COLS) {
            out.push_back(row);
        } else if ((int)row.size() < MAP_COLS) {
            out.push_back(row + std::string(MAP_COLS - (int)row.size(), Tile::floor));
        } else {
            out.push_back(row.substr(0, MAP_COLS));
        }
    }
    while ((int)out.size() < MAP_ROWS)
        out.push_back(std::string(MAP_COLS, Tile::floor));
    if ((int)out.size() > MAP_ROWS)
        out.resize(MAP_ROWS);
    return out;
}

std::unordered_map<std::string, std::vector<std::string>> LevelStore::loadCustomLevels() const {
    std::unordered_map<std::string, std::vector<std::string>> result;
#if defined(BOSS_MAN_WEB)
    std::string blob = storeGet(fileURL());
    if (blob.empty()) return result;
    nlohmann::json j = nlohmann::json::parse(blob, nullptr, false);
#else
    std::ifstream f(fileURL());
    if (!f.is_open()) return result;
    nlohmann::json j = nlohmann::json::parse(f, nullptr, false);
#endif
    if (j.is_discarded() || !j.is_object()) return result;
    for (auto& [key, val] : j.items()) {
        if (!val.is_array()) continue;
        std::vector<std::string> rows;
        for (auto& row : val)
            if (row.is_string()) rows.push_back(row.get<std::string>());
        result[key] = rows;
    }
    return result;
}

void LevelStore::saveCustomLevels(
    const std::unordered_map<std::string, std::vector<std::string>>& levels) const {
    // ordered_json keeps keys sorted for a stable, diff-friendly file (matches the
    // Swift encoder's .sortedKeys).
    nlohmann::ordered_json j;
    std::vector<std::string> keys;
    keys.reserve(levels.size());
    for (auto& [k, v] : levels) keys.push_back(k);
    std::sort(keys.begin(), keys.end());
    for (auto& k : keys) j[k] = levels.at(k);
#if defined(BOSS_MAN_WEB)
    storeSet(fileURL(), j.dump(2));
#else
    std::ofstream f(fileURL(), std::ios::trunc);
    if (f.is_open()) f << j.dump(2);
#endif
}

std::vector<std::string> LevelStore::loadLevel(const std::string& name) const {
    auto custom = loadCustomLevels();
    auto it = custom.find(name);
    if (it != custom.end()) return normalize(it->second);
    auto bit = bundled_.find(name);
    if (bit != bundled_.end()) return normalize(bit->second);
    return {};
}

std::vector<std::string> LevelStore::loadLevel(int index) const {
    auto names = levelNames();
    if (index < 0 || index >= (int)names.size()) index = 0;
    auto rows = loadLevel(names[index]);
    if (!rows.empty()) return rows;
    // Fall back to an empty (all-floor) map so the editor always has something.
    return normalize({});
}

void LevelStore::saveLevel(const std::string& name, const std::vector<std::string>& rows) {
    auto custom = loadCustomLevels();
    custom[name] = rows;
    saveCustomLevels(custom);
}

void LevelStore::resetLevel(const std::string& name) {
    auto custom = loadCustomLevels();
    custom.erase(name);
    saveCustomLevels(custom);
}

void LevelStore::revealInFinder() const {
#if defined(BOSS_MAN_WEB)
    if (storeGet(fileURL()).empty()) storeSet(fileURL(), "{}");
#else
    std::string path = fileURL();
    std::ifstream probe(path);
    if (!probe.good()) {
        std::ofstream f(path, std::ios::trunc);
        if (f.is_open()) f << "{}";
    }
#ifdef __APPLE__
    macRevealInFinder(path.c_str());
#endif
#endif
}

} // namespace bm
