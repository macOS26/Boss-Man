#include "LevelLoader.hpp"
#include "Assets.hpp"
#include <nlohmann/json.hpp>
#include <iostream>

namespace bm {

namespace {
std::unordered_map<std::string, std::vector<std::string>> parseLevels(const std::string& text) {
    nlohmann::json j = nlohmann::json::parse(text, nullptr, false);
    std::unordered_map<std::string, std::vector<std::string>> result;
    if (j.is_discarded() || !j.is_object()) {
        std::cerr << "JSON parse error in levels" << std::endl;
        return result;
    }
    for (auto& [key, val] : j.items()) {
        if (val.is_array()) {
            std::vector<std::string> rows;
            for (auto& row : val) {
                if (row.is_string()) rows.push_back(row.get<std::string>());
            }
            result[key] = rows;
        }
    }
    return result;
}
} // namespace

std::unordered_map<std::string, std::vector<std::string>> LevelLoader::loadFromFile(const std::string& path) {
    return parseLevels(loadText(path));
}

std::unordered_map<std::string, std::vector<std::string>> LevelLoader::loadFromAsset() {
    return parseLevels(loadText("assets/levels.json"));
}

} // namespace bm
