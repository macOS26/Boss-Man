#pragma once
#include <SFML/System/Vector2.hpp>
#include "Constants.hpp"
#include "MoveDirection.hpp"
#include <vector>
#include <algorithm>

namespace bm {

struct WaterDroplet {
    sf::Vector2f pos;
    sf::Vector2f velocity;
    float distance = 0.0f;
    bool active = true;
};

class WaterGunState {
public:
    bool isActive = false;
    int pelletsRemaining = 0;
    std::vector<WaterDroplet> droplets;

    // No timer: the gun never expires. Emptying it just stops firing; it stays
    // picked up (HUD shows it) and a pellet pickup reloads it. Only a new level
    // (explicit deactivate) clears it, matching the SpriteKit WaterGunState.
    void activate() { isActive = true; pelletsRemaining = WATER_GUN_PELLETS; }
    void deactivate() { isActive = false; pelletsRemaining = 0; droplets.clear(); }
    void reloadPellets(int count) {
        pelletsRemaining = std::min(WATER_GUN_PELLETS, pelletsRemaining + count);
        if (pelletsRemaining > 0) isActive = true;
    }
    void addPellets(int count) {
        if (!isActive) return;
        pelletsRemaining = std::min(WATER_GUN_PELLETS, pelletsRemaining + count);
    }
    bool consumePellet() {
        if (!isActive || pelletsRemaining <= 0) return false;
        pelletsRemaining--;
        if (pelletsRemaining == 0) isActive = false; // can't fire, but stays picked up
        return true;
    }

    void fire(sf::Vector2f from, MoveDirection dir) {
        if (!consumePellet()) return;
        WaterDroplet d;
        auto delta = bm::delta(dir);
        // Spawn ahead of Pete by half a tile plus the droplet radius so the shot
        // clears his body instead of materializing inside it (matches SpriteKit's
        // tileSize/2 + radius + 2 launch offset).
        const float spawnOffset = TILE_SIZE / 2.f + WATER_DROPLET_RADIUS + 2.f;
        d.pos = sf::Vector2f(from.x + delta.x * spawnOffset, from.y - delta.y * spawnOffset);
        d.velocity = sf::Vector2f(delta.x * WATER_DROPLET_SPEED, -delta.y * WATER_DROPLET_SPEED);
        d.distance = 0;
        d.active = true;
        droplets.push_back(d);
    }

    void update(float dt) {
        for (auto& d : droplets) {
            if (!d.active) continue;
            d.pos += d.velocity * dt;
            d.distance += std::abs(d.velocity.x * dt) + std::abs(d.velocity.y * dt);
            if (d.distance > WATER_DROPLET_MAX_DIST) d.active = false;
        }
        droplets.erase(std::remove_if(droplets.begin(), droplets.end(),
            [](const WaterDroplet& d) { return !d.active; }), droplets.end());
    }
};

} // namespace bm