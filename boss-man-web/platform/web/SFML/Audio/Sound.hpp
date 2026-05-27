#pragma once
#include "../System.hpp"
#include "../../abi.h"
#include "SoundSource.hpp"
#include "SoundBuffer.hpp"

namespace sf {

// MARK: - Sound
// A playing instance of a SoundBuffer. play() starts a WebAudio voice (snd_play)
// and remembers its handle so stop/volume/status target that voice. setVolume on a
// live voice is applied immediately; otherwise it takes effect on the next play.
class Sound : public SoundSource {
public:
    Sound() = default;
    explicit Sound(const SoundBuffer& buffer) : m_buffer(&buffer) {}

    void setBuffer(const SoundBuffer& buffer) { m_buffer = &buffer; }
    const SoundBuffer* getBuffer() const { return m_buffer; }

    void setLoop(bool loop) { m_loop = loop; }
    bool getLoop() const { return m_loop; }

    void play() {
        if (!m_buffer) return;
        int buf = m_buffer->handle();
        if (buf == 0) return;
        m_voice = snd_play(buf, m_volume / 100.f, m_loop ? 1 : 0);
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
    const SoundBuffer* m_buffer{nullptr};
    bool               m_loop{false};
    int                m_voice{0};
};

}  // namespace sf
