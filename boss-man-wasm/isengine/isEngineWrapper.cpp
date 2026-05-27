#include "isEngineWrapper.h"
#include <chrono>
#include <algorithm>

#if defined(IS_ENGINE_HTML_5) || defined(IS_ENGINE_SDL_2)

namespace sf
{

const Time Time::Zero;

Time seconds(float amount)      {return Time(static_cast<Int64>(amount * 1000000.f));}
Time milliseconds(Int32 amount) {return Time(static_cast<Int64>(amount) * 1000);}
Time microseconds(Int64 amount) {return Time(amount);}

static Int64 nowMicroseconds()
{
    return std::chrono::duration_cast<std::chrono::microseconds>(
               std::chrono::steady_clock::now().time_since_epoch()).count();
}

Clock::Clock() : m_startTime(microseconds(nowMicroseconds())) {}

const Time Clock::getElapsedTime()
{
    return microseconds(nowMicroseconds() - m_startTime.asMicroseconds());
}

Time Clock::restart()
{
    Int64 now = nowMicroseconds();
    Time elapsed = microseconds(now - m_startTime.asMicroseconds());
    m_startTime = microseconds(now);
    return elapsed;
}

Rect functionGetGlobalBounds(const Vector2f &position, const Vector2f &origin, const Vector2f &size)
{
    return Rect(static_cast<int>(position.x - origin.x),
                static_cast<int>(position.y - origin.y),
                static_cast<int>(size.x),
                static_cast<int>(size.y));
}

bool Rect::intersects(Rect const &rec) const
{
    int l = std::max(left, rec.left);
    int t = std::max(top, rec.top);
    int r = std::min(left + width, rec.left + rec.width);
    int b = std::min(top + height, rec.top + rec.height);
    return (l < r) && (t < b);
}

bool Rect::intersects(Rect const &rec1, Rect const &rec2) const
{
    int l = std::max(rec1.left, rec2.left);
    int t = std::max(rec1.top, rec2.top);
    int r = std::min(rec1.left + rec1.width, rec2.left + rec2.width);
    int b = std::min(rec1.top + rec1.height, rec2.top + rec2.height);
    return (l < r) && (t < b);
}

}

#endif
