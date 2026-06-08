#pragma once

namespace sf {

// MARK: - Joystick
// Inert on web: no gamepad ABI. isConnected returns false so the game's joystick
// code never activates, and getAxisPosition returns 0 (centered).
class Joystick {
public:
    enum {
        Count       = 8,
        ButtonCount = 32,
        AxisCount   = 8
    };

    enum Axis {
        X,
        Y,
        Z,
        R,
        U,
        V,
        PovX,
        PovY
    };

    static bool isConnected(unsigned int) { return false; }
    static unsigned int getButtonCount(unsigned int) { return 0; }
    static bool hasAxis(unsigned int, Axis) { return false; }
    static bool isButtonPressed(unsigned int, unsigned int) { return false; }
    static float getAxisPosition(unsigned int, Axis) { return 0.f; }
    static void update() {}
};

}  // namespace sf
