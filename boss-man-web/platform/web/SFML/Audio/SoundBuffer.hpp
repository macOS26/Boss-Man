#pragma once
#include "../System.hpp"
#include "../../abi.h"
#include "../Graphics/Image.hpp"
#include <vector>

namespace sf {

// MARK: - SoundBuffer
// Holds PCM samples in C++ (so getSamples/getSampleCount/peak-normalize work) and,
// lazily, a JS WebAudio buffer handle minted from those samples. loadFromSamples
// takes a total sample count (frames * channels) exactly like SFML; the ABI's
// snd_from_samples wants frames, so we divide out the channel count. loadFromFile
// resolves a preloaded clip by basename; loadFromMemory can't decode, returns false.
class SoundBuffer {
public:
    SoundBuffer() = default;

    bool loadFromFile(const std::string& path) {
        std::string key = detail::assetKey(path);
        m_handle = snd_by_name(key.c_str(), (int)key.size());
        m_samples.clear();
        m_channels = 1;
        m_sampleRate = 44100;
        return m_handle != 0;
    }

    bool loadFromMemory(const void*, std::size_t) { return false; }

    bool loadFromSamples(const Int16* samples, Uint64 sampleCount,
                         unsigned int channelCount, unsigned int sampleRate) {
        m_samples.assign(samples, samples + sampleCount);
        m_channels = channelCount ? channelCount : 1;
        m_sampleRate = sampleRate ? sampleRate : 44100;
        m_handle = 0;
        return true;
    }

    const Int16* getSamples() const { return m_samples.empty() ? nullptr : m_samples.data(); }
    Uint64 getSampleCount() const { return m_samples.size(); }
    unsigned int getChannelCount() const { return m_channels; }
    unsigned int getSampleRate() const { return m_sampleRate; }

    Time getDuration() const {
        if (m_sampleRate == 0 || m_channels == 0) return Time::Zero;
        Uint64 frames = m_samples.size() / m_channels;
        return seconds((float)frames / (float)m_sampleRate);
    }

    // MARK: - backend
    // Lazily uploads CPU samples to a WebAudio buffer the first time a Sound needs
    // it. Name-loaded buffers already carry a handle.
    int handle() const {
        if (m_handle == 0 && !m_samples.empty()) {
            int frames = (int)(m_samples.size() / m_channels);
            m_handle = snd_from_samples(m_samples.data(), frames, (int)m_channels, (int)m_sampleRate);
        }
        return m_handle;
    }

private:
    std::vector<Int16> m_samples;
    unsigned int       m_channels{1};
    unsigned int       m_sampleRate{44100};
    mutable int        m_handle{0};
};

}  // namespace sf
