#pragma once
#include <SFML/Window/Event.hpp>
#include "MoveDirection.hpp"

namespace bm {

class InputController {
public:
    MoveDirection lastDirection = MoveDirection::None;
    bool fireRequested = false;
    bool pauseRequested = false;
    bool escapeRequested = false;
    bool pRequested = false;
    bool eRequested = false;
    bool fullscreenToggleRequested = false;

    void handleEvent(const sf::Event& event) {
        if (event.type == sf::Event::KeyPressed) {
            switch (event.key.code) {
            case sf::Keyboard::Left:  case sf::Keyboard::A:
                lastDirection = MoveDirection::Left; break;
            case sf::Keyboard::Right: case sf::Keyboard::D:
                lastDirection = MoveDirection::Right; break;
            case sf::Keyboard::Down:  case sf::Keyboard::S:
                lastDirection = MoveDirection::Down; break;
            case sf::Keyboard::Up:    case sf::Keyboard::W:
                lastDirection = MoveDirection::Up; break;
            case sf::Keyboard::Space:
                fireRequested = true; break;
            case sf::Keyboard::P:
                pRequested = true; break;
            case sf::Keyboard::E:
                eRequested = true; break;
            case sf::Keyboard::F:
                fullscreenToggleRequested = true; break;
            case sf::Keyboard::Escape:
                escapeRequested = true; break;
            default: break;
            }
        } else if (event.type == sf::Event::KeyReleased) {
            switch (event.key.code) {
            case sf::Keyboard::Left:  case sf::Keyboard::A:
                if (lastDirection == MoveDirection::Left) lastDirection = MoveDirection::None; break;
            case sf::Keyboard::Right: case sf::Keyboard::D:
                if (lastDirection == MoveDirection::Right) lastDirection = MoveDirection::None; break;
            case sf::Keyboard::Down:  case sf::Keyboard::S:
                if (lastDirection == MoveDirection::Down) lastDirection = MoveDirection::None; break;
            case sf::Keyboard::Up:    case sf::Keyboard::W:
                if (lastDirection == MoveDirection::Up) lastDirection = MoveDirection::None; break;
            default: break;
            }
        } else if (event.type == sf::Event::JoystickMoved) {
            float x = sf::Joystick::getAxisPosition(event.joystickMove.joystickId, sf::Joystick::X);
            float y = sf::Joystick::getAxisPosition(event.joystickMove.joystickId, sf::Joystick::Y);
            float deadzone = 25.0f;
            if (std::abs(x) > std::abs(y)) {
                if (x > deadzone) lastDirection = MoveDirection::Right;
                else if (x < -deadzone) lastDirection = MoveDirection::Left;
            } else {
                if (y > deadzone) lastDirection = MoveDirection::Down;
                else if (y < -deadzone) lastDirection = MoveDirection::Up;
            }
        } else if (event.type == sf::Event::JoystickButtonPressed) {
            switch (event.joystickButton.button) {
            case 0: fireRequested = true; break;   // A/Cross
            case 1: pRequested = true; break;      // B/Circle
            case 6: case 7: escapeRequested = true; break; // Back/Start
            }
        }
    }

    // Mouse / trackpad swipe steering: accumulate motion between MouseMoved
    // events and, once it clears a threshold, steer Pete that way (mirrors the
    // apple InputController.handleMouseDelta and the wasm swipe). Pixel deltas
    // are fine for direction; called only in the Playing state.
    int lastMouseX = -1, lastMouseY = -1;
    float mouseAccumX = 0.f, mouseAccumY = 0.f;

    void handleMouseMove(int x, int y) {
        if (lastMouseX < 0) { lastMouseX = x; lastMouseY = y; return; }
        float dx = float(x - lastMouseX), dy = float(y - lastMouseY);
        lastMouseX = x; lastMouseY = y;
        if (dx * dx + dy * dy > 100.f * 100.f) { mouseAccumX = 0; mouseAccumY = 0; return; } // ignore warps
        mouseAccumX += dx; mouseAccumY += dy;
        float ax = mouseAccumX < 0 ? -mouseAccumX : mouseAccumX;
        float ay = mouseAccumY < 0 ? -mouseAccumY : mouseAccumY;
        const float threshold = 24.f;
        if (ax < threshold && ay < threshold) return;
        if (ax > ay) lastDirection = (mouseAccumX > 0) ? MoveDirection::Right : MoveDirection::Left;
        else         lastDirection = (mouseAccumY > 0) ? MoveDirection::Down  : MoveDirection::Up;
        mouseAccumX = 0; mouseAccumY = 0;
    }

    void consume() {
        fireRequested = false;
        pauseRequested = false;
        escapeRequested = false;
        pRequested = false;
        eRequested = false;
        fullscreenToggleRequested = false;
    }
};

} // namespace bm