// gen_sfx.cpp — standalone pre-renderer for BossMan's synthesized SFX.
//
// is-Engine's SDL2 sf::SoundBuffer wrapper only supports loadFromFile, not
// loadFromSamples. So every procedurally-synthesized effect from
// boss-man-box2d-sfml-cpp/src/SoundManager.cpp is rendered here to a 16-bit PCM
// mono 44100 Hz .wav under boss-man-wasm/assets/sfx/<key>.wav.
//
// The DSP math is copied faithfully from SoundManager.cpp; only the
// sf::SoundBuffer wrapper is dropped (samples go straight to a hand-rolled WAV
// writer). Noise-using builders each get a fresh std::mt19937{42} to stay
// deterministic, matching the seed used in SoundManager.hpp.
//
// Build: clang++ -std=c++17 -O2 gen_sfx.cpp -o /tmp/gen_sfx
// Run:   /tmp/gen_sfx   (writes into ../assets/sfx relative to this file)

#include <cstdint>
#include <cstdio>
#include <cmath>
#include <vector>
#include <string>
#include <random>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static const int sampleRate = 44100;

// rng matches SoundManager.hpp: std::mt19937 rng{42};
static std::mt19937 rng{42};
static void resetRng() { rng.seed(42); }

// MARK: - WAV writer (44-byte RIFF/WAVE header + int16 LE samples)
static void writeWav(const std::string& path, const std::vector<int16_t>& samples) {
    FILE* f = std::fopen(path.c_str(), "wb");
    if (!f) { std::fprintf(stderr, "ERROR: cannot open %s\n", path.c_str()); return; }
    const uint16_t channels = 1;
    const uint32_t rate = (uint32_t)sampleRate;
    const uint16_t bits = 16;
    const uint16_t blockAlign = channels * bits / 8;
    const uint32_t byteRate = rate * blockAlign;
    const uint32_t dataBytes = (uint32_t)(samples.size() * sizeof(int16_t));
    const uint32_t riffSize = 36 + dataBytes;

    auto w32 = [&](uint32_t v) { uint8_t b[4]={(uint8_t)v,(uint8_t)(v>>8),(uint8_t)(v>>16),(uint8_t)(v>>24)}; std::fwrite(b,1,4,f); };
    auto w16 = [&](uint16_t v) { uint8_t b[2]={(uint8_t)v,(uint8_t)(v>>8)}; std::fwrite(b,1,2,f); };

    std::fwrite("RIFF", 1, 4, f);
    w32(riffSize);
    std::fwrite("WAVE", 1, 4, f);
    std::fwrite("fmt ", 1, 4, f);
    w32(16);            // fmt chunk size (PCM)
    w16(1);             // audio format = PCM
    w16(channels);
    w32(rate);
    w32(byteRate);
    w16(blockAlign);
    w16(bits);
    std::fwrite("data", 1, 4, f);
    w32(dataBytes);
    if (!samples.empty()) std::fwrite(samples.data(), sizeof(int16_t), samples.size(), f);
    std::fclose(f);
}

// MARK: - Synth helpers (faithful copies of SoundManager.cpp)

static std::vector<int16_t> tone(float freq, float dur, float vol, float decay = 8.0f) {
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
    return samples;
}

static std::vector<int16_t> sweep(float from, float to, float dur, float vol) {
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
    return samples;
}

static std::vector<int16_t> sequence(const std::vector<float>& notes, float perNote, float vol) {
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
    return samples;
}

static std::vector<int16_t> buildTeleport() {
    resetRng();
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
    return data;
}

static std::vector<int16_t> synthFiltered(float seconds, int bursts, float vol) {
    resetRng();
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
    return out;
}

static std::vector<int16_t> synthPrinter() {
    resetRng();
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
    return data;
}

static std::vector<int16_t> synthFax() {
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
    return data;
}

static std::vector<int16_t> synthCollator() {
    resetRng();
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
    return data;
}

static std::vector<int16_t> synthPageFlip() {
    resetRng();
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
    float lp = 0.0f;
    for (int i = 0; i < frames; ++i) {
        lp = 0.82f * lp + 0.18f * data[i];
        data[i] = (data[i] - lp) * 0.85f;
    }
    const float fade = 0.05f;
    std::vector<int16_t> out(frames);
    for (int i = 0; i < frames; ++i) {
        float t = (float)i / sampleRate;
        float env = 1.0f;
        if (t < fade) env = t / fade;
        else if (t > total - fade) env = std::max(0.0f, (total - t) / fade);
        out[i] = (int16_t)(std::clamp(data[i] * env, -1.0f, 1.0f) * 32767);
    }
    return out;
}

