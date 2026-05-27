#include "SoundManager.hpp"
#include "Constants.hpp"
#include "Assets.hpp"
#include <algorithm>

namespace bm {

SoundManager::SoundManager() {}

// Loads assets/sfx/<key>.wav from disk via the SFML 2 loadFromFile API and caches
// the buffer by key. Returns nullptr if the file is missing so callers stay silent.
const sf::SoundBuffer* SoundManager::cached(const std::string& key) {
    auto it = cache.find(key);
    if (it != cache.end()) return &it->second;
    sf::SoundBuffer buf;
    if (!buf.loadFromFile("assets/sfx/" + key + ".wav"))
        return nullptr; // wav not generated yet — stay silent rather than error
    auto res = cache.emplace(key, std::move(buf)).first;
    return &res->second;
}

void SoundManager::playVoice(const std::string& key) {
    auto it = voiceCache.find(key);
    if (it == voiceCache.end()) {
        sf::SoundBuffer buf;
        if (!buf.loadFromFile("assets/voice/" + key + ".wav"))
            return; // clip not generated yet — stay silent rather than error
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
    float sfx = ducked ? 25.0f : 100.0f; // SpriteKit duckedEffectsVolume 0.25
    for (auto& s : sounds) s.setVolume(sfx);
    if (musicEnabled) musicSound.setVolume(ducked ? 18.0f : 100.0f); // 0.18
    // Bass is intentionally not ducked, matching SpriteKit's setDucked.
}

void SoundManager::updateDucking() {
    bool playing = (voiceSound.getStatus() == sf::Sound::Playing);
    if (playing != voiceDucked) applyDuck(playing);
}

void SoundManager::playBuffer(const sf::SoundBuffer& buf) {
    float vol = voiceDucked ? 25.0f : 100.0f;
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
    // Key encodes stage + hi/lo + MIB variant; the matching pre-rendered wav holds
    // the pitch/volume that the synth used to compute (per-stage 988..1760 Hz etc.).
    std::string key = "dot-" + std::to_string(stage) + (dotToggle ? "hi" : "lo") + (isMIB ? "m" : "");
    if (const sf::SoundBuffer* b = cached(key)) playBuffer(*b);
    dotsEatenInCycle++;
}

void SoundManager::playGoldDisc() {
    if (const sf::SoundBuffer* b = cached("goldDisc")) playBuffer(*b);
}

void SoundManager::playFootstep() {
    if (const sf::SoundBuffer* b = cached("footstep")) playBuffer(*b);
}

void SoundManager::playCaptureBoss(int streak) {
    int count = std::max(2, std::min(4, streak + 1));
    if (const sf::SoundBuffer* b = cached("capture" + std::to_string(count))) playBuffer(*b);
    playVoiceRandom("capture"); // boss reacts to being captured
}

void SoundManager::playCaughtByBoss() {
    if (const sf::SoundBuffer* b = cached("caughtByBoss")) playBuffer(*b);
    playVoiceRandom("caught"); // boss taunts the worker it just caught
}

void SoundManager::playFishOrTreat() {
    if (const sf::SoundBuffer* b = cached("fishOrTreat")) playBuffer(*b);
    playVoiceRandom("fish");
}

void SoundManager::playTpsDeliver() {
    if (const sf::SoundBuffer* b = cached("tpsDeliver")) playBuffer(*b);
    playVoiceRandom("tps_done");
}

void SoundManager::playGameOver() {
    if (const sf::SoundBuffer* b = cached("gameOver")) playBuffer(*b);
    playVoiceRandom("gameover");
}

void SoundManager::playLevelStart() {
    if (const sf::SoundBuffer* b = cached("levelStart")) playBuffer(*b);
    playVoiceRandom("levelstart");
}

void SoundManager::playTeleport() {
    // Guard so multiple bosses spawning at once don't stack the 1.75s sweep.
    if (teleportPlayed && teleportClock.getElapsedTime().asSeconds() < 1.75f) return;
    teleportPlayed = true;
    teleportClock.restart();
    if (const sf::SoundBuffer* b = cached("teleport")) playBuffer(*b);
}

// One distinct sound per traveler type on arrival (idx matches TRAVELERS order).
void SoundManager::playTravelerArrive(int idx) {
    static const char* keys[12] = {
        "travelerArrive_water",       "travelerArrive_glaze",
        "travelerArrive_crunch",      "travelerArrive_alienBleep",
        "travelerArrive_jelly",       "travelerArrive_crispTap",
        "travelerArrive_bellDing",    "travelerArrive_radioStatic",
        "travelerArrive_magicChime",  "travelerArrive_ufoWhoosh",
        "travelerArrive_eyeDrone",    "travelerArrive_bigEye"
    };
    if (idx < 0 || idx >= 12) return;
    if (const sf::SoundBuffer* b = cached(keys[idx])) playBuffer(*b);
}

void SoundManager::playWaterGunPickup() {
    if (const sf::SoundBuffer* b = cached("waterGunPickup")) playBuffer(*b);
}

void SoundManager::playWaterGunShoot() {
    if (const sf::SoundBuffer* b = cached("waterGunShoot")) playBuffer(*b);
}

void SoundManager::playWaterGunSplash() {
    if (const sf::SoundBuffer* b = cached("waterGunSplash")) playBuffer(*b);
}

void SoundManager::playMachine(const std::string& name) {
    const char* key = nullptr;
    if (name == Machine::PRINTER) key = "printer";
    else if (name == Machine::FAX) key = "fax";
    else if (name == Machine::COVER_SHEET) key = "pageFlip";
    else if (name == Machine::BOOK_BINDER) key = "collator";
    else { playDotBlip(); return; }
    if (const sf::SoundBuffer* b = cached(key)) playBuffer(*b);
}

void SoundManager::startBackgroundMusic(bool mib) {
    if (musicEnabled && isMIB == mib) return;
    isMIB = mib;
    if (!musicBuffer.loadFromFile(mib ? "assets/sfx/bgMusicMIB.wav" : "assets/sfx/bgMusic.wav"))
        return; // loop not generated yet — stay silent rather than error
    musicEnabled = true;
    musicSound.setBuffer(musicBuffer);
    musicSound.setLoop(true);
    musicSound.play();
}

void SoundManager::stopBackgroundMusic() {
    musicEnabled = false;
    musicSound.stop();
}

void SoundManager::startGoldDiscBass(bool mib) {
    // Dedicated bass channel, looped, layered over the background music.
    bassSound.stop();
    if (!bassBuffer.loadFromFile(mib ? "assets/sfx/mibGoldDiscBeat.wav" : "assets/sfx/goldDiscBeat.wav"))
        return; // beat not generated yet — stay silent rather than error
    bassSound.setBuffer(bassBuffer);
    bassSound.setLoop(true);
    bassSound.setVolume(mib ? 67.5f : 90.f); // SpriteKit: 0.9 * (mib ? 0.75 : 1.0)
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