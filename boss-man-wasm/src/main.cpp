#include <cstdlib>
#include "Game.hpp"

int main() {
#ifdef _WIN32
    _putenv_s("ALSOFT_LOGLEVEL", "0");
#elif !defined(IS_ENGINE_HTML_5)
    setenv("ALSOFT_LOGLEVEL", "0", 1);
#endif
    // NOTE: the web fork loads assets from files relative to the working dir
    // (the build dir on desktop; "/" with Emscripten's preloaded /assets on web),
    // so we must NOT chdir away from it (the native build's Application-Support
    // chdir would break the relative asset paths).
    bm::Game game;
    game.run();
    return 0;
}
