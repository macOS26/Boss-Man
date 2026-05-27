#pragma once
#include "../System.hpp"
#include "Keyboard.hpp"
#include "Mouse.hpp"
#include "Joystick.hpp"
#include "VideoMode.hpp"
#include "WindowStyle.hpp"

namespace sf {

// MARK: - Event
// EventType ordering matches SFML 2.6 exactly so evt_poll's `type` lines up with
// the JS runtime. RenderWindow::pollEvent maps the (type,a,b,c,d) ints from
// evt_poll into the matching member struct.
class Event {
public:
    struct SizeEvent {
        unsigned int width;
        unsigned int height;
    };

    struct KeyEvent {
        Keyboard::Key code;
        bool          alt;
        bool          control;
        bool          shift;
        bool          system;
    };

    struct TextEvent {
        Uint32 unicode;
    };

    struct MouseMoveEvent {
        int x;
        int y;
    };

    struct MouseButtonEvent {
        Mouse::Button button;
        int           x;
        int           y;
    };

    struct MouseWheelEvent {
        int delta;
        int x;
        int y;
    };

    struct MouseWheelScrollEvent {
        Mouse::Wheel wheel;
        float        delta;
        int          x;
        int          y;
    };

    struct JoystickConnectEvent {
        unsigned int joystickId;
    };

    struct JoystickMoveEvent {
        unsigned int   joystickId;
        Joystick::Axis axis;
        float          position;
    };

    struct JoystickButtonEvent {
        unsigned int joystickId;
        unsigned int button;
    };

    enum EventType {
        Closed,
        Resized,
        LostFocus,
        GainedFocus,
        TextEntered,
        KeyPressed,
        KeyReleased,
        MouseWheelMoved,
        MouseWheelScrolled,
        MouseButtonPressed,
        MouseButtonReleased,
        MouseMoved,
        MouseEntered,
        MouseLeft,
        JoystickButtonPressed,
        JoystickButtonReleased,
        JoystickMoved,
        JoystickConnected,
        JoystickDisconnected,
        TouchBegan,
        TouchMoved,
        TouchEnded,
        SensorChanged,

        Count
    };

    EventType type;

    union {
        SizeEvent             size;
        KeyEvent              key;
        TextEvent             text;
        MouseMoveEvent        mouseMove;
        MouseButtonEvent      mouseButton;
        MouseWheelEvent       mouseWheel;
        MouseWheelScrollEvent mouseWheelScroll;
        JoystickMoveEvent     joystickMove;
        JoystickButtonEvent   joystickButton;
        JoystickConnectEvent  joystickConnect;
    };
};

}  // namespace sf
