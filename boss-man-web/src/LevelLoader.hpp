#pragma once
#include <string>
#include <vector>
#include <unordered_map>

namespace bm {

class LevelLoader {
public:
    static std::unordered_map<std::string, std::vector<std::string>> loadFromFile(const std::string& path);
    static std::unordered_map<std::string, std::vector<std::string>> loadFromAsset();
};

} // namespace bm