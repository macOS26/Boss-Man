#include "LevelLoader.hpp"
#include <nlohmann/json.hpp>
#include <fstream>
#include <iostream>

namespace bm {

std::unordered_map<std::string, std::vector<std::string>> LevelLoader::loadFromFile(const std::string& path) {
    std::ifstream file(path);
    if (!file.is_open()) {
        std::cerr << "Failed to open levels file: " << path << std::endl;
        return {};
    }
    try {
        nlohmann::json j;
        file >> j;
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

std::unordered_map<std::string, std::vector<std::string>> LevelLoader::loadFromAsset() {
    return loadFromFile("assets/levels.json");
}

} // namespace bm