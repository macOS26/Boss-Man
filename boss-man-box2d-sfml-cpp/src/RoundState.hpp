#pragma once
#include <string>
#include <unordered_set>
#if defined(BOSS_MAN_WEB)
#include <cstdlib>
#include "WebStore.hpp"
#else
#include <fstream>
#include "AppPaths.hpp"
#endif

namespace bm {

class RoundState {
public:
    int level = 1;
    int lives = STARTING_LIVES;
    int score = 0;
    int dotCount = 0;
    int collectedDots = 0;
    int goldDiscCount = 0;
    int collectedGoldDiscs = 0;
    int tpsReportsDelivered = 0;
    std::unordered_set<std::string> reportItems;
    int currentReportScore = 0;
    int highScore = 0;
    bool practiceMode = false;

    void loadHighScore() {
#if defined(BOSS_MAN_WEB)
        std::string s = storeGet("highscore.txt");
        if (!s.empty()) highScore = std::atoi(s.c_str());
#else
        std::ifstream f(appSupportPath("highscore.txt"));
        if (f.is_open()) f >> highScore;
#endif
    }

    void saveHighScore() {
#if defined(BOSS_MAN_WEB)
        storeSet("highscore.txt", std::to_string(highScore));
#else
        std::ofstream f(appSupportPath("highscore.txt"));
        if (f.is_open()) f << highScore;
#endif
    }

    void bumpScore(int points) {
        score += points;
        if (!practiceMode && score > highScore) {
            highScore = score;
            saveHighScore();
        }
    }

    void resetForNewGame() {
        level = 1;
        lives = STARTING_LIVES;
        score = 0;
        tpsReportsDelivered = 0;
        collectedDots = 0;
        collectedGoldDiscs = 0;
        reportItems.clear();
        currentReportScore = 0;
    }

    void advanceLevel() {
        level++;
        collectedDots = 0;
        collectedGoldDiscs = 0;
        tpsReportsDelivered = 0;
        reportItems.clear();
        currentReportScore = 0;
    }
};

} // namespace bm