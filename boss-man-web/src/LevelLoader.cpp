#include "LevelLoader.hpp"
#include "Assets.hpp"
#include <nlohmann/json.hpp>
#include <iostream>

namespace bm {

namespace {
std::unordered_map<std::string, std::vector<std::string>> parseLevels(const std::string& text) {
    try {
        nlohmann::json j = nlohmann::json::parse(text);
        std::unordered_map<std::string, std::vector<std::string>> result;
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
    } catch (const std::exception& e) {
        std::cerr << "JSON parse error: " << e.what() << std::endl;
        return {};
    }
}
} // namespace

std::unordered_map<std::string, std::vector<std::string>> LevelLoader::loadFromFile(const std::string& path) {
    return parseLevels(loadText(path));
}

std::unordered_map<std::string, std::vector<std::string>> LevelLoader::loadFromAsset() {
    return parseLevels(loadText("assets/levels.json"));
}

} // namespace bm
