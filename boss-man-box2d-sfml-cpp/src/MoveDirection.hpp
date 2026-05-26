#pragma once
#include "Constants.hpp"

namespace bm {

enum class MoveDirection {
    Left, Right, Down, Up, None
};

inline GridPos delta(MoveDirection dir) {
    switch (dir) {
    case MoveDirection::Left:  return {-1, 0};
    case MoveDirection::Right: return {1, 0};
    case MoveDirection::Down:  return {0, -1};
    case MoveDirection::Up:    return {0, 1};
    default: return {0, 0};
    }
}

inline GridPos neighbor(GridPos grid, MoveDirection dir) {
    auto d = delta(dir);
    return {grid.x + d.x, grid.y + d.y};
}

inline bool isHorizontal(MoveDirection dir) {
    return dir == MoveDirection::Left || dir == MoveDirection::Right;
}

inline bool isVertical(MoveDirection dir) {
    return dir == MoveDirection::Up || dir == MoveDirection::Down;
}

} // namespace bm