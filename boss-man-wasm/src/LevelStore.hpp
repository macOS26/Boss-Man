#pragma once
#include <string>
#include <vector>
#include <unordered_map>

namespace bm {

// Mirrors the SpriteKit LevelStore: custom edited levels are persisted to a
// writable JSON file (~/Library/Application Support/Boss-Man/levels.json on
// macOS) and override the bundled levels shipped in assets/levels.json. Both the
// editor and the game consult loadLevel(), so edits take effect immediately and
// survive relaunches. All rows are normalized to the fixed 37x17 map size.
class LevelStore {
public:
    static constexpr int MAP_COLS = 37;
    static constexpr int MAP_ROWS = 17;

    // The bundled levels (assets/levels.json), set once at startup.
    void setBundled(const std::unordered_map<std::string, std::vector<std::string>>& m) {
        bundled_ = m;
    }

    // Custom rows if present, else bundled, normalized. Empty if neither exists.
    std::vector<std::string> loadLevel(const std::string& name) const;
    std::vector<std::string> loadLevel(int index) const;

    void saveLevel(const std::string& name, const std::vector<std::string>& rows);
    void resetLevel(const std::string& name);

    // Creates the file (empty JSON) if missing and reveals it in Finder (macOS).
    void revealInFinder() const;

    // Pad/truncate to exactly MAP_COLS x MAP_ROWS, filling with floor.
    static std::vector<std::string> normalize(const std::vector<std::string>& rows);

    // Absolute path to the custom levels file.
    static std::string fileURL();

private:
    std::unordered_map<std::string, std::vector<std::string>> bundled_;

    std::unordered_map<std::string, std::vector<std::string>> loadCustomLevels() const;
    void saveCustomLevels(const std::unordered_map<std::string, std::vector<std::string>>& levels) const;
};

} // namespace bm
