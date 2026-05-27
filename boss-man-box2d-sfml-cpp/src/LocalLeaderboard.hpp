#pragma once
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <algorithm>
#include "AppPaths.hpp"

namespace bm {

struct LeaderboardEntry {
    std::string name;
    int score;
};

// Simple persistent top-10 leaderboard (leaderboard.txt). Stands in for the
// SpriteKit LocalHighScores / Game Center board, which aren't available here.
class LocalLeaderboard {
public:
    static constexpr int MAX_ENTRIES = 10;

    void load(const std::string& path = "") {
        path_ = path.empty() ? appSupportPath("leaderboard.txt") : path;
        entries_.clear();
        std::ifstream f(path_);
        std::string line;
        while (std::getline(f, line)) {
            std::istringstream ss(line);
            int score;
            if (!(ss >> score)) continue;
            std::string name;
            std::getline(ss, name);
            size_t s = name.find_first_not_of(" \t");
            name = (s == std::string::npos) ? "" : name.substr(s);
            entries_.push_back({name, score});
        }
        sortTrim();
    }

    void record(const std::string& name, int score) {
        if (score <= 0) return;
        entries_.push_back({name, score});
        sortTrim();
        std::ofstream f(path_.empty() ? appSupportPath("leaderboard.txt") : path_);
        for (auto& e : entries_) f << e.score << "\t" << e.name << "\n";
    }

    const std::vector<LeaderboardEntry>& entries() const { return entries_; }

private:
    std::vector<LeaderboardEntry> entries_;
    std::string path_ = "leaderboard.txt";

    void sortTrim() {
        std::stable_sort(entries_.begin(), entries_.end(),
            [](const LeaderboardEntry& a, const LeaderboardEntry& b) { return a.score > b.score; });
        if ((int)entries_.size() > MAX_ENTRIES) entries_.resize(MAX_ENTRIES);
    }
};

} // namespace bm
