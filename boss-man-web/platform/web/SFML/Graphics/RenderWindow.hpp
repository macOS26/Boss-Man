#pragma once
#include "../System.hpp"
#include "../System/String.hpp"
#include "RenderTarget.hpp"
#include "../Window/Event.hpp"
#include "../Window/VideoMode.hpp"
#include "../Window/WindowStyle.hpp"
#include <string>

namespace sf {

// MARK: - RenderWindow
// The screen target (handle 0). pollEvent drains evt_poll and unpacks the
// (type,a,b,c,d) ints into the matching Event member. Most window controls
// (vsync, framerate, key-repeat, icon) are no-ops on web; isOpen tracks an
// explicit close() so the game's main loop can exit (the page itself stays up).
class RenderWindow : public RenderTarget {
public:
    RenderWindow() { m_target = 0; }
    RenderWindow(VideoMode mode, const String& title,
                 Uint32 = Style::Default, const ContextSettings& = ContextSettings()) {
        m_target = 0;
        create(mode, title);
    }

    void create(VideoMode mode, const String& title,
                Uint32 = Style::Default, const ContextSettings& = ContextSettings()) {
        m_target = 0;
        m_open = true;
        m_size = {mode.width, mode.height};
        setTitle(title);
    }

    bool isOpen() const { return m_open; }
    void close() { m_open = false; }

    bool pollEvent(Event& event) {
        int type = 0, a = 0, b = 0, c = 0, d = 0;
        if (!evt_poll(&type, &a, &b, &c, &d)) return false;
        event.type = (Event::EventType)type;
        switch (event.type) {
        case Event::KeyPressed:
        case Event::KeyReleased:
            event.key.code    = (Keyboard::Key)a;
            event.key.shift   = b != 0;
            event.key.system  = c != 0;
            event.key.control = false;
            event.key.alt     = false;
            break;
        case Event::MouseButtonPressed:
        case Event::MouseButtonReleased:
            event.mouseButton.button = (Mouse::Button)a;
            event.mouseButton.x      = b;
            event.mouseButton.y      = c;
            break;
        case Event::MouseMoved:
            event.mouseMove.x = a;
            event.mouseMove.y = b;
            break;
        case Event::MouseWheelScrolled:
            event.mouseWheelScroll.wheel = Mouse::VerticalWheel;
            event.mouseWheelScroll.delta = (float)a;
            event.mouseWheelScroll.x     = b;
            event.mouseWheelScroll.y     = c;
            break;
        case Event::Resized:
            event.size.width  = (unsigned)a;
            event.size.height = (unsigned)b;
            m_size = {(unsigned)a, (unsigned)b};
            break;
        case Event::JoystickButtonPressed:
        case Event::JoystickButtonReleased:
            event.joystickButton.joystickId = (unsigned)a;
            event.joystickButton.button     = (unsigned)b;
            break;
        case Event::JoystickMoved:
            event.joystickMove.joystickId = (unsigned)a;
            event.joystickMove.axis       = (Joystick::Axis)b;
            event.joystickMove.position   = (float)c;
            break;
        default:
            break;
        }
        return true;
    }

    void display() {}

    Vector2u getSize() const override {
        return Vector2u((unsigned)win_width(), (unsigned)win_height());
    }

    void setTitle(const String& title) {
        const std::string& s = title.bytes();
        win_set_title(s.c_str(), (int)s.size());
    }

    void setFramerateLimit(unsigned int) {}
    void setVerticalSyncEnabled(bool) {}
    void setKeyRepeatEnabled(bool) {}
    void setMouseCursorVisible(bool) {}
    void setActive(bool = true) {}
    void requestFocus() {}
    bool hasFocus() const { return true; }
    void setIcon(unsigned int, unsigned int, const Uint8*) {}

    void* getSystemHandle() const { return nullptr; }

private:
    bool     m_open{false};
    Vector2u m_size{0, 0};
};

}  // namespace sf
