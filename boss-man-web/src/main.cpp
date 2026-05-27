// Web entry point. There is no blocking main loop in the browser: runtime.js
// calls boot() once (after assets are preloaded), then frame(dtMs) every
// requestAnimationFrame. boot()/frame() are the wasm exports the runtime drives.
#include "Game.hpp"
#include <SFML/System.hpp>
#include <cstdint>
#include <memory>

#define WASM_EXPORT(name) __attribute__((export_name(name)))

namespace { std::unique_ptr<bm::Game> g_game; }

extern "C" WASM_EXPORT("boot") void boot() {
    g_game = std::make_unique<bm::Game>();
}

extern "C" WASM_EXPORT("frame") void frame(double dtMs) {
    if (dtMs > 100.0) dtMs = 100.0; // avoid update spiral after a backgrounded tab
    sf::detail::nowUs() += static_cast<int64_t>(dtMs * 1000.0);
    if (g_game) g_game->tick();
}
