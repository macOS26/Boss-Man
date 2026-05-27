#include <cstdlib>
#include "Game.hpp"

int main() {
    setenv("ALSOFT_LOGLEVEL", "0", 1);
    bm::Game game;
    game.run();
    return 0;
}