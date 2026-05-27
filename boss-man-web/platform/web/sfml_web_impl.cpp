// Out-of-line definitions for the web (wasm) sf:: layer. Compiled into the wasm
// build alongside the game. Holds the static members the headers declare extern.
#include "SFML/Graphics.hpp"
#include "SFML/Audio.hpp"

namespace sf {

// MARK: - System
const Time Time::Zero = Time();

// MARK: - Graphics
const Color Color::Black(0, 0, 0);
const Color Color::White(255, 255, 255);
const Color Color::Red(255, 0, 0);
const Color Color::Green(0, 255, 0);
const Color Color::Blue(0, 0, 255);
const Color Color::Yellow(255, 255, 0);
const Color Color::Magenta(255, 0, 255);
const Color Color::Cyan(0, 255, 255);
const Color Color::Transparent(0, 0, 0, 0);

const Transform Transform::Identity = Transform();

const RenderStates RenderStates::Default = RenderStates();

const BlendMode BlendAlpha(BlendMode::SrcAlpha, BlendMode::OneMinusSrcAlpha, BlendMode::Add,
                           BlendMode::One, BlendMode::OneMinusSrcAlpha, BlendMode::Add);
const BlendMode BlendAdd(BlendMode::SrcAlpha, BlendMode::One, BlendMode::Add,
                         BlendMode::One, BlendMode::One, BlendMode::Add);
const BlendMode BlendMultiply(BlendMode::DstColor, BlendMode::Zero);
const BlendMode BlendNone(BlendMode::One, BlendMode::Zero);

}  // namespace sf
