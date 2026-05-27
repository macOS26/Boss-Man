#pragma once
#include "../System.hpp"
#include "../../abi.h"
#include "SoundSource.hpp"
#include "../Graphics/Image.hpp"

namespace sf {

// MARK: - Music
// Streamed audio in SFML; on web there is no streaming distinction, so Music is a
// thin wrapper over a name-resolved WebAudio buffer played as a (looping) voice.
// openFromFile resolves by basename; openFromMemory can't decode, returns false.
class Music : public SoundSource {
public:
    Music() = default;

    bool openFromFile(const std::string& path) {
        std::string key = detail::assetKey(path);
        m_buffer = snd_by_name(key.c_str(), (int)key.size());
        return m_buffer != 0;
    }
    bool openFromMemory(const void*, std::size_t) { return false; }

    void setLoop(bool loop) { m_loop = loop; }
    bool getLoop() const { return m_loop; }

    void play() {
        if (m_buffer == 0) return;
        m_voice = snd_play(m_buffer, m_volume / 100.f, m_loop ? 1 : 0);
    }
    void stop() {
        if (m_voice != 0) snd_stop(m_voice);
        m_voice = 0;
    }
    void pause() {
        if (m_voice != 0) snd_stop(m_voice);
        m_voice = 0;
    }
    void setVolume(float volume) {
        m_volume = volume;
        if (m_voice != 0) snd_set_volume(m_voice, m_volume / 100.f);
    }

    Status getStatus() const {
        if (m_voice == 0) return Stopped;
        int s = snd_status(m_voice);
        return s == 1 ? Playing : (s == 2 ? Paused : Stopped);
    }

private:
    int  m_buffer{0};
    int  m_voice{0};
    bool m_loop{false};
};

}  // namespace sf
