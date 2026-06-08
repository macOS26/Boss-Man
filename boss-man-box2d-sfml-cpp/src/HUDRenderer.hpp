#pragma once
#include <SFML/Graphics.hpp>
#include <string>
#include <unordered_set>
#include "Constants.hpp"
#include "PixelPersonRenderer.hpp"

namespace bm {

// 1:1 port of the SpriteKit HUD (Boss-Man/HUD.swift). SpriteKit uses a
// bottom-left origin (+Y up) with top = scene.height; SFML uses a top-left
// origin (+Y down). The scene height matches WINDOW_HEIGHT, so every Swift
// position `top - d` (distance d below the top edge) becomes the SFML Y `d`.
// Helpers below take the Swift "distance below top" directly so the literal
// constants from the spec carry over unchanged.
class HUDRenderer {
public:
    int lives = STARTING_LIVES;
    int score = 0;
    int highScore = 0;
    int level = 1;
    int collectedDots = 0;
    int dotCount = 0;
    int tpsReports = 0;
    std::unordered_set<std::string> reportItems;
    bool waterGunActive = false;
    bool waterGunVisible = false; // picked up this level (stays shown even when empty)
    int waterGunPellets = 0;
    bool goldDiscActive = false;  // blueMode: gun shows dimmed blue
    bool isGameOver = false;      // the full-screen game-over combo is drawn by Game

    // extraRow == the 100% (full-board) layout: borderless, with the extra bottom
    // row (high score / dots counter / traveler accumulation). 150%/200% draw the
    // bordered panel and no bottom row. Game sets this from Settings::mazeZoom().
    bool extraRow = false;
    // BOSS 3D forces the compact (150/200%-style) mini HUD regardless of the era's
    // zoomPercent (which is 100 for the 1993 DOOM era).
    bool compactHud = false;

    void showMessage(const std::string& text, float duration);
    void showPaused(bool paused);
    void update(float dt);
    void draw(sf::RenderTarget& target, float windowWidth, float windowHeight);

private:
    PixelPersonRenderer peteIcon_; // default config is PETE; used for life icons

    // The progress message / PAUSED overlay. The message crossfades with the TPS
    // checklist (same centre); score/dice/gun/ammo dim to 1/3 alpha while it shows.
    // SpriteKit drives this with SKActions; there is no Task.sleep on wasm, so the
    // crossfade is integrated from update(dt) instead.
    std::string message_;
    float messageHold_ = 0.f;   // remaining steady-state seconds (>0 => showing)
    float messageFade_ = 0.f;   // 0..1 crossfade progress (1 = fully shown)
    bool  messageOut_ = false;  // true once the hold elapsed and we fade back out
    bool  paused_ = false;      // PAUSED latches the dim until resumed
    float messageSize_ = 25.72f;

    sf::Clock blinkClock_; // drives the game-over prompt blink (legacy path)
};

} // namespace bm
