#include "MazeRenderer.hpp"
#include "EmojiText.hpp"
#include <algorithm>
#include <random>

namespace {
// Colored book variants used at random for each book-binder machine (📕📗📘📙).
const char* BOOK_EMOJIS[] = {
    "\xf0\x9f\x93\x95", "\xf0\x9f\x93\x97", "\xf0\x9f\x93\x98", "\xf0\x9f\x93\x99"};
std::string randomBook() {
    static std::mt19937 rng(std::random_device{}());
    return BOOK_EMOJIS[rng() % 4];
}
} // namespace

namespace bm {

int MazeRenderer::build() {
    dotCount = 0;
    dotPresence.clear();
    workerSpawnFromMap = {-1, -1};
    bossSpawnsFromMap.clear();
    goldDiscPositionsFromMap.clear();
    waterGunPositionsFromMap.clear();
    waterPelletPositionsFromMap.clear();
    pickups.clear();
    dotShapes.clear();
    dotGridToShapeIndex.clear();

    int cols = map.rows.empty() ? 0 : (int)map.rows[0].size();
    int rowCount = (int)map.rows.size();
    dotPresence.resize(rowCount, std::vector<bool>(cols, false));

    buildBackground();

    // Parse level data
    for (int rowIndex = 0; rowIndex < rowCount; ++rowIndex) {
        int gridY = rowCount - 1 - rowIndex;
        auto& row = map.rows[rowIndex];
        for (int colIndex = 0; colIndex < (int)row.size(); ++colIndex) {
            char ch = row[colIndex];
            GridPos grid = {colIndex, gridY};
            sf::Vector2f pos = map.pointFor(grid);

            if (ch == Tile::wall) continue;

            bool isBossSpawn = (ch >= '1' && ch <= '4');
            if ((ch == Tile::dot || ch == Tile::hideout || isBossSpawn)) {
                dotPresence[rowIndex][colIndex] = true;
                dotCount++;
                sf::RectangleShape dot(sf::Vector2f(6, 6));
                dot.setFillColor(sf::Color(255, 231, 0)); // systemYellow
                dot.setPosition(pos.x - 3, pos.y - 3);
                dotGridToShapeIndex[rowIndex * 1000 + colIndex] = (int)dotShapes.size();
                dotShapes.push_back(dot);
            }

            // Machines and pickups
            if (MACHINE_NAMES_BY_TILE().count(ch) && ch != Tile::brownBox) {
                Pickup p;
                p.grid = grid; p.pixelPos = pos; p.type = ch;
                p.machineName = MACHINE_NAMES_BY_TILE().at(ch);
                // Book binder shows a random colored book instead of the 📚 stack.
                if (ch == Tile::bookBinder) p.emojiOverride = randomBook();
                p.active = true;
                pickups.push_back(p);
            } else if (ch == Tile::brownBox) {
                Pickup p;
                p.grid = grid; p.pixelPos = pos; p.type = ch;
                p.machineName = Machine::BROWN_BOX;
                p.active = true;
                pickups.push_back(p);
            }

            switch (ch) {
            case Tile::goldDisc:   goldDiscPositionsFromMap.push_back(grid); break;
            case Tile::waterGun:   waterGunPositionsFromMap.push_back(grid); break;
            case Tile::waterPellet: waterPelletPositionsFromMap.push_back(grid); break;
            case Tile::worker:     workerSpawnFromMap = grid; break;
            case '1': bossSpawnsFromMap.push_back({0, grid}); break;
            case '2': bossSpawnsFromMap.push_back({1, grid}); break;
            case '3': bossSpawnsFromMap.push_back({2, grid}); break;
            case '4': bossSpawnsFromMap.push_back({3, grid}); break;
            }
        }
    }

    // Gold discs
    placedGoldDiscs = 0;
    auto discPositions = goldDiscPositionsFromMap.empty()
        ? defaultGoldDiscPositions() : goldDiscPositionsFromMap;
    for (auto& g : discPositions) {
        if (map.isWalkable(g)) {
            Pickup p;
            p.grid = g; p.pixelPos = map.pointFor(g); p.type = 'O';
            p.active = true;
            pickups.push_back(p);
            placedGoldDiscs++;
        }
    }

    // Water gun and pellets
    for (auto& g : waterGunPositionsFromMap) {
        if (map.isWalkable(g)) {
            Pickup p;
            p.grid = g; p.pixelPos = map.pointFor(g); p.type = 'G';
            p.active = true;
            pickups.push_back(p);
        }
    }
    for (auto& g : waterPelletPositionsFromMap) {
        if (map.isWalkable(g)) {
            Pickup p;
            p.grid = g; p.pixelPos = map.pointFor(g); p.type = 'A';
            p.active = true;
            pickups.push_back(p);
        }
    }

    return dotCount;
}

void MazeRenderer::buildBackground() {
    int cols = map.rows.empty() ? 0 : (int)map.rows[0].size();
    int rowCount = (int)map.rows.size();
    float tile = map.tileSize;

    if (!backgroundTexture.create(cols * (int)tile, rowCount * (int)tile))
        return;

    backgroundTexture.clear(sf::Color::Transparent);

    for (int rowIndex = 0; rowIndex < rowCount; ++rowIndex) {
        int gridY = rowCount - 1 - rowIndex;
        auto& row = map.rows[rowIndex];
        for (int colIndex = 0; colIndex < (int)row.size(); ++colIndex) {
            float x = colIndex * tile;
            // SFML Y-down: rowIndex 0 (top of level string) at top of texture
            float y = rowIndex * tile;
            char ch = row[colIndex];

            // Floor tile
            bool alternate = (gridY + colIndex) % 2 == 0;
            sf::Color floorColor = alternate
                ? sf::Color(28, 31, 33)   // lighter dark
                : sf::Color(23, 26, 28);  // darker dark
            sf::RectangleShape floorTile(sf::Vector2f(tile, tile));
            floorTile.setFillColor(floorColor);
            floorTile.setPosition(x, y);
            backgroundTexture.draw(floorTile);

            // Grid edge
            sf::RectangleShape edge(sf::Vector2f(tile-1, tile-1));
            edge.setFillColor(sf::Color::Transparent);
            edge.setOutlineColor(sf::Color(41,41,41));
            edge.setOutlineThickness(1);
            edge.setPosition(x+0.5f, y+0.5f);
            backgroundTexture.draw(edge);

            // Wall
            if (ch == Tile::wall) {
                auto& cubCol = cubicleColor;
                // Wall fill
                sf::RectangleShape wallFill(sf::Vector2f(tile-2, tile-2));
                wallFill.setFillColor(sf::Color(
                    (uint8_t)(cubCol.r*255*0.55), (uint8_t)(cubCol.g*255*0.55),
                    (uint8_t)(cubCol.b*255*0.55), 255));
                wallFill.setPosition(x+1, y+1);
                backgroundTexture.draw(wallFill);

                // Wall border
                sf::RectangleShape wallBorder(sf::Vector2f(tile-4, tile-4));
                wallBorder.setFillColor(sf::Color::Transparent);
                wallBorder.setOutlineColor(sf::Color(
                    (uint8_t)(cubCol.r*255), (uint8_t)(cubCol.g*255),
                    (uint8_t)(cubCol.b*255), 255));
                wallBorder.setOutlineThickness(2);
                wallBorder.setPosition(x+2, y+2);
                backgroundTexture.draw(wallBorder);

                // Gray trim (desk strip) — 6px from top of tile in both SpriteKit and SFML
                sf::RectangleShape trim(sf::Vector2f(tile-10, 4));
                trim.setFillColor(sf::Color(128,128,128));
                trim.setPosition(x+5, y+6);
                backgroundTexture.draw(trim);
            }
        }
    }

    backgroundTexture.display();
    backgroundSprite.setTexture(backgroundTexture.getTexture());
    backgroundSprite.setPosition(0, map.yOffset);
}

void MazeRenderer::drawBackground(sf::RenderTarget& target) {
    target.draw(backgroundSprite);
}

void MazeRenderer::drawDots(sf::RenderTarget& target, float dt) {
    for (auto& dot : dotShapes) {
        target.draw(dot);
    }
}

void MazeRenderer::drawPickups(sf::RenderTarget& target, float dt) {
    // Emoji UTF-8 strings (matching original SpriteKit emojis)
    static const std::string emojiPrinter   = "\xf0\x9f\x96\xa8\xef\xb8\x8f"; // 🖨️
    static const std::string emojiFax       = "\xf0\x9f\x93\xa0";              // 📠
    static const std::string emojiCover     = "\xf0\x9f\x93\x84";              // 📄
    static const std::string emojiBooks     = "\xf0\x9f\x93\x9a";              // 📚
    static const std::string emojiBox        = "\xf0\x9f\x93\xa6";              // 📦
    static const std::string emojiGun       = "\xf0\x9f\x94\xab";              // 🔫

    // Absolute elapsed time drives the throb so it is independent of how the
    // caller computes its frame delta. All pickups pulse in sync, like SpriteKit.
    float t = animClock.getElapsedTime().asSeconds();
    // Eased pulse that never shrinks below 1.0, matching SpriteKit scale actions:
    // gold/water gun 1.0<->1.25 over 0.7s, water pellet 1.0<->1.3 over 0.8s.
    float goldScale   = 1.0f + 0.25f * (0.5f - 0.5f * cos(t * 8.976f));
    float pelletScale = 1.0f + 0.30f * (0.5f - 0.5f * cos(t * 7.854f));
    float scale = goldScale;

    for (auto& p : pickups) {
        if (!p.active) continue;

        if (p.type == Tile::goldDisc) {
            // Gold disc: halo + core + specular (specular ABOVE center in SFML Y-down)
            float r = TILE_SIZE * 0.28f * scale;
            sf::CircleShape halo(r * 1.35f, 48);
            halo.setFillColor(sf::Color(255, 231, 0, 77));
            halo.setPosition(p.pixelPos.x - halo.getRadius(), p.pixelPos.y - halo.getRadius());
            target.draw(halo);

            sf::CircleShape core(r, 48);
            core.setFillColor(sf::Color(255, 231, 0, 217));
            core.setOutlineColor(sf::Color(178, 127, 0));
            core.setOutlineThickness(1);
            core.setPosition(p.pixelPos.x - r, p.pixelPos.y - r);
            target.draw(core);

            sf::CircleShape spec(r * 0.3f, 24);
            spec.setFillColor(sf::Color(255, 255, 255, 191));
            spec.setPosition(p.pixelPos.x - r*0.28f - spec.getRadius(),
                            p.pixelPos.y - r*0.28f - spec.getRadius());
            target.draw(spec);

        } else if (p.type == Tile::waterGun) {
            // Water gun: 🔫 emoji (full color, throbs with gold scale)
            drawEmoji(target, emojiGun, p.pixelPos, TILE_SIZE * 0.55f * scale);

        } else if (p.type == Tile::waterPellet) {
            // Water pellet: halo + core + specular (specular ABOVE center in SFML Y-down)
            float r = TILE_SIZE * 0.32f * pelletScale;
            sf::CircleShape halo(r * 1.35f, 48);
            halo.setFillColor(sf::Color(0, 200, 240, 64));
            halo.setPosition(p.pixelPos.x - halo.getRadius(), p.pixelPos.y - halo.getRadius());
            target.draw(halo);

            sf::CircleShape core(r, 48);
            core.setFillColor(sf::Color(0, 200, 240, 217));
            core.setOutlineColor(sf::Color(4, 122, 255));
            core.setOutlineThickness(1.5f);
            core.setPosition(p.pixelPos.x - r, p.pixelPos.y - r);
            target.draw(core);

            sf::CircleShape spec(r * 0.3f, 24);
            spec.setFillColor(sf::Color(255, 255, 255, 191));
            spec.setPosition(p.pixelPos.x - r*0.28f - spec.getRadius(),
                            p.pixelPos.y - r*0.28f - spec.getRadius());
            target.draw(spec);

        } else {
            // Machines/TPS items: emoji characters (matching original SpriteKit)
            std::string emojiUtf8;
            float emojiSize = 26.0f; // machines 26, brown box 28 (matches MazeBuilder.swift)
            switch (p.type) {
            case Tile::printer:     emojiUtf8 = emojiPrinter; break;
            case Tile::fax:         emojiUtf8 = emojiFax; break;
            case Tile::coverSheet:  emojiUtf8 = emojiCover; break;
            case Tile::bookBinder:  emojiUtf8 = emojiBooks; break;
            case Tile::brownBox:    emojiUtf8 = emojiBox; emojiSize = 28.0f; break;
            default:               emojiUtf8 = "?"; break;
            }
            if (!p.emojiOverride.empty()) emojiUtf8 = p.emojiOverride; // random book binder

            // Collected machines dim during their cooldown (SpriteKit alpha 0.55).
            uint8_t a = (p.cooldownTimer > 0.0f) ? 140 : 255;
            drawEmoji(target, emojiUtf8, p.pixelPos, emojiSize, sf::Color(255, 255, 255, a));
        }
    }
}

bool MazeRenderer::collectDot(int col, int row) {
    int rowCount = (int)dotPresence.size();
    if (rowCount == 0) return false;
    int rowIndex = rowCount - 1 - row; // Convert gridY to rowIndex
    if (rowIndex < 0 || rowIndex >= rowCount) return false;
    if (col < 0 || col >= (int)dotPresence[rowIndex].size()) return false;
    if (!dotPresence[rowIndex][col]) return false;

    dotPresence[rowIndex][col] = false;

    // Find and hide the corresponding dot shape
    int key = rowIndex * 1000 + col;
    auto it = dotGridToShapeIndex.find(key);
    if (it != dotGridToShapeIndex.end() && it->second < (int)dotShapes.size()) {
        dotShapes[it->second].setPosition(-100, -100);
    }

    return true;
}

} // namespace bm