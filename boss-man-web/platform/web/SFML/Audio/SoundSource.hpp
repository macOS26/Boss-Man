#pragma once
#include "../System.hpp"

namespace sf {

// MARK: - SoundSource
// Base for Sound/Music. Provides the Status enum and volume/pitch/loop state. The
// web backend tracks volume as 0..100 (SFML units) and converts to 0..1 for the
// ABI when (re)playing.
class SoundSource {
public:
    enum Status {
        Stopped,
        Paused,
        Playing
    };

    void setVolume(float volume) { m_volume = volume; }
    void setPitch(float pitch) { m_pitch = pitch; }
    float getVolume() const { return m_volume; }
    float getPitch() const { return m_pitch; }

protected:
    SoundSource() = default;
    ~SoundSource() = default;

    float m_volume{100.f};
    float m_pitch{1.f};
};

}  // namespace sf
