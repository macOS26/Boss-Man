#pragma once
#include "../System.hpp"
#include "../../abi.h"

namespace sf {

// MARK: - Mouse
class Mouse {
public:
    enum Button {
        Left,
        Right,
        Middle,
        XButton1,
        XButton2,
        ButtonCount
    };

    enum Wheel {
        VerticalWheel,
        HorizontalWheel
    };

    static bool isButtonPressed(Button button) { return mouse_button((int)button) != 0; }
    static Vector2i getPosition() { return Vector2i(mouse_x(), mouse_y()); }
};

}  // namespace sf
