#include <cstdlib>
#include "Game.hpp"

int main() {
#ifdef _WIN32
    _putenv_s("ALSOFT_LOGLEVEL", "0");
#else
    setenv("ALSOFT_LOGLEVEL", "0", 1);
#endif
    bm::Game game;
    game.run();
    return 0;
}