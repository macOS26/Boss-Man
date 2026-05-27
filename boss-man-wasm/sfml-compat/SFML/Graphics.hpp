#pragma once
// is-Engine SDL2 wrapper provides the sf:: API on web (IS_ENGINE_SDL_2).
#include "isEngineSDLWrapper.h"

// The wrapper has RenderWindow/RenderTexture but no abstract RenderTarget base
// that the game's renderers take by reference. Everything is drawn to the window,
// so alias it.
namespace sf { using RenderTarget = RenderWindow; }
