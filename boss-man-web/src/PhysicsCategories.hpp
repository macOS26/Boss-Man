#pragma once
#include <cstdint>

namespace bm {

namespace PhysicsCat {
    constexpr uint16_t WORKER        = 1 << 0;
    constexpr uint16_t WALL         = 1 << 1;
    constexpr uint16_t DOT          = 1 << 2;
    constexpr uint16_t BOSS         = 1 << 3;
    constexpr uint16_t MACHINE      = 1 << 4;
    constexpr uint16_t TPS_BOX     = 1 << 5;
    constexpr uint16_t GOLD_DISC   = 1 << 6;
    constexpr uint16_t FISH         = 1 << 7;
    constexpr uint16_t WATER_GUN    = 1 << 8;
    constexpr uint16_t WATER_DROPLET = 1 << 9;
    constexpr uint16_t WATER_PELLET  = 1 << 10;
}

} // namespace bm