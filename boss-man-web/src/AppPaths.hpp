#pragma once
#include <string>

namespace bm {

// Web build: there is no writable filesystem. Save data lives in localStorage
// (see WebStore.hpp); the "path" is just the storage key (the former filename).

inline std::string userDataDir() { return ""; }

inline std::string appSupportPath(const std::string& filename) { return filename; }

} // namespace bm