static std::vector<int16_t> buildGoldDiscBeat() {
    const float duration = 2.0f;
    int frames = (int)(sampleRate * duration);
    std::vector<int16_t> data(frames, 0);
    const float E2 = 82.41f, E3 = 164.81f, G2 = 98.0f, A2 = 110.0f, B2 = 123.47f;
    const float pattern[16] = { E2,E2,0, E3, E2,0, G2,G2, E2,0, A2,A2, G2,0, B2,E3 };
    int slotFrames = frames / 16;
    const float attack = 0.005f;
    for (int slot = 0; slot < 16; ++slot) {
        float freq = pattern[slot];
        if (freq <= 0) continue;
        int startFrame = slot * slotFrames;
        for (int j = 0; j < slotFrames && startFrame + j < frames; ++j) {
            float t = (float)j / sampleRate;
            float env = (t < attack) ? (t / attack) : expf(-3.8f * (t - attack));
            float f1 = sinf(2 * M_PI * freq * t);
            float f2 = sinf(2 * M_PI * freq * 2 * t) * 0.35f;
            float f3 = sinf(2 * M_PI * freq * 3 * t) * 0.12f;
            float raw = (f1 + f2 + f3) * 1.8f * env;
            data[startFrame + j] = (int16_t)(tanhf(raw) * 0.34f * 32767);
        }
    }
    return data;
}

static std::vector<int16_t> buildMIBGoldDiscBeat() {
    const float duration = 60.0f / 100.0f * 4.0f; // 2.4s
    int frames = (int)(sampleRate * duration);
    std::vector<int16_t> data(frames, 0);
    const float C2 = 65.41f, G2 = 98.0f;
    const float pattern[8] = { C2,0,C2,0, G2,0,C2,0 };
    int slotFrames = frames / 8;
    const float attack = 0.006f, release = 0.02f;
    float slotDuration = (float)slotFrames / sampleRate;
    for (int slot = 0; slot < 8; ++slot) {
        float freq = pattern[slot];
        if (freq <= 0) continue;
        int startFrame = slot * slotFrames;
        for (int j = 0; j < slotFrames && startFrame + j < frames; ++j) {
            float t = (float)j / sampleRate;
            float env = (t < attack) ? (t / attack) : expf(-3.2f * (t - attack));
            float tailStart = slotDuration - release;
            if (t > tailStart) env *= std::max(0.0f, (slotDuration - t) / release);
            data[startFrame + j] = (int16_t)(sinf(2 * M_PI * freq * t) * 0.34f * env * 32767);
        }
    }
    return data;
}

// MARK: - main

