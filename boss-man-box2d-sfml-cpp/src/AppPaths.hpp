#pragma once
#include <string>

#if defined(BOSS_MAN_WEB)

namespace bm {
// Web build: there is no writable filesystem. Save data lives in localStorage
// (see WebStore.hpp); the "path" is just the storage key (the former filename).
inline std::string userDataDir() { return ""; }
inline std::string appSupportPath(const std::string& filename) { return filename; }
} // namespace bm

#else

#include <cstdlib>
#include <filesystem>

namespace bm {

// Per-user writable data directory, created on first use. The single source of
// truth for save files (high score, leaderboard, edited levels) so a Finder-
// launched .app (CWD = "/") still persists them.
//   macOS:   ~/Library/Application Support/Boss-Man
//   Windows: %APPDATA%\Boss-Man
//   Linux:   $XDG_DATA_HOME/Boss-Man  (or ~/.local/share/Boss-Man)
inline std::string userDataDir() {
#if defined(_WIN32)
    const char* base = std::getenv("APPDATA");
    std::filesystem::path dir = base ? std::filesystem::path(base) : std::filesystem::path(".");
    dir /= "Boss-Man";
#elif defined(__APPLE__)
    const char* home = std::getenv("HOME");
    std::filesystem::path dir = home ? std::filesystem::path(home) : std::filesystem::path(".");
    dir /= "Library/Application Support/Boss-Man";
#else
    const char* xdg = std::getenv("XDG_DATA_HOME");
    const char* home = std::getenv("HOME");
    std::filesystem::path dir = xdg ? std::filesystem::path(xdg)
                              : (home ? std::filesystem::path(home) / ".local/share"
                                      : std::filesystem::path("."));
    dir /= "Boss-Man";
#endif
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    return dir.string();
}

inline std::string appSupportPath(const std::string& filename) {
    return (std::filesystem::path(userDataDir()) / filename).string();
}

} // namespace bm

#endif
