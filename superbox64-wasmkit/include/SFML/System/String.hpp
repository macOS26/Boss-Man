#pragma once
#include "../System.hpp"
#include <string>

namespace sf {

// MARK: - String
// SFML's Unicode string. The game only needs to round-trip UTF-8 bytes into
// sf::Text (which draws via Canvas2D fillText), so we store the UTF-8 bytes
// verbatim. fromUtf8 copies the byte range as-is; conversion to std::string
// hands the same bytes back.
class String {
public:
    String() = default;
    String(const char* utf8) : m_utf8(utf8 ? utf8 : "") {}
    String(const std::string& utf8) : m_utf8(utf8) {}

    template <typename InputIt>
    static String fromUtf8(InputIt begin, InputIt end) {
        String s;
        s.m_utf8.assign(begin, end);
        return s;
    }

    const std::string& toAnsiString() const { return m_utf8; }
    std::string toUtf8() const { return m_utf8; }
    operator std::string() const { return m_utf8; }

    bool isEmpty() const { return m_utf8.empty(); }
    std::size_t getSize() const { return m_utf8.size(); }
    const std::string& bytes() const { return m_utf8; }

private:
    std::string m_utf8;
};

}  // namespace sf
