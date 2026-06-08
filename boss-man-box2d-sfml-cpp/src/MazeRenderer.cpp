#include "MazeRenderer.hpp"
#include "EmojiText.hpp"
#include <algorithm>
#include <cstdint>

namespace bm {

// Deterministic 0..1 noise (pure LCG, no system RNG so it matches WASI/native
// byte-for-byte). State persists across every wall-tile build in a level, so
// each cubicle gets its own grain and the whole maze is reproducible per build.
// Ported verbatim from SpriteFactory.swift nextNoise().
static uint64_t g_noiseState = 0x9E3779B97F4A7C15ULL;
static float nextNoise() {
    g_noiseState = g_noiseState * 6364136223846793005ULL + 1442695040888963407ULL;
    return (float)((g_noiseState >> 40) & 0xFFFFFFULL) / (float)0xFFFFFF;
}

int MazeRenderer::build() {
    dotCount = 0;
    dotPresence.clear();
    workerSpawnFromMap = {-1, -1};
    bossSpawnsFromMap.clear();
    goldDiscPositionsFromMap.clear();
    waterGunPositionsFromMap.clear();
    waterPelletPositionsFromMap.clear();
    pickups.clear();
    dotVerts.clear();
    dotVerts.setPrimitiveType(sf::Quads);
    dotGridToQuad.clear();

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
                const sf::Color dotColor(255, 231, 0); // systemYellow
                const float dx = pos.x - 3.f, dy = pos.y - 3.f;
                dotGridToQuad[rowIndex * 1000 + colIndex] = (int)dotVerts.getVertexCount() / 4;
                dotVerts.append(sf::Vertex(sf::Vector2f(dx,       dy),       dotColor));
                dotVerts.append(sf::Vertex(sf::Vector2f(dx + 6.f, dy),       dotColor));
                dotVerts.append(sf::Vertex(sf::Vector2f(dx + 6.f, dy + 6.f), dotColor));
                dotVerts.append(sf::Vertex(sf::Vector2f(dx,       dy + 6.f), dotColor));
            }

            // Machines and pickups
            if (MACHINE_NAMES_BY_TILE().count(ch) && ch != Tile::brownBox) {
                Pickup p;
                p.grid = grid; p.pixelPos = pos; p.type = ch;
                p.machineName = MACHINE_NAMES_BY_TILE().at(ch);
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
            case Tile::worker:
                workerSpawnFromMap = grid;
                dotPresence[rowIndex][colIndex] = true;
                dotCount++;
                {
                    const sf::Color dotColor(255, 231, 0);
                    const float dx = pos.x - 3.f, dy = pos.y - 3.f;
                    dotGridToQuad[rowIndex * 1000 + colIndex] = (int)dotVerts.getVertexCount() / 4;
                    dotVerts.append(sf::Vertex(sf::Vector2f(dx,       dy),       dotColor));
                    dotVerts.append(sf::Vertex(sf::Vector2f(dx + 6.f, dy),       dotColor));
                    dotVerts.append(sf::Vertex(sf::Vector2f(dx + 6.f, dy + 6.f), dotColor));
                    dotVerts.append(sf::Vertex(sf::Vector2f(dx,       dy + 6.f), dotColor));
                }
                break;
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

    // Reset the noise LCG so each level build produces an identical, reproducible
    // grain regardless of how many levels were built before this one. The state
    // then advances sequentially across every wall tile in this build (44 draws
    // per wall, in the same tile order as the Swift master).
    g_noiseState = 0x9E3779B97F4A7C15ULL;

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

                // Deterministic noise grain: exactly 11 specks, each 4 RNG draws
                // (gx, gy, gs, color-pick) in that order — 44 LCG advances per
                // wall — ported verbatim from SpriteFactory.swift wallTile. The
                // grain sits in z-order between the fill and the panel stroke.
                // Swift positions specks by rect origin in tile-centered coords;
                // map to SFML top-left space by adding the tile center (tile/2).
                const float cx = x + tile * 0.5f;
                const float cy = y + tile * 0.5f;
                const float grain = tile - 5.f;
                for (int s = 0; s < 11; ++s) {
                    float gx = (nextNoise() - 0.5f) * grain;
                    float gy = (nextNoise() - 0.5f) * grain;
                    float gs = 1.f + nextNoise() * 1.5f;
                    bool dark = nextNoise() < 0.5f;
                    sf::RectangleShape speck(sf::Vector2f(gs, gs));
                    speck.setFillColor(dark ? sf::Color(0, 0, 0, 41)        // black, alpha 0.16
                                            : sf::Color(255, 255, 255, 23)); // white, alpha 0.09
                    speck.setPosition(cx + gx, cy + gy);
                    backgroundTexture.draw(speck);
                }

                // Wall border. SpriteKit centers a 2px stroke on rect.insetBy(2,2),
                // so the wall's outer edge sits 1px inside the tile and the floor
                // shows through between adjacent walls. SFML grows the outline
                // outward, so size the rect (tile-6, at offset 3) such that the 2px
                // outline lands at 1px..3px from the tile edge — never at the edge.
                sf::RectangleShape wallBorder(sf::Vector2f(tile-6, tile-6));
                wallBorder.setFillColor(sf::Color::Transparent);
                wallBorder.setOutlineColor(sf::Color(
                    (uint8_t)(cubCol.r*255), (uint8_t)(cubCol.g*255),
                    (uint8_t)(cubCol.b*255), 255));
                wallBorder.setOutlineThickness(2);
                wallBorder.setPosition(x+3, y+3);
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
    (void)dt;
    if (dotVerts.getVertexCount() > 0) target.draw(dotVerts);
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

    // Collapse the eaten dot's quad to a zero-area point so it stops drawing.
    int key = rowIndex * 1000 + col;
    auto it = dotGridToQuad.find(key);
    if (it != dotGridToQuad.end()) {
        int base = it->second * 4;
        if (base + 3 < (int)dotVerts.getVertexCount()) {
            sf::Vector2f p = dotVerts[base].position;
            for (int i = 0; i < 4; ++i) dotVerts[base + i].position = p;
        }
    }

    return true;
}

bool MazeRenderer::collectGold(int col, int row) {
    for (auto& p : pickups) {
        if (p.type == 'O' && p.grid.x == col && p.grid.y == row && p.active) {
            p.active = false;
            return true;
        }
    }
    return false;
}

bool MazeRenderer::collectWaterGun(int col, int row) {
    for (auto& p : pickups) {
        if (p.type == 'G' && p.grid.x == col && p.grid.y == row && p.active) {
            p.active = false;
            return true;
        }
    }
    return false;
}

bool MazeRenderer::collectWaterPellet(int col, int row) {
    for (auto& p : pickups) {
        if (p.type == 'A' && p.grid.x == col && p.grid.y == row && p.active) {
            p.active = false;
            return true;
        }
    }
    return false;
}

sf::Vector2f* MazeRenderer::touchedBrownBox(int col, int row) {
    for (auto& p : pickups) {
        if (p.type == Tile::brownBox && p.grid.x == col && p.grid.y == row && p.active) {
            return &p.pixelPos;
        }
    }
    return nullptr;
}

} // namespace bm