#include "SoundManager.hpp"
#include "Constants.hpp"
#include "Assets.hpp"
#include <algorithm>

namespace bm {

namespace {
// `say`/afconvert clips aren't normalized, so they play quiet. Peak-normalize each
// voice buffer up toward full scale (capped) so the boss lines are loud and even.
void peakNormalize(sf::SoundBuffer& buf, float targetPeak, float maxGain) {
    const sf::Int16* src = buf.getSamples();
    std::size_t n = buf.getSampleCount();
    if (n == 0) return;
    int peak = 1;
    for (std::size_t i = 0; i < n; ++i) {
        int a = std::abs((int)src[i]);
        if (a > peak) peak = a;
    }
    float gain = (targetPeak * 32767.0f) / (float)peak;
    if (gain > maxGain) gain = maxGain;
    if (gain <= 1.001f) return; // already loud enough
    std::vector<sf::Int16> out(n);
    for (std::size_t i = 0; i < n; ++i) {
        float v = src[i] * gain;
        if (v > 32767.0f) v = 32767.0f;
        else if (v < -32768.0f) v = -32768.0f;
        out[i] = (sf::Int16)v;
    }
    buf.loadFromSamples(out.data(), n, buf.getChannelCount(), buf.getSampleRate());
}
} // namespace

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

void SoundManager::playVoice(const std::string& key) {
    auto it = voiceCache.find(key);
    if (it == voiceCache.end()) {
        sf::SoundBuffer buf;
        if (!loadSoundBuffer(buf, "assets/voice/" + key + ".wav"))
            return; // clip not generated yet — stay silent rather than error
        peakNormalize(buf, 0.95f, 6.0f);
        it = voiceCache.emplace(key, std::move(buf)).first;
    }
    // Voice gets its own channel so the boss is never cut off by SFX recycling
    // (footsteps/dots) in the shared pool. Re-triggering the same line while it
    // is still playing is ignored, so a brown-box contact firing 1-3 times as
    // Pete crosses it can't restart and stutter the clip. A *different* line
    // interrupts (one voice at a time, like the SpriteKit synthesizer).
    if (voiceSound.getStatus() == sf::Sound::Playing && key == lastVoiceKey)
        return;
    voiceSound.stop();
    voiceSound.setBuffer(it->second);
    voiceSound.setVolume(100.f);
    voiceSound.play();
    lastVoiceKey = key;
    applyDuck(true); // duck SFX/music immediately so the line is never buried
}

int SoundManager::voicePoolCount(const std::string& prefix) {
    auto it = voicePoolCounts.find(prefix);
    if (it != voicePoolCounts.end()) return it->second;
    int n = 0;
    while (true) {
        if (!assetExists("assets/voice/" + prefix + "_" + std::to_string(n + 1) + ".wav")) break;
        ++n;
    }
    voicePoolCounts[prefix] = n;
    return n;
}

void SoundManager::playVoiceRandom(const std::string& prefix) {
    int n = voicePoolCount(prefix);
    if (n <= 0) return; // pool not generated — stay silent
    std::uniform_int_distribution<int> dist(1, n);
    playVoice(prefix + "_" + std::to_string(dist(rng)));
}

void SoundManager::applyDuck(bool ducked) {
    voiceDucked = ducked;
    float sfx = ducked ? 15.0f : 60.0f; // SFX trimmed (too loud on mobile); SpriteKit normal 0.6 / ducked 0.15
    for (auto& s : sounds) s.setVolume(sfx);
    if (musicEnabled) musicSound.setVolume(ducked ? 18.0f : 100.0f); // 0.18
    // Bass is intentionally not ducked, matching SpriteKit's setDucked.
}

void SoundManager::updateDucking() {
    bool playing = (voiceSound.getStatus() == sf::Sound::Playing);
    if (playing != voiceDucked) applyDuck(playing);
}

void SoundManager::playBuffer(const sf::SoundBuffer& buf) {
    float vol = voiceDucked ? 15.0f : 60.0f;
    // Find a stopped sound or add a new one
    for (auto& s : sounds) {
        if (s.getStatus() != sf::Sound::Playing) {
            s.setBuffer(buf);
            s.setVolume(vol);
            s.play();
            return;
        }
    }
    sounds.emplace_back(buf);
    sounds.back().setVolume(vol);
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
    // An octave below the originals: the high pure sines read as a tinny ting on
    // phone speakers; warmer C4-A5 range, same waka pattern.
    static const float dotStages[4][2]    = {{494.00f,587.33f},{698.46f,587.33f},{698.46f,880.00f},{392.00f,493.88f}};
    // MIB dots an octave below the originals (C5-C6 read as a tinny ting against
    // the dark 12/24 theme); same C-minor pattern, just warmer.
    static const float mibDotStages[4][2] = {{261.63f,311.13f},{311.13f,392.00f},{392.00f,523.25f},{466.16f,392.00f}};
    const float (*pair)[2] = isMIB ? mibDotStages : dotStages;
    float freq = dotToggle ? pair[stage][0] : pair[stage][1];
    float vol = isMIB ? 0.11f : 0.22f; // MIB dot blips are quieter, like SpriteKit
    std::string key = "dot-" + std::to_string(stage) + (dotToggle ? "hi" : "lo") + (isMIB ? "m" : "");
    playBuffer(cached(key, [=]() { return tone(freq, 0.05f, vol); }));
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
    playVoiceRandom("capture"); // boss reacts to being captured
}

void SoundManager::playCaughtByBoss() {
    playBuffer(cached("caughtByBoss", [=]() { return sweep(330, 60, 0.7f, 0.4f); }));
    playVoiceRandom("caught"); // boss taunts the worker it just caught
}

void SoundManager::playFishOrTreat() {
    playBuffer(cached("fishOrTreat", [=]() { return sequence({1320, 1760, 2093}, 0.08f, 0.3f); }));
    playVoiceRandom("fish");
}

void SoundManager::playTpsDeliver() {
    playBuffer(cached("tpsDeliver", [=]() { return sequence({660, 880, 1320}, 0.12f, 0.35f); }));
    playVoiceRandom("tps_done");
}

void SoundManager::playGameOver() {
    playBuffer(cached("gameOver", [=]() { return sequence({392, 311, 261, 196}, 0.18f, 0.4f); }));
    playVoiceRandom("gameover");
}

void SoundManager::playLevelStart() {
    playBuffer(cached("levelStart", [=]() { return sequence({523, 659, 784, 1046}, 0.12f, 0.3f); }));
    playVoiceRandom("levelstart");
}

void SoundManager::playTeleport() {
    // Guard so multiple bosses spawning at once don't stack the 1.75s sweep.
    if (teleportPlayed && teleportClock.getElapsedTime().asSeconds() < 1.75f) return;
    teleportPlayed = true;
    teleportClock.restart();
    playBuffer(cached("teleport", [=]() { return buildTeleport(); }));
}

// Teleport: simultaneous ascending (220->1400) and descending (1400->220) sweeps
// plus a shimmer, under a sin envelope over 1.75s. Mirrors SpriteKit buildTeleport.
sf::SoundBuffer SoundManager::buildTeleport() {
    const float duration = 1.75f;
    int frames = (int)(sampleRate * duration);
    std::vector<int16_t> data(frames, 0);
    const float ascStart = 220, ascEnd = 1400, descStart = 1400, descEnd = 220;
    float phaseAsc = 0, phaseDesc = 0;
    float dt = 1.0f / sampleRate;
    std::uniform_real_distribution<float> noiseDist(-1.0f, 1.0f);
    for (int i = 0; i < frames; ++i) {
        float t = (float)i / sampleRate;
        float progress = t / duration;
        float ascFreq = ascStart * powf(ascEnd / ascStart, progress);
        float descFreq = descStart * powf(descEnd / descStart, progress);
        phaseAsc += 2 * M_PI * ascFreq * dt;
        phaseDesc += 2 * M_PI * descFreq * dt;
        float env = sinf(M_PI * progress);
        float shimmer = noiseDist(rng) * 0.06f;
        float v = (sinf(phaseAsc) * 0.20f + sinf(phaseDesc) * 0.15f + shimmer) * env;
        data[i] = (int16_t)(std::clamp(v, -1.0f, 1.0f) * 32767);
    }
    sf::SoundBuffer buf;
    buf.loadFromSamples(data.data(), frames, 1, sampleRate);
    return buf;
}

// Band-passy noise texture used by the crunch / radio-static travelers.
// bursts<=1 fills with continuous noise; otherwise sin-enveloped random bursts.
// One-pole high-pass + 0.04s fades. Mirrors SpriteKit synthFiltered.
sf::SoundBuffer SoundManager::synthFiltered(float seconds, int bursts, float vol) {
    int frames = (int)(sampleRate * seconds);
    std::vector<float> data(frames, 0.0f);
    std::uniform_real_distribution<float> noiseDist(-1.0f, 1.0f);
    if (bursts <= 1) {
        for (int i = 0; i < frames; ++i) data[i] = noiseDist(rng);
    } else {
        std::uniform_int_distribution<int> startDist(0, std::max(1, frames - 1024));
        std::uniform_int_distribution<int> lenDist((int)(sampleRate * 0.01f), (int)(sampleRate * 0.04f));
        for (int b = 0; b < bursts; ++b) {
            int start = startDist(rng);
            int len = lenDist(rng);
            for (int j = 0; j < len && start + j < frames; ++j) {
                float t = (float)j / len;
                data[start + j] += noiseDist(rng) * sinf(M_PI * t);
            }
        }
    }
    float lp = 0.0f;
    for (int i = 0; i < frames; ++i) {
        lp = 0.78f * lp + 0.22f * data[i];
        data[i] = (data[i] - lp) * vol;
    }
    const float fade = 0.04f;
    std::vector<int16_t> out(frames);
    for (int i = 0; i < frames; ++i) {
        float t = (float)i / sampleRate;
        float env = 1.0f;
        if (t < fade) env = t / fade;
        else if (t > seconds - fade) env = std::max(0.0f, (seconds - t) / fade);
        out[i] = (int16_t)(std::clamp(data[i] * env, -1.0f, 1.0f) * 32767);
    }
    sf::SoundBuffer buf;
    buf.loadFromSamples(out.data(), frames, 1, sampleRate);
    return buf;
}

// One distinct sound per traveler type on arrival (idx matches TRAVELERS order).
void SoundManager::playTravelerArrive(int idx) {
    const std::string p = "travelerArrive_";
    switch (idx) {
    case 0:  playBuffer(cached(p + "water",       [=]() { return sweep(520, 180, 0.55f, 0.14f); })); break;
    case 1:  playBuffer(cached(p + "glaze",       [=]() { return sequence({2093, 2637, 3136}, 0.07f, 0.13f); })); break;
    case 2:  playBuffer(cached(p + "crunch",      [=]() { return synthFiltered(0.35f, 12, 0.18f); })); break;
    case 3:  playBuffer(cached(p + "alienBleep",  [=]() { return sequence({880, 1320, 1760, 1320}, 0.06f, 0.16f); })); break;
    case 4:  playBuffer(cached(p + "jelly",       [=]() { return sweep(660, 990, 0.7f, 0.12f); })); break;
    case 5:  playBuffer(cached(p + "crispTap",    [=]() { return tone(1568, 0.12f, 0.18f, 22.0f); })); break;
    case 6:  playBuffer(cached(p + "bellDing",    [=]() { return sequence({1568, 2093}, 0.22f, 0.16f); })); break;
    case 7:  playBuffer(cached(p + "radioStatic", [=]() { return synthFiltered(0.6f, 1, 0.10f); })); break;
    case 8:  playBuffer(cached(p + "magicChime",  [=]() { return sequence({1318, 1976, 2637, 3520}, 0.07f, 0.13f); })); break;
    case 9:  playBuffer(cached(p + "ufoWhoosh",   [=]() { return sweep(1760, 220, 0.65f, 0.13f); })); break;
    case 10: playBuffer(cached(p + "eyeDrone",    [=]() { return tone(196, 0.8f, 0.18f, 2.0f); })); break;
    case 11: playBuffer(cached(p + "bigEye",      [=]() { return sequence({659, 880, 1175, 1568}, 0.07f, 0.14f); })); break;
    default: break;
    }
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
    if (name == Machine::PRINTER) playBuffer(cached("printer", [=]() { return synthPrinter(); }));
    else if (name == Machine::FAX) playBuffer(cached("fax", [=]() { return synthFax(); }));
    else if (name == Machine::COVER_SHEET) playBuffer(cached("pageFlip", [=]() { return synthPageFlip(); }));
    else if (name == Machine::BOOK_BINDER) playBuffer(cached("collator", [=]() { return synthCollator(); }));
    else playDotBlip();
}

// Printer: 5 square-wave chirps (alternating 540/820 Hz) then a 0.18s noise+hum
// whir tail. Mirrors SpriteKit synthPrinter.
sf::SoundBuffer SoundManager::synthPrinter() {
    const int chirpCount = 5;
    const float chirpDur = 0.055f, gapDur = 0.028f;
    const float total = (chirpDur + gapDur) * chirpCount + 0.18f;
    int frames = (int)(sampleRate * total);
    std::vector<int16_t> data(frames, 0);
    int perFrames = (int)(sampleRate * chirpDur);
    int gapFrames = (int)(sampleRate * gapDur);
    for (int c = 0; c < chirpCount; ++c) {
        int start = c * (perFrames + gapFrames);
        float baseFreq = 540.0f + (c % 2) * 280.0f;
        for (int j = 0; j < perFrames && start + j < frames; ++j) {
            float t = (float)j / sampleRate;
            float sq = sinf(2 * M_PI * baseFreq * t) > 0 ? 1.0f : -1.0f;
            float env = sinf(M_PI * (float)j / perFrames);
            data[start + j] = (int16_t)(sq * env * 0.16f * 32767);
        }
    }
    int whirStart = chirpCount * (perFrames + gapFrames);
    int whirFrames = (int)(sampleRate * 0.18f);
    std::uniform_real_distribution<float> noiseDist(-1.0f, 1.0f);
    for (int j = 0; j < whirFrames && whirStart + j < frames; ++j) {
        float t = (float)j / sampleRate;
        float env = expf(-8 * t);
        float hum = sinf(2 * M_PI * 110 * t) * 0.06f + noiseDist(rng) * 0.04f;
        data[whirStart + j] = (int16_t)(hum * env * 32767);
    }
    sf::SoundBuffer buf;
    buf.loadFromSamples(data.data(), frames, 1, sampleRate);
    return buf;
}

// Fax: 4 tone segments (1100/2100/1500/2400 Hz) with a 14 Hz vibrato and per-
// segment fades/gaps. Mirrors SpriteKit synthFax.
sf::SoundBuffer SoundManager::synthFax() {
    struct Seg { float freq, dur, gapAfter; };
    const Seg segments[] = {
        {1100, 0.16f, 0.05f}, {2100, 0.18f, 0.05f},
        {1500, 0.14f, 0.04f}, {2400, 0.22f, 0.00f}
    };
    float total = 0;
    for (auto& s : segments) total += s.dur + s.gapAfter;
    int frames = (int)(sampleRate * total);
    std::vector<int16_t> data(frames, 0);
    int offset = 0;
    for (auto& seg : segments) {
        int segFrames = (int)(sampleRate * seg.dur);
        for (int j = 0; j < segFrames && offset + j < frames; ++j) {
            float t = (float)j / sampleRate;
            float fadeIn = 0.012f, fadeOut = 0.025f;
            float env;
            if (t < fadeIn) env = t / fadeIn;
            else if (t > seg.dur - fadeOut) env = std::max(0.0f, (seg.dur - t) / fadeOut);
            else env = 1.0f;
            float wobble = sinf(2 * M_PI * 14 * t) * 6.0f;
            data[offset + j] = (int16_t)(sinf(2 * M_PI * (seg.freq + wobble) * t) * 0.22f * env * 32767);
        }
        offset += segFrames + (int)(sampleRate * seg.gapAfter);
    }
    sf::SoundBuffer buf;
    buf.loadFromSamples(data.data(), frames, 1, sampleRate);
    return buf;
}

// Book binder: 4 low-pass-filtered noise bursts, sin-enveloped. The filter state
// carries across bursts. Mirrors SpriteKit synthCollator.
sf::SoundBuffer SoundManager::synthCollator() {
    const int bursts = 4;
    const float burstDur = 0.075f, gapDur = 0.05f;
    const float total = (burstDur + gapDur) * bursts;
    int frames = (int)(sampleRate * total);
    std::vector<int16_t> data(frames, 0);
    int perBurst = (int)(sampleRate * burstDur);
    int perGap = (int)(sampleRate * gapDur);
    std::uniform_real_distribution<float> noiseDist(-1.0f, 1.0f);
    float prev = 0.0f;
    for (int b = 0; b < bursts; ++b) {
        int start = b * (perBurst + perGap);
        for (int j = 0; j < perBurst && start + j < frames; ++j) {
            float env = sinf(M_PI * (float)j / perBurst);
            float n = noiseDist(rng);
            prev = 0.4f * n + 0.6f * prev;
            data[start + j] = (int16_t)(prev * env * 0.32f * 32767);
        }
    }
    sf::SoundBuffer buf;
    buf.loadFromSamples(data.data(), frames, 1, sampleRate);
    return buf;
}

// Crackly paper "page flip": 50 short random crackles (each with a sin envelope),
// run through a one-pole high-pass filter, then faded in/out. Mirrors SpriteKit's
// synthPageFlip exactly.
sf::SoundBuffer SoundManager::synthPageFlip() {
    const float total = 0.55f;
    int frames = (int)(sampleRate * total);
    std::vector<float> data(frames, 0.0f);

    std::uniform_int_distribution<int>   startDist(0, std::max(1, frames - 256));
    std::uniform_int_distribution<int>   lenDist((int)(sampleRate * 0.003f), (int)(sampleRate * 0.018f));
    std::uniform_real_distribution<float> ampDist(0.15f, 0.55f);
    std::uniform_real_distribution<float> noiseDist(-1.0f, 1.0f);

    const int crackleCount = 50;
    for (int c = 0; c < crackleCount; ++c) {
        int startFrame = startDist(rng);
        int crackleLen = lenDist(rng);
        float amp = ampDist(rng);
        for (int j = 0; j < crackleLen; ++j) {
            int idx = startFrame + j;
            if (idx >= frames) break;
            float t = (float)j / crackleLen;
            data[idx] += noiseDist(rng) * sinf(M_PI * t) * amp;
        }
    }
    // one-pole high-pass (emphasize the crackle, remove low rumble)
    float lp = 0.0f;
    for (int i = 0; i < frames; ++i) {
        lp = 0.82f * lp + 0.18f * data[i];
        data[i] = (data[i] - lp) * 0.85f;
    }
    // 0.05s fade in/out
    const float fade = 0.05f;
    std::vector<int16_t> out(frames);
    for (int i = 0; i < frames; ++i) {
        float t = (float)i / sampleRate;
        float env = 1.0f;
        if (t < fade) env = t / fade;
        else if (t > total - fade) env = std::max(0.0f, (total - t) / fade);
        out[i] = (int16_t)(std::clamp(data[i] * env, -1.0f, 1.0f) * 32767);
    }
    sf::SoundBuffer buf;
    buf.loadFromSamples(out.data(), frames, 1, sampleRate);
    return buf;
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

// Non-MIB power-pellet bass: a 16-step, 2.0s loop. Each note is fundamental +
// 2nd (0.40) + 3rd (0.06) harmonics, tanh-saturated. A soft attack + slow decay +
// short release keep it from clicking, and each note rings through a following
// rest so the line grooves instead of tapping ("tap tap tap" on small speakers).
// The trimmed 3rd harmonic takes the tinny edge off; the fuller 2nd carries the
// bass on phone speakers that can't reproduce the fundamental. Matches the
// SpriteKit SoundManager.buildGoldDiscBeat.
sf::SoundBuffer SoundManager::buildGoldDiscBeat() {
    const float duration = 2.0f;
    int frames = (int)(sampleRate * duration);
    std::vector<int16_t> data(frames, 0);
    const float E2 = 82.41f, E3 = 164.81f, G2 = 98.0f, A2 = 110.0f, B2 = 123.47f;
    const float pattern[16] = { E2,E2,0, E3, E2,0, G2,G2, E2,0, A2,A2, G2,0, B2,E3 };
    int slotFrames = frames / 16;
    const float attack = 0.008f, release = 0.010f;
    for (int slot = 0; slot < 16; ++slot) {
        float freq = pattern[slot];
        if (freq <= 0) continue; // rest: filled by the ring-out of the previous note
        bool nextRest = pattern[(slot + 1) % 16] <= 0;
        int noteFrames = slotFrames + (nextRest ? slotFrames : 0);
        float noteDur = (float)noteFrames / sampleRate;
        int startFrame = slot * slotFrames;
        for (int j = 0; j < noteFrames && startFrame + j < frames; ++j) {
            float t = (float)j / sampleRate;
            float env = (t < attack) ? (t / attack) : expf(-2.2f * (t - attack));
            float tail = noteDur - release;
            if (t > tail) env *= std::max(0.0f, (noteDur - t) / release);
            float f1 = sinf(2 * M_PI * freq * t);
            float f2 = sinf(2 * M_PI * freq * 2 * t) * 0.40f;
            float f3 = sinf(2 * M_PI * freq * 3 * t) * 0.06f;
            float raw = (f1 + f2 + f3) * 1.6f * env;
            data[startFrame + j] = (int16_t)(tanhf(raw) * 0.34f * 32767);
        }
    }
    sf::SoundBuffer buf;
    buf.loadFromSamples(data.data(), frames, 1, sampleRate);
    return buf;
}

// MIB power-pellet bass (levels 12/24): a 100 BPM, 2.4s C-minor riff matching the
// SpriteKit SoundManager.buildMIBGoldDiscBeat. Fundamental + warm 2nd harmonic,
// tanh-saturated, with a soft attack / slow decay / short release so it grooves as
// a bass rather than a tinny tap on small speakers. (Replaces a sparse pure-sine
// loop that had drifted out of parity with the Swift master.)
sf::SoundBuffer SoundManager::buildMIBGoldDiscBeat() {
    const float duration = 60.0f / 100.0f * 4.0f; // 2.4s
    int frames = (int)(sampleRate * duration);
    std::vector<int16_t> data(frames, 0);
    const float C2 = 65.41f, Eb2 = 77.78f, F2 = 87.31f, G2 = 98.0f, Ab2 = 103.83f;
    const float bass[8] = { C2, G2, Eb2, G2, Ab2, G2, F2, G2 };
    int slotFrames = frames / 8;
    const float attack = 0.008f, release = 0.018f;
    float slotDuration = (float)slotFrames / sampleRate;
    for (int slot = 0; slot < 8; ++slot) {
        float freq = bass[slot];
        int startFrame = slot * slotFrames;
        for (int j = 0; j < slotFrames && startFrame + j < frames; ++j) {
            float t = (float)j / sampleRate;
            float env = (t < attack) ? (t / attack) : expf(-2.2f * (t - attack));
            float tailStart = slotDuration - release;
            if (t > tailStart) env *= std::max(0.0f, (slotDuration - t) / release);
            float s = sinf(2 * M_PI * freq * t) + 0.4f * sinf(2 * M_PI * freq * 2 * t);
            data[startFrame + j] = (int16_t)(tanhf(s * 1.2f) * 0.30f * env * 32767);
        }
    }
    sf::SoundBuffer buf;
    buf.loadFromSamples(data.data(), frames, 1, sampleRate);
    return buf;
}

void SoundManager::startGoldDiscBass(bool mib) {
    // The bass stands in for the background music during blue mode: pause the
    // music so the two never overlap, and play the bass 15% louder.
    musicSound.pause();
    bassSound.stop();
    bassBuffer = mib ? buildMIBGoldDiscBeat() : buildGoldDiscBeat();
    bassSound.setBuffer(bassBuffer);
    bassSound.setLoop(true);
    bassSound.setVolume((mib ? 67.5f : 90.f) * 1.15f); // SpriteKit 0.9*(mib?0.75:1.0), +15% while it replaces the music
    bassSound.play();
    bassEnabled = true;
}

void SoundManager::stopGoldDiscBass() {
    bool wasActive = bassEnabled;
    bassEnabled = false;
    bassSound.stop();
    // Resume the background music at its unchanged volume. Guarded by wasActive so
    // teardown paths (game over, stop-all) that also call this never revive it.
    if (wasActive && musicEnabled) musicSound.play();
}
void SoundManager::pauseAudio() {
    musicSound.pause();
    bassSound.pause();
    for (auto& s : sounds) s.pause();
}
void SoundManager::resumeAudio() {
    if (musicEnabled && !bassEnabled) musicSound.play(); // keep music silent while the bass owns blue mode
    if (bassEnabled) bassSound.play();
}

} // namespace bm