int main() {
    const std::string out = "../assets/sfx/";
    int n = 0;
    auto emit = [&](const std::string& key, const std::vector<int16_t>& s) {
        writeWav(out + key + ".wav", s);
        std::printf("%-26s %8zu samples\n", (key + ".wav").c_str(), s.size());
        ++n;
    };

    // Core SFX
    emit("goldDisc",       sweep(220, 660, 0.45f, 0.35f));
    emit("footstep",       tone(140, 0.025f, 0.07f, 60.0f));
    emit("caughtByBoss",   sweep(330, 60, 0.7f, 0.4f));
    emit("fishOrTreat",    sequence({1320, 1760, 2093}, 0.08f, 0.3f));
    emit("tpsDeliver",     sequence({660, 880, 1320}, 0.12f, 0.35f));
    emit("gameOver",       sequence({392, 311, 261, 196}, 0.18f, 0.4f));
    emit("levelStart",     sequence({523, 659, 784, 1046}, 0.12f, 0.3f));
    emit("teleport",       buildTeleport());
    emit("waterGunPickup", sweep(440, 1320, 0.3f, 0.3f));
    emit("waterGunShoot",  sweep(880, 440, 0.08f, 0.25f));
    emit("waterGunSplash", sweep(660, 220, 0.3f, 0.35f));

    // Machines
    emit("printer",  synthPrinter());
    emit("fax",      synthFax());
    emit("pageFlip", synthPageFlip());
    emit("collator", synthCollator());

    // Capture boss arpeggios: count = clamp(streak+1, 2, 4) -> notes = first `count`
    // of {base, base*1.5, base*2, base*3}, base=440. Keys are "capture<count>".
    {
        float base = 440;
        std::vector<float> arp = {base, base*1.5f, base*2, base*3};
        for (int count = 2; count <= 4; ++count) {
            std::vector<float> notes(arp.begin(), arp.begin() + count);
            emit("capture" + std::to_string(count), sequence(notes, 0.08f, 0.35f));
        }
    }

    // Dot blips: playDotBlip caches key
    //   "dot-" + stage + (toggle?"hi":"lo") + (isMIB?"m":"")
    // built as tone(freq, 0.05, vol). stage in 0..3, two freqs per stage, two
    // volumes (non-MIB 0.22, MIB 0.11). Emit all 16 distinct cached variants.
    {
        const float dotStages[4][2]    = {{988.00f,1174.66f},{1396.91f,1174.66f},{1396.91f,1760.00f},{783.99f,987.77f}};
        const float mibDotStages[4][2] = {{523.25f,622.25f},{622.25f,783.99f},{783.99f,1046.50f},{932.33f,783.99f}};
        for (int stage = 0; stage < 4; ++stage) {
            // non-MIB: vol 0.22, toggle hi=index0, lo=index1
            emit("dot-" + std::to_string(stage) + "hi",  tone(dotStages[stage][0], 0.05f, 0.22f));
            emit("dot-" + std::to_string(stage) + "lo",  tone(dotStages[stage][1], 0.05f, 0.22f));
            // MIB: vol 0.11, key suffix "m"
            emit("dot-" + std::to_string(stage) + "him", tone(mibDotStages[stage][0], 0.05f, 0.11f));
            emit("dot-" + std::to_string(stage) + "lom", tone(mibDotStages[stage][1], 0.05f, 0.11f));
        }
    }

    // Traveler arrival sounds. prefix p = "travelerArrive_" (from playTravelerArrive).
    {
        const std::string p = "travelerArrive_";
        emit(p + "water",       sweep(520, 180, 0.55f, 0.14f));
        emit(p + "glaze",       sequence({2093, 2637, 3136}, 0.07f, 0.13f));
        emit(p + "crunch",      synthFiltered(0.35f, 12, 0.18f));
        emit(p + "alienBleep",  sequence({880, 1320, 1760, 1320}, 0.06f, 0.16f));
        emit(p + "jelly",       sweep(660, 990, 0.7f, 0.12f));
        emit(p + "crispTap",    tone(1568, 0.12f, 0.18f, 22.0f));
        emit(p + "bellDing",    sequence({1568, 2093}, 0.22f, 0.16f));
        emit(p + "radioStatic", synthFiltered(0.6f, 1, 0.10f));
        emit(p + "magicChime",  sequence({1318, 1976, 2637, 3520}, 0.07f, 0.13f));
        emit(p + "ufoWhoosh",   sweep(1760, 220, 0.65f, 0.13f));
        emit(p + "eyeDrone",    tone(196, 0.8f, 0.18f, 2.0f));
        emit(p + "bigEye",      sequence({659, 880, 1175, 1568}, 0.07f, 0.14f));
    }

    // Looping power-pellet bass channels (startGoldDiscBass).
    emit("goldDiscBeat",    buildGoldDiscBeat());
    emit("mibGoldDiscBeat", buildMIBGoldDiscBeat());

    // Background music loops (startBackgroundMusic): sequence over a bass pattern.
    {
        std::vector<float> notes = {130.81f,164.81f,130.81f,196.0f,174.61f,220.0f,174.61f,261.63f,
                                    155.56f,196.0f,155.56f,233.08f,174.61f,220.0f,130.81f,164.81f};
        emit("backgroundMusic", sequence(notes, 0.278f, 0.12f));
    }
    {
        std::vector<float> notes = {65.41f,0,65.41f,0,98.0f,0,65.41f,0,
                                    77.78f,0,77.78f,0,98.0f,0,77.78f,0};
        emit("mibBackgroundMusic", sequence(notes, 0.15f, 0.14f));
    }

    std::printf("\nGenerated %d wav files into %s\n", n, out.c_str());
    return 0;
}
