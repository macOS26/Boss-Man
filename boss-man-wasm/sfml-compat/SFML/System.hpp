#pragma once
// Compat shim: VRSFML has no umbrella headers and renamed several core types
// (Vec2 not Vector2, Rect2 not Rect, base::U8 not Uint8). This header (first on
// the include path) restores the SFML-2.x spellings the source uses so most of
// the code compiles unchanged; the structural differences are ported in code.
#include <SFML/System/Vec2.hpp>
#include <SFML/System/Rect2.hpp>
#include <SFML/System/Clock.hpp>
#include <SFML/System/Time.hpp>
#include <SFML/System/Angle.hpp>
#include <SFML/Base/IntTypes.hpp>

namespace sf {
template <class T> using Vector2 = Vec2<T>;
using Vector2f = Vec2<float>;
using Vector2i = Vec2<int>;
using Vector2u = Vec2<unsigned int>;

template <class T> using Rect = Rect2<T>;
using FloatRect = Rect2<float>;
using IntRect   = Rect2<int>;

using Uint8  = base::U8;
using Int16  = base::I16;
using Uint16 = base::U16;
using Int32  = base::I32;
using Uint32 = base::U32;
} // namespace sf
