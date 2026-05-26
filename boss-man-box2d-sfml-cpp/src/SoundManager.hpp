#pragma once
#include <SFML/Audio.hpp>
#include <vector>
#include <unordered_map>
#include <string>
#include <cmath>
#include <random>

namespace bm {

class SoundManager {
public:
    SoundManager();
    void playDotBlip();
    void playGoldDisc();
    void playFootstep();
    void playCaptureBoss(int streak);
    void playCaughtByBoss();
    void playFishOrTreat();
    void playTpsDeliver();
    void playGameOver();
    void playLevelStart();
    void playTeleport();
    void playWaterGunPickup();
    void playWaterGunShoot();
    void playWaterGunSplash();
    void playMachine(const std::string& name);
    void startBackgroundMusic(bool mib);
    void stopBackgroundMusic();
    void startGoldDiscBass(bool mib);
    void stopGoldDiscBass();
    void pauseAudio();
    void resumeAudio();

private:
    sf::SoundBuffer tone(float freq, float dur, float vol, float decay = 12.0f);
    sf::SoundBuffer sweep(float from, float to, float dur, float vol);
    sf::SoundBuffer sequence(const std::vector<float>& notes, float perNote, float vol);
    sf::SoundBuffer makeNoise(float dur, int bursts, float vol);

    void playBuffer(const sf::SoundBuffer& buf);
    const sf::SoundBuffer& cached(const std::string& key, std::function<sf::SoundBuffer()> build);

    std::unordered_map<std::string, sf::SoundBuffer> cache;
    std::vector<sf::Sound> sounds;
    sf::Sound musicSound;
    sf::Sound bassSound;
    sf::SoundBuffer musicBuffer;
    sf::SoundBuffer bassBuffer;
    bool musicEnabled = false;
    bool bassEnabled = false;
    bool isMIB = false;

    int dotsEatenInCycle = 0;
    bool dotToggle = false;
    float lastDotEatTime = 0;
    sf::Clock dotClock;
    int sampleRate = 44100;
    std::mt19937 rng{42};
};

} // namespace bm