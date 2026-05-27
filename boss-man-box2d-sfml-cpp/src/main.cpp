#include <cstdlib>
#include <filesystem>
#include "AppPaths.hpp"
#include "Game.hpp"

int main() {
#ifdef _WIN32
    _putenv_s("ALSOFT_LOGLEVEL", "0");
#else
    setenv("ALSOFT_LOGLEVEL", "0", 1);
#endif
    // Run from the per-user data dir (Application Support). The .app may live under
    // ~/Documents, and any relative file access — OpenAL probing ./alsoft.ini, or a
    // stray save — would otherwise hit the Documents folder and trigger a macOS
    // privacy prompt. Keep all of it in Application Support instead.
    std::error_code ec;
    std::filesystem::current_path(bm::userDataDir(), ec);

    bm::Game game;
    game.run();
    return 0;
}