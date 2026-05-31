#pragma once
#include <string>
#include <vector>
#include <sstream>
#include <algorithm>
#if defined(BOSS_MAN_WEB)
#include "WebStore.hpp"
#else
#include <fstream>
#include "AppPaths.hpp"
#endif

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
#if defined(BOSS_MAN_WEB)
        path_ = path.empty() ? "leaderboard.txt" : path;
        entries_.clear();
        std::istringstream f(storeGet(path_));
#else
        path_ = path.empty() ? appSupportPath("leaderboard.txt") : path;
        entries_.clear();
        std::ifstream f(path_);
#endif
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
#if defined(BOSS_MAN_WEB)
        std::ostringstream f;
        for (auto& e : entries_) f << e.score << "\t" << e.name << "\n";
        storeSet(path_.empty() ? "leaderboard.txt" : path_, f.str());
#else
        std::ofstream f(path_.empty() ? appSupportPath("leaderboard.txt") : path_);
        for (auto& e : entries_) f << e.score << "\t" << e.name << "\n";
#endif
    }

    const std::vector<LeaderboardEntry>& entries() const { return entries_; }

    // True when `score` would land in the top 10 (board not full, or beats the
    // lowest entry). Mirrors LocalHighScores.qualifies.
    bool qualifies(int score) const {
        if (score <= 0) return false;
        if ((int)entries_.size() < MAX_ENTRIES) return true;
        return score > entries_.back().score;
    }

    // Last-entered name, persisted alongside the board (username.txt), so the
    // game-over name field defaults to it. Mirrors LocalHighScores.savedUsername.
    std::string savedName() const {
#if defined(BOSS_MAN_WEB)
        std::istringstream f(storeGet("username.txt"));
#else
        std::ifstream f(appSupportPath("username.txt"));
#endif
        std::string n;
        std::getline(f, n);
        return n;
    }

    void saveName(const std::string& name) {
#if defined(BOSS_MAN_WEB)
        storeSet("username.txt", name);
#else
        std::ofstream f(appSupportPath("username.txt"));
        f << name;
#endif
    }

private:
    std::vector<LeaderboardEntry> entries_;
    std::string path_; // resolved to appSupportPath("leaderboard.txt") on load/record

    void sortTrim() {
        std::stable_sort(entries_.begin(), entries_.end(),
            [](const LeaderboardEntry& a, const LeaderboardEntry& b) { return a.score > b.score; });
        if ((int)entries_.size() > MAX_ENTRIES) entries_.resize(MAX_ENTRIES);
    }
};

} // namespace bm
