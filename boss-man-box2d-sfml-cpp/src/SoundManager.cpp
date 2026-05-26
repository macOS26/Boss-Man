#include "SoundManager.hpp"
#include "Constants.hpp"
#include <algorithm>

namespace bm {

SoundManager::SoundManager() {}

sf::SoundBuffer SoundManager::tone(float freq, float dur, float vol, float decay) {
    int frames = (int)(sampleRate * dur);
    std::vector<int16_t> samples(frames);
    float attack = 0.004f;
    for (int i = 0; i < frames; ++i) {
        float t = (float)i / sampleRate;
        float env;
        if (t < attack) env = t / attack;
        else env = expf(-decay * (t - attack));
        samples[i] = (int16_t)(sinf(2 * M_PI * freq * t) * vol * env * 32767);
    }
    sf::SoundBuffer buf;
    buf.loadFromSamples(samples.data(), frames, 1, sampleRate);
    return buf;
}

sf::SoundBuffer SoundManager::sweep(float from, float to, float dur, float vol) {
    int frames = (int)(sampleRate * dur);
    std::vector<int16_t> samples(frames);
    float phase = 0;
    float dt = 1.0f / sampleRate;
    for (int i = 0; i < frames; ++i) {
        float progress = (float)i / frames;
        float freq = from * powf(to / from, progress);
        phase += 2 * M_PI * freq * dt;
        float env = sinf(M_PI * progress);
        float t = i * dt;
        float release = (dur - t < 0.04f) ? std::max(0.0f, (dur - t) / 0.04f) : 1.0f;
        samples[i] = (int16_t)(sinf(phase) * vol * env * release * 32767);
    }
    sf::SoundBuffer buf;
    buf.loadFromSamples(samples.data(), frames, 1, sampleRate);
    return buf;
}

sf::SoundBuffer SoundManager::sequence(const std::vector<float>& notes, float perNote, float vol) {
    int totalFrames = (int)(sampleRate * perNote * notes.size());
    std::vector<int16_t> samples(totalFrames, 0);
    int perFrames = (int)(sampleRate * perNote);
    for (size_t idx = 0; idx < notes.size(); ++idx) {
        float freq = notes[idx];
        int start = (int)(idx * perFrames);
        for (int j = 0; j < perFrames && start + j < totalFrames; ++j) {
            float t = (float)j / sampleRate;
            float env = expf(-8 * t) * (t < 0.003f ? t / 0.003f : 1.0f);
            samples[start + j] = (int16_t)(sinf(2 * M_PI * freq * t) * vol * env * 32767);
        }
    }
    sf::SoundBuffer buf;
    buf.loadFromSamples(samples.data(), totalFrames, 1, sampleRate);
    return buf;
}

sf::SoundBuffer SoundManager::makeNoise(float dur, int bursts, float vol) {
    int frames = (int)(sampleRate * dur);
    std::vector<int16_t> samples(frames, 0);
    std::uniform_real_distribution<float> dist(-1.0f, 1.0f);
    if (bursts <= 1) {
        for (int i = 0; i < frames; ++i)
            samples[i] = (int16_t)(dist(rng) * vol * 32767);
    } else {
        for (int b = 0; b < bursts; ++b) {
            int startFrame = rng() % std::max(1, frames - 1024);
            int len = sampleRate * 0.01f + rng() % (int)(sampleRate * 0.03f);
            for (int j = 0; j < len && startFrame + j < frames; ++j) {
                float t = (float)j / len;
                samples[startFrame + j] += (int16_t)(dist(rng) * sinf(M_PI * t) * vol * 32767);
            }
        }
    }
    sf::SoundBuffer buf;
    buf.loadFromSamples(samples.data(), frames, 1, sampleRate);
    return buf;
}

const sf::SoundBuffer& SoundManager::cached(const std::string& key, std::function<sf::SoundBuffer()> build) {
    auto it = cache.find(key);
    if (it != cache.end()) return it->second;
    cache[key] = build();
    return cache[key];
}

void SoundManager::playBuffer(const sf::SoundBuffer& buf) {
    // Find a stopped sound or add a new one
    for (auto& s : sounds) {
        if (s.getStatus() != sf::Sound::Playing) {
            s.setBuffer(buf);
            s.play();
            return;
        }
    }
    sounds.emplace_back(buf);
    sounds.back().play();
    if (sounds.size() > 16) sounds.erase(sounds.begin(), sounds.begin() + 8);
}

void SoundManager::playDotBlip() {
    float now = dotClock.getElapsedTime().asSeconds();
    if (now - lastDotEatTime > 1.5f) dotsEatenInCycle = 0;
    lastDotEatTime = now;
    dotToggle = !dotToggle;
    int dotsPerStage[] = {4, 2, 4, 2};
    int cycleLen = 12;
    int pos = dotsEatenInCycle % cycleLen;
    int stage = 0, threshold = 0;
    for (int i = 0; i < 4; ++i) {
        threshold += dotsPerStage[i];
        if (pos < threshold) { stage = i; break; }
    }
    float dotStages[][2] = {{988,1175},{1397,1175},{1397,1760},{784,988}};
    float freq = dotToggle ? dotStages[stage][0] : dotStages[stage][1];
    std::string key = "dot-" + std::to_string(stage) + (dotToggle ? "hi" : "lo");
    playBuffer(cached(key, [=]() { return tone(freq, 0.05f, 0.22f); }));
    dotsEatenInCycle++;
}

void SoundManager::playGoldDisc() {
    playBuffer(cached("goldDisc", [=]() { return sweep(220, 660, 0.45f, 0.35f); }));
}

void SoundManager::playFootstep() {
    playBuffer(cached("footstep", [=]() { return tone(140, 0.025f, 0.07f, 60.0f); }));
}

void SoundManager::playCaptureBoss(int streak) {
    float base = 440;
    std::vector<float> arp = {base, base*1.5f, base*2, base*3};
    int count = std::max(2, std::min(4, streak + 1));
    std::vector<float> notes(arp.begin(), arp.begin() + count);
    playBuffer(cached("capture" + std::to_string(count), [=]() { return sequence(notes, 0.08f, 0.35f); }));
}

void SoundManager::playCaughtByBoss() {
    playBuffer(cached("caughtByBoss", [=]() { return sweep(330, 60, 0.7f, 0.4f); }));
}

void SoundManager::playFishOrTreat() {
    playBuffer(cached("fishOrTreat", [=]() { return sequence({1320, 1760, 2093}, 0.08f, 0.3f); }));
}

void SoundManager::playTpsDeliver() {
    playBuffer(cached("tpsDeliver", [=]() { return sequence({660, 880, 1320}, 0.12f, 0.35f); }));
}

void SoundManager::playGameOver() {
    playBuffer(cached("gameOver", [=]() { return sequence({392, 311, 261, 196}, 0.18f, 0.4f); }));
}

void SoundManager::playLevelStart() {
    playBuffer(cached("levelStart", [=]() { return sequence({523, 659, 784, 1046}, 0.12f, 0.3f); }));
}

void SoundManager::playTeleport() {
    playBuffer(cached("teleport", [=]() { return sweep(220, 1400, 1.0f, 0.2f); }));
}

void SoundManager::playWaterGunPickup() {
    playBuffer(cached("waterGunPickup", [=]() { return sweep(440, 1320, 0.3f, 0.3f); }));
}

void SoundManager::playWaterGunShoot() {
    playBuffer(cached("waterGunShoot", [=]() { return sweep(880, 440, 0.08f, 0.25f); }));
}

void SoundManager::playWaterGunSplash() {
    playBuffer(cached("waterGunSplash", [=]() { return sweep(660, 220, 0.3f, 0.35f); }));
}

void SoundManager::playMachine(const std::string& name) {
    if (name == Machine::PRINTER) playBuffer(cached("printer", [=]() { return sequence({540, 820, 540, 820}, 0.06f, 0.16f); }));
    else if (name == Machine::FAX) playBuffer(cached("fax", [=]() { return sequence({1100, 2100, 1500, 2400}, 0.12f, 0.22f); }));
    else if (name == Machine::COVER_SHEET) playBuffer(cached("pageFlip", [=]() { return makeNoise(0.55f, 50, 0.18f); }));
    else if (name == Machine::BOOK_BINDER) playBuffer(cached("collator", [=]() { return makeNoise(0.3f, 4, 0.32f); }));
    else playDotBlip();
}

void SoundManager::startBackgroundMusic(bool mib) {
    if (musicEnabled && isMIB == mib) return;
    musicEnabled = true;
    isMIB = mib;
    // Pre-generate a simple music loop
    std::vector<float> bassNotes;
    if (!mib) {
        float notes[] = {130.81f,164.81f,130.81f,196.0f,174.61f,220.0f,174.61f,261.63f,
                        155.56f,196.0f,155.56f,233.08f,174.61f,220.0f,130.81f,164.81f};
        for (auto n : notes) bassNotes.push_back(n);
    } else {
        float notes[] = {65.41f,0,65.41f,0,98.0f,0,65.41f,0,
                        77.78f,0,77.78f,0,98.0f,0,77.78f,0};
        for (auto n : notes) bassNotes.push_back(n);
    }
    float beat = mib ? 0.15f : 0.278f;
    musicBuffer = sequence(bassNotes, beat, mib ? 0.14f : 0.12f);
    musicSound.setBuffer(musicBuffer);
    musicSound.setLoop(true);
    musicSound.play();
}

void SoundManager::stopBackgroundMusic() {
    musicEnabled = false;
    musicSound.stop();
}

void SoundManager::startGoldDiscBass(bool mib) {
    std::vector<float> notes;
    if (!mib) {
        float n[] = {82.41f,82.41f,0,164.81f,82.41f,0,98.0f,98.0f,
                     82.41f,0,110.0f,110.0f,98.0f,0,123.47f,164.81f};
        for (auto f : n) notes.push_back(f);
    } else {
        float n[] = {65.41f,0,65.41f,0,98.0f,0,65.41f,0};
        for (auto f : n) notes.push_back(f);
    }
    bassBuffer = sequence(notes, 0.125f, 0.34f);
    bassSound.setBuffer(bassBuffer);
    bassSound.setLoop(true);
    bassSound.play();
    bassEnabled = true;
}

void SoundManager::stopGoldDiscBass() { bassSound.stop(); bassEnabled = false; }
void SoundManager::pauseAudio() {
    musicSound.pause();
    bassSound.pause();
    for (auto& s : sounds) s.pause();
}
void SoundManager::resumeAudio() {
    if (musicEnabled) musicSound.play();
    if (bassEnabled) bassSound.play();
}

} // namespace bm