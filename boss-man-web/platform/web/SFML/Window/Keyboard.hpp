#pragma once
#include "../../abi.h"

namespace sf {

// MARK: - Keyboard
// Enum values match SFML 2.6 exactly (A=0 .. Pause), so the ints handed to
// key_pressed() and carried in KeyPressed/KeyReleased events line up with the JS
// runtime's keymap. Deprecated aliases (BackSpace etc.) are kept for source compat.
class Keyboard {
public:
    enum Key {
        Unknown = -1,
        A = 0, B, C, D, E, F, G, H, I, J, K, L, M,
        N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
        Num0, Num1, Num2, Num3, Num4, Num5, Num6, Num7, Num8, Num9,
        Escape,
        LControl, LShift, LAlt, LSystem,
        RControl, RShift, RAlt, RSystem,
        Menu,
        LBracket, RBracket, Semicolon, Comma, Period, Apostrophe,
        Slash, Backslash, Grave, Equal, Hyphen,
        Space, Enter, Backspace, Tab,
        PageUp, PageDown, End, Home, Insert, Delete,
        Add, Subtract, Multiply, Divide,
        Left, Right, Up, Down,
        Numpad0, Numpad1, Numpad2, Numpad3, Numpad4,
        Numpad5, Numpad6, Numpad7, Numpad8, Numpad9,
        F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
        F13, F14, F15,
        Pause,

        KeyCount,

        Tilde     = Grave,
        Dash      = Hyphen,
        BackSpace = Backspace,
        BackSlash = Backslash,
        SemiColon = Semicolon,
        Return    = Enter,
        Quote     = Apostrophe
    };

    static bool isKeyPressed(Key key) { return key_pressed((int)key) != 0; }
};

}  // namespace sf
