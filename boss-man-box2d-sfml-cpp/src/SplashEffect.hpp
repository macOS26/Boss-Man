#pragma once
#include <SFML/Graphics.hpp>
#include <vector>
#include <algorithm>
#include <cmath>
#include <cstdlib>

namespace bm {

// Water-splash burst shown when a boss is hit by the squirt gun. Mirrors the
// SpriteKit spawnWaterSplash: 10 droplets fly outward, scale up then shrink while
// fading, over 0.35s. Cyan/blue, alpha 0.85.
class SplashEffect {
public:
    struct Particle {
        sf::Vector2f center;
        sf::Vector2f offset;  // total outward displacement over its life
        float baseRadius;
        sf::Color color;
        float age = 0.0f;
    };

    std::vector<Particle> particles;
    static constexpr float LIFE = 0.35f;

    void spawn(sf::Vector2f center) {
        const int count = 10;
        for (int i = 0; i < count; ++i) {
            float angle = (float)i / (float)count * 6.2831853f;
            float r = 22.0f + (float)(std::rand() % 27); // 22..48
            Particle p;
            p.center = center;
            p.offset = {std::cos(angle) * r, std::sin(angle) * r};
            p.baseRadius = 3.0f + (float)(std::rand() % 4); // 3..6
            p.color = (std::rand() & 1) ? sf::Color(50, 200, 240)   // systemCyan
                                        : sf::Color(10, 122, 255);  // systemBlue
            particles.push_back(p);
        }
    }

    void update(float dt) {
        for (auto& p : particles) p.age += dt;
        particles.erase(std::remove_if(particles.begin(), particles.end(),
            [](const Particle& p) { return p.age >= LIFE; }), particles.end());
    }

    void draw(sf::RenderTarget& target) {
        const float t1 = 0.1f / LIFE; // grow phase fraction
        for (auto& p : particles) {
            float t = p.age / LIFE; // 0..1
            float scale = (t < t1) ? 1.0f + 0.4f * (t / t1)
                                   : 1.4f - 1.3f * ((t - t1) / (1.0f - t1));
            float a = (t < t1) ? 0.85f : 0.85f * (1.0f - (t - t1) / (1.0f - t1));
            float radius = p.baseRadius * scale;
            if (radius < 0.5f || a <= 0.0f) continue;
            sf::Vector2f pos = p.center + p.offset * t;
            sf::CircleShape c(radius, 12);
            sf::Color col = p.color;
            col.a = (uint8_t)(a * 255);
            c.setFillColor(col);
            c.setPosition(pos.x - radius, pos.y - radius);
            target.draw(c);
        }
    }
};

} // namespace bm
