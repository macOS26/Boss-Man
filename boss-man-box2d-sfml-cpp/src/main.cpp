// Entry point. Native (Win/Mac/Linux): a blocking main() run loop from a real
// data dir. Web (wasm): runtime.js calls boot() once after assets preload, then
// frame(dtMs) each requestAnimationFrame (no blocking loop in a browser).
#include "Game.hpp"

#if defined(BOSS_MAN_WEB)
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

#else
#include <cstdlib>
#include <filesystem>
#include "AppPaths.hpp"

int main() {
#ifdef _WIN32
    _putenv_s("ALSOFT_LOGLEVEL", "0");
#else
    setenv("ALSOFT_LOGLEVEL", "0", 1);
#endif
    // Run from the per-user data dir (Application Support). The .app may live under
    // ~/Documents, and any relative file access would otherwise hit Documents and
    // trigger a macOS privacy prompt. Keep all of it in Application Support instead.
    std::error_code ec;
    std::filesystem::current_path(bm::userDataDir(), ec);

    bm::Game game;
    game.run();
    return 0;
}
#endif
