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