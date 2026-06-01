import AVFoundation
import Foundation
#if os(WASI)
import KitABI
import SpriteKit
#endif

enum MusicTheme {
    case normal
    case mib
}

@MainActor
final class SoundManager {
    private let engine = AVAudioEngine()
    private let effectsPlayer = AVAudioPlayerNode()
    private let musicPlayer = AVAudioPlayerNode()
    private let bassPlayer = AVAudioPlayerNode()
    private var goldDiscBeatBuffer: AVAudioPCMBuffer?
    private var mibGoldDiscBeatBuffer: AVAudioPCMBuffer?
    private var bufferCache: [String: AVAudioPCMBuffer] = [:]
    private let speech = AVSpeechSynthesizer()
    var isSpeaking: Bool { speech.isSpeaking }
    #if os(macOS)
    private let voice: AVSpeechSynthesisVoice? = SoundManager.pickBossVoice()
    #else
    // The runtime picks the voice on web (see applyWebVoicePreferences); no
    // in-process selection, so we skip pickBossVoice entirely. That matters
    // because its `.lowercased()` calls would link ICU's ~30MB Unicode tables.
    private let voice: AVSpeechSynthesisVoice? = nil
    #endif
    #if os(macOS)
    // Speech ducking rides AVSpeechSynthesizer's @objc delegate, which requires
    // an NSObject. Keeping that on a small helper (not on SoundManager itself)
    // keeps SoundManager free of NSObject, so the wasm build doesn't pull all of
    // Foundation in and balloon the binary.
    private let speechDuck = SpeechDuckDelegate()
    #endif

    #if os(macOS)
    // Voice priority. Gender is NOT a filter — female voices are ranked last, not
    // excluded. We walk Strings.Speech.preferredVoiceNames in order (list order =
    // priority), preferring en-US over other English variants. The robotic /
    // novelty voices are still excluded by name.
    private static func pickBossVoice() -> AVSpeechSynthesisVoice? {
        let robotic = Strings.Speech.roboticVoiceNames
        let usable = AVSpeechSynthesisVoice.speechVoices().filter {
            let n = $0.name.lowercased()
            return !robotic.contains(where: { n.contains($0) })
        }
        let nonFemale = usable.filter { $0.gender != .female }
        let female    = usable.filter { $0.gender == .female }
        func usOnly(_ a: [AVSpeechSynthesisVoice]) -> [AVSpeechSynthesisVoice] { a.filter { $0.language == Strings.Speech.usEnglish } }
        func anyEn(_ a: [AVSpeechSynthesisVoice])  -> [AVSpeechSynthesisVoice] { a.filter { $0.language.hasPrefix(Strings.Speech.englishPrefix) } }

        // en-US non-female → any-English non-female → female (US, then any English).
        return bestVoice(in: usOnly(nonFemale))
            ?? bestVoice(in: anyEn(nonFemale))
            ?? bestVoice(in: usOnly(female))
            ?? bestVoice(in: anyEn(female))
            ?? AVSpeechSynthesisVoice(language: Strings.Speech.usEnglish)
    }

    // Walks the preferred-name list in order; for each name returns the highest-
    // quality matching voice in the pool, else the best-quality voice in the pool.
    private static func bestVoice(in pool: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        for name in Strings.Speech.preferredVoiceNames {
            let m = pool.filter { $0.identifier.lowercased().contains(name) || $0.name.lowercased().contains(name) }
            if let v = m.first(where: { $0.quality == .premium })
                    ?? m.first(where: { $0.quality == .enhanced })
                    ?? m.first { return v }
        }
        return pool.first(where: { $0.quality == .premium })
            ?? pool.first(where: { $0.quality == .enhanced })
            ?? pool.first
    }
    #endif

    private var bossCaptureLines: [String] { Strings.Speech.bossCaptureLines }
    private var caughtLines:      [String] { Strings.Speech.caughtLines }
    private var fishLines:        [String] { Strings.Speech.fishLines }
    private var tpsLines:         [String] { Strings.Speech.tpsLines }
    private var gameOverLines:    [String] { Strings.Speech.gameOverLines }
    private var levelStartLines:  [String] { Strings.Speech.levelStartLines }
    private let sampleRate: Double = 44100
    private let format: AVAudioFormat
    private var musicBuffers: [MusicTheme: AVAudioPCMBuffer] = [:]
    private var currentMusicTheme: MusicTheme = .normal

    private var dotToggle = false
    private var dotsEatenInCycle: Int = 0
    private var lastDotEatTime: TimeInterval = 0
    
    private let dotStages: [(Float, Float)] = [
        (988.00, 1174.66),
        (1396.91, 1174.66),
        (1396.91, 1760.00),
        (783.99, 987.77)
    ]
    // MIB dots an octave below the originals (C5-C6 read as a tinny ting against
    // the dark 12/24 theme); same C-minor pattern, just warmer.
    private let mibDotStages: [(Float, Float)] = [
        (261.63, 311.13),
        (311.13, 392.00),
        (392.00, 523.25),
        (466.16, 392.00)
    ]
    private let dotsPerStage: [Int] = [4, 2, 4, 2]
    private var lastSpeechTime: TimeInterval = 0
    private let speechCooldown: TimeInterval = 1.5
    private var teleportPlaying = false
    
    private var musicEnabled = false
    private var goldDiscBassActive = false   // bass stands in for the music during blue mode; the two never overlap

    private let normalEffectsVolume: Float = 0.5
    private let duckedEffectsVolume: Float = 0.12
    private let normalMusicVolume: Float = 1.0
    private let duckedMusicVolume: Float = 0.25   // match the wasm duck factor (0.25)

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(effectsPlayer)
        engine.attach(musicPlayer)
        engine.attach(bassPlayer)
        engine.connect(effectsPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(musicPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(bassPlayer, to: engine.mainMixerNode, format: format)
        bassPlayer.volume = 0.9
        engine.mainMixerNode.outputVolume = 0.55
        effectsPlayer.volume = normalEffectsVolume
        musicPlayer.volume = normalMusicVolume
        #if os(macOS)
        speechDuck.owner = self
        speech.delegate = speechDuck
        #endif
        let outputAU = engine.outputNode.auAudioUnit
        outputAU.maximumFramesToRender = max(outputAU.maximumFramesToRender, 4096)
        do {
            try engine.start()
        } catch {
        }
        #if os(WASI)
        SoundManager.applyWebVoicePreferences()
        #endif
    }

    #if os(WASI)
    // apple ranks voices in pickBossVoice; on web the runtime owns selection, so
    // hand it the same name lists as CSVs (priority, robotic-excluded, female-last).
    private static func applyWebVoicePreferences() {
        sendCSV(Strings.Speech.preferredVoiceNames.joined(separator: ","), tts_set_preferred_voices)
        sendCSV(Strings.Speech.roboticVoiceNames.joined(separator: ","),   tts_set_robotic_voices)
        sendCSV(Strings.Speech.femaleVoiceNames.joined(separator: ","),    tts_set_female_voices)
    }
    private static func sendCSV(_ s: String, _ f: (UnsafePointer<CChar>?, Int32) -> Void) {
        let bytes = Array(s.utf8)
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            base.withMemoryRebound(to: CChar.self, capacity: buf.count) { f($0, Int32(buf.count)) }
        }
    }
    #endif

    // MARK: - Speech ducking
    fileprivate func setDucked(_ ducked: Bool) {
        effectsPlayer.volume = ducked ? duckedEffectsVolume : normalEffectsVolume
        let base = ducked ? duckedMusicVolume : normalMusicVolume
        musicPlayer.volume = base * themeMusicMultiplier(currentMusicTheme)
    }

    private func themeMusicMultiplier(_ theme: MusicTheme) -> Float {
        switch theme {
        case .normal: return 1.0
        case .mib:    return 0.625
        }
    }

    // MARK: - Public events
    private func cached(_ key: String, _ build: () -> AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        if let buf = bufferCache[key] { return buf }
        let built = build()
        bufferCache[key] = built
        return built
    }

    func playDotBlip() {
        let now = CACurrentMediaTime()
        if now - lastDotEatTime > 1.5 {
            dotsEatenInCycle = 0
        }
        lastDotEatTime = now

        let cycleLen = dotsPerStage.reduce(0, +)
        let positionInCycle = dotsEatenInCycle % cycleLen
        var stageIndex = 0
        var threshold = 0
        for (i, count) in dotsPerStage.enumerated() {
            threshold += count
            if positionInCycle < threshold {
                stageIndex = i
                break
            }
        }

        dotToggle.toggle()
        let mib = currentMusicTheme == .mib
        let pair = mib ? mibDotStages[stageIndex] : dotStages[stageIndex]
        let freq = dotToggle ? pair.0 : pair.1
        let vol: Float = mib ? 0.11 : 0.22
        let key = Strings.SoundCache.dotKey(stage: stageIndex, highToggle: !dotToggle, mib: mib)
        play(buffer: cached(key) { self.tone(frequency: freq, duration: 0.05, volume: vol) })

        dotsEatenInCycle += 1
    }

    func playGoldDisc() {
        play(buffer: cached(Strings.SoundCache.goldDisc) { self.sweep(from: 220, to: 660, duration: 0.45, volume: 0.35) })
    }

    func playWaterGunPickup() {
        play(buffer: cached(Strings.SoundCache.waterGunPickup) { self.sweep(from: 440, to: 1320, duration: 0.3, volume: 0.3) })
    }

    func playWaterGunShoot() {
        play(buffer: cached(Strings.SoundCache.waterGunShoot) { self.sweep(from: 880, to: 440, duration: 0.08, volume: 0.25) })
    }

    func playWaterGunSplash() {
        play(buffer: cached(Strings.SoundCache.waterGunSplash) { self.sweep(from: 660, to: 220, duration: 0.3, volume: 0.35) })
    }

    func playFootstep() {
        play(buffer: cached(Strings.SoundCache.footstep) { self.tone(frequency: 140, duration: 0.025, volume: 0.07, decay: 60) })
    }

    func playCaptureBoss(streak: Int) {
        let base: Float = 440
        let arp: [Float] = [base, base * 1.5, base * 2, base * 3]
        let count = max(2, min(4, streak + 1))
        play(buffer: cached("\(Strings.SoundCache.captureBossPrefix)\(count)") {
            self.sequence(notes: Array(arp.prefix(count)), perNote: 0.08, volume: 0.35)
        })
        speak(bossCaptureLines.randomElement(using: &GameRandom.shared) ?? Strings.Speech.fallback, priority: false)
    }

    @discardableResult
    func playCaughtByBoss() -> TimeInterval {
        play(buffer: cached(Strings.SoundCache.caughtByBoss) { self.sweep(from: 330, to: 60, duration: 0.7, volume: 0.4) })
        return speak(caughtLines.randomElement(using: &GameRandom.shared) ?? Strings.Speech.caughtFallback, priority: true)
    }

    func playFishOrTreat() {
        play(buffer: cached(Strings.SoundCache.fishOrTreat) { self.sequence(notes: [1320, 1760, 2093], perNote: 0.08, volume: 0.3) })
        speak(fishLines.randomElement(using: &GameRandom.shared) ?? Strings.Speech.fishFallback, priority: false)
    }

    func playTpsDeliver() {
        play(buffer: cached(Strings.SoundCache.tpsDeliver) { self.sequence(notes: [660, 880, 1320], perNote: 0.12, volume: 0.35) })
        speak(tpsLines.randomElement(using: &GameRandom.shared) ?? Strings.Speech.tpsFallback, priority: false)
    }

    func playTpsMissingItems(_ items: [String]) {
        let names = items.map { Strings.Machine.displayNames[$0] ?? $0 }
        speak("The TPS report is missing \(names.joined(separator: ", ")).", priority: true)
    }

    func playGameOver() {
        play(buffer: cached(Strings.SoundCache.gameOver) { self.sequence(notes: [392, 311, 261, 196], perNote: 0.18, volume: 0.4) })
        speak(gameOverLines.randomElement(using: &GameRandom.shared) ?? Strings.Speech.gameOverFallback, priority: true)
    }

    func playMachine(named name: String) {
        switch name {
        case Strings.Machine.printer:    play(buffer: cached(Strings.SoundCache.printer)  { self.synthPrinter()  })
        case Strings.Machine.fax:        play(buffer: cached(Strings.SoundCache.fax)      { self.synthFax()      })
        case Strings.Machine.coverSheet: play(buffer: cached(Strings.SoundCache.pageFlip) { self.synthPageFlip() })
        case Strings.Machine.bookBinder: play(buffer: cached(Strings.SoundCache.collator) { self.synthCollator() })
        default:         playDotBlip()
        }
    }

    func playTravelerArrive(_ which: TravelerSound) {
        switch which {
        case .water:
            play(buffer: cached("\(Strings.SoundCache.travelerPrefix)water") { self.sweep(from: 520, to: 180, duration: 0.55, volume: 0.14) })
        case .glaze:
            play(buffer: cached("\(Strings.SoundCache.travelerPrefix)glaze") { self.sequence(notes: [2093, 2637, 3136], perNote: 0.07, volume: 0.13) })
        case .crunch:
            play(buffer: cached("\(Strings.SoundCache.travelerPrefix)crunch") { self.synthFiltered(noiseSeconds: 0.35, bursts: 12, volume: 0.18) })
        case .alienBleep:
            play(buffer: cached("\(Strings.SoundCache.travelerPrefix)alienBleep") { self.sequence(notes: [880, 1320, 1760, 1320], perNote: 0.06, volume: 0.16) })
        case .jelly:
            play(buffer: cached("\(Strings.SoundCache.travelerPrefix)jelly") { self.sweep(from: 660, to: 990, duration: 0.7, volume: 0.12) })
        case .crispTap:
            play(buffer: cached("\(Strings.SoundCache.travelerPrefix)crispTap") { self.tone(frequency: 1568, duration: 0.12, volume: 0.18, decay: 22) })
        case .bellDing:
            play(buffer: cached("\(Strings.SoundCache.travelerPrefix)bellDing") { self.sequence(notes: [1568, 2093], perNote: 0.22, volume: 0.16) })
        case .radioStatic:
            play(buffer: cached("\(Strings.SoundCache.travelerPrefix)radioStatic") { self.synthFiltered(noiseSeconds: 0.6, bursts: 1, volume: 0.10) })
        case .magicChime:
            play(buffer: cached("\(Strings.SoundCache.travelerPrefix)magicChime") { self.sequence(notes: [1318, 1976, 2637, 3520], perNote: 0.07, volume: 0.13) })
        case .ufoWhoosh:
            play(buffer: cached("\(Strings.SoundCache.travelerPrefix)ufoWhoosh") { self.sweep(from: 1760, to: 220, duration: 0.65, volume: 0.13) })
        case .eyeDrone:
            play(buffer: cached("\(Strings.SoundCache.travelerPrefix)eyeDrone") { self.tone(frequency: 196, duration: 0.8, volume: 0.18, decay: 2) })
        case .bigEye:
            play(buffer: cached("\(Strings.SoundCache.travelerPrefix)bigEye") { self.sequence(notes: [659, 880, 1175, 1568], perNote: 0.07, volume: 0.14) })
        }
    }

    private func synthFiltered(noiseSeconds total: TimeInterval, bursts: Int, volume: Float) -> AVAudioPCMBuffer {
        let buffer = makeBuffer(seconds: total)
        let data = buffer.floatChannelData![0]
        let frames = Int(buffer.frameLength)
        for i in 0..<frames { data[i] = 0 }
        if bursts <= 1 {
            for i in 0..<frames {
                data[i] = Float.random(in: -1...1, using: &GameRandom.shared)
            }
        } else {
            for _ in 0..<bursts {
                let startFrame = Int.random(in: 0..<max(1, frames - 1024), using: &GameRandom.shared)
                let len = Int.random(in: Int(sampleRate * 0.01)...Int(sampleRate * 0.04), using: &GameRandom.shared)
                for j in 0..<len where startFrame + j < frames {
                    let t = Float(j) / Float(len)
                    data[startFrame + j] += Float.random(in: -1...1, using: &GameRandom.shared) * sin(.pi * t)
                }
            }
        }
        var lp: Float = 0
        for i in 0..<frames {
            lp = 0.78 * lp + 0.22 * data[i]
            data[i] = (data[i] - lp) * volume
        }
        let fade: Float = 0.04
        let durF = Float(total)
        for i in 0..<frames {
            let t = Float(i) / Float(sampleRate)
            let env: Float
            if t < fade { env = t / fade }
            else if t > durF - fade { env = max(0, (durF - t) / fade) }
            else { env = 1 }
            data[i] *= env
        }
        return buffer
    }

    @discardableResult
    func playLevelStart() -> TimeInterval {
        play(buffer: cached(Strings.SoundCache.levelStart) { self.sequence(notes: [523, 659, 784, 1046], perNote: 0.12, volume: 0.3) })
        return speak(levelStartLines.randomElement(using: &GameRandom.shared) ?? Strings.Speech.fallback, priority: false)
    }

    func startBackgroundMusic(theme: MusicTheme = .normal) {
        if musicEnabled && currentMusicTheme == theme { return }
        if musicEnabled { musicPlayer.stop() }
        musicEnabled = true
        currentMusicTheme = theme
        let buffer = musicBuffers[theme] ?? {
            let b: AVAudioPCMBuffer
            switch theme {
            case .normal: b = buildBackgroundLoop()
            case .mib:    b = buildSunglassesAtNightLoop()
            }
            musicBuffers[theme] = b
            return b
        }()
        musicPlayer.volume = normalMusicVolume * themeMusicMultiplier(theme)
        musicPlayer.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        if !musicPlayer.isPlaying { musicPlayer.play() }
    }

    func stopBackgroundMusic() {
        musicEnabled = false
        musicPlayer.stop()
    }

    func stopAllAudio() {
        stopBackgroundMusic()
        stopGoldDiscBass()
        effectsPlayer.stop()
        speech.stopSpeaking(at: .immediate)
    }

    func pauseAudio() {
        if musicPlayer.isPlaying { musicPlayer.pause() }
        if effectsPlayer.isPlaying { effectsPlayer.pause() }
        if bassPlayer.isPlaying { bassPlayer.pause() }
        if speech.isSpeaking { speech.pauseSpeaking(at: .word) }
    }

    func resumeAudio() {
        if musicEnabled && !goldDiscBassActive { musicPlayer.play() }   // keep music silent while the bass owns blue mode
        effectsPlayer.play()
        bassPlayer.play()
        if speech.isPaused { speech.continueSpeaking() }
    }

    // MARK: - Gold-disc beat
    func startGoldDiscBass() {
        let useMIB = currentMusicTheme == .mib
        if useMIB {
            if mibGoldDiscBeatBuffer == nil { mibGoldDiscBeatBuffer = buildMIBGoldDiscBeat() }
        } else {
            if goldDiscBeatBuffer == nil { goldDiscBeatBuffer = buildGoldDiscBeat() }
        }
        guard let buffer = useMIB ? mibGoldDiscBeatBuffer : goldDiscBeatBuffer else { return }
        goldDiscBassActive = true
        // Silence the background loop while the bass stands in for it. On wasm the
        // kit's pause()/play() are GLOBAL (snd_pause_all / snd_resume_all), so a
        // merely-paused loop is revived the instant any node resumes (the bass's
        // own play() did exactly that, leaking the music under the bass). Stop the
        // voice outright on wasm and reschedule it on exit; macOS keeps a seamless
        // per-player pause/resume.
        #if os(macOS)
        if musicPlayer.isPlaying { musicPlayer.pause() }
        #elseif os(WASI)
        musicPlayer.stop()
        #endif
        bassPlayer.stop()
        bassPlayer.volume = 0.9 * (useMIB ? 0.75 : 1.0) * 1.15   // 15% louder while standing in for the music
        bassPlayer.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        if !bassPlayer.isPlaying { bassPlayer.play() }
    }

    func stopGoldDiscBass() {
        let wasActive = goldDiscBassActive
        goldDiscBassActive = false
        bassPlayer.stop()
        // Restore the background loop at its unchanged volume. Guarded by wasActive
        // so teardown paths (game over, stop-all) never revive it. On wasm the loop
        // was stopped (not paused), so it must be rescheduled rather than resumed.
        if wasActive && musicEnabled {
            #if os(macOS)
            musicPlayer.play()
            #elseif os(WASI)
            let theme = currentMusicTheme
            musicEnabled = false
            startBackgroundMusic(theme: theme)
            #endif
        }
    }

    private func buildGoldDiscBeat() -> AVAudioPCMBuffer {
        let duration: TimeInterval = 2.0
        let buffer = makeBuffer(seconds: duration)
        let data = buffer.floatChannelData![0]
        let frames = Int(buffer.frameLength)

        let E2: Float = 82.41
        let E3: Float = 164.81
        let G2: Float = 98.00
        let A2: Float = 110.00
        let B2: Float = 123.47
        let _: Float = 0

        let pattern: [Float] = [
            E2, E2, 0,  E3,  E2, 0,  G2, G2,
            E2, 0,  A2, A2,  G2, 0,  B2, E3
        ]
        let slotFrames = frames / pattern.count
        let attack: Float = 0.008
        let release: Float = 0.010

        // Start from silence; notes ring through a following rest (filling the
        // staccato gaps that read as "tap tap tap"), so rests are not re-zeroed.
        for i in 0..<frames { data[i] = 0 }

        for (slot, freq) in pattern.enumerated() where freq > 0 {
            let nextRest = pattern[(slot + 1) % pattern.count] <= 0
            let noteFrames = slotFrames + (nextRest ? slotFrames : 0)
            let noteDur = Float(noteFrames) / Float(sampleRate)
            let startFrame = slot * slotFrames
            for j in 0..<noteFrames where startFrame + j < frames {
                let t = Float(j) / Float(sampleRate)
                var env: Float = (t < attack) ? (t / attack) : exp(-2.2 * (t - attack))
                let tail = noteDur - release
                if t > tail { env *= max(0, (noteDur - t) / release) }
                let f1 = sin(2 * .pi * freq * t)
                let f2 = sin(2 * .pi * freq * 2 * t) * 0.40
                let f3 = sin(2 * .pi * freq * 3 * t) * 0.06
                let raw = (f1 + f2 + f3) * 1.6 * env
                data[startFrame + j] = tanh(raw) * 0.34
            }
        }
        return buffer
    }

    private func buildMIBGoldDiscBeat() -> AVAudioPCMBuffer {
        let duration: TimeInterval = 60.0 / 100.0 * 4.0
        let buffer = makeBuffer(seconds: duration)
        let data = buffer.floatChannelData![0]
        let frames = Int(buffer.frameLength)

        // 100 BPM, 2.4s loop. A driving C-minor riff under the MIB "Sunglasses at
        // Night" theme: fundamental + warm 2nd harmonic, tanh-saturated, with a
        // soft attack / slow decay / short release so it grooves as a bass instead
        // of a tinny tap on small speakers. (The old high G5 "ping" pulse was the
        // tingy part and is gone.)
        let C2: Float = 65.41, Eb2: Float = 77.78, F2: Float = 87.31, G2: Float = 98.00, Ab2: Float = 103.83
        let bass: [Float] = [C2, G2, Eb2, G2, Ab2, G2, F2, G2]
        let slotFrames = frames / bass.count
        let attack: Float = 0.008
        let release: Float = 0.018
        let slotDuration = Float(slotFrames) / Float(sampleRate)

        for (slot, freq) in bass.enumerated() {
            let startFrame = slot * slotFrames
            for j in 0..<slotFrames where startFrame + j < frames {
                let t = Float(j) / Float(sampleRate)
                var env: Float = t < attack ? t / attack : exp(-2.2 * (t - attack))
                let tailStart = slotDuration - release
                if t > tailStart { env *= max(0, (slotDuration - t) / release) }
                let s = sin(2 * .pi * freq * t) + 0.4 * sin(2 * .pi * freq * 2 * t)
                data[startFrame + j] = tanh(s * 1.2) * 0.30 * env
            }
        }
        return buffer
    }

    func playTeleport() {
        if teleportPlaying { return }
        teleportPlaying = true
        let buffer = cached(Strings.SoundCache.teleport) { self.buildTeleport() }
        effectsPlayer.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            runOnMain { self?.teleportPlaying = false }
        }
        if !effectsPlayer.isPlaying { effectsPlayer.play() }
    }

    private func buildTeleport() -> AVAudioPCMBuffer {
        let duration: TimeInterval = 1.75
        let buffer = makeBuffer(seconds: duration)
        let data = buffer.floatChannelData![0]
        let frames = Int(buffer.frameLength)
        let durF = Float(duration)
        let ascStart: Float = 220
        let ascEnd: Float = 1400
        let descStart: Float = 1400
        let descEnd: Float = 220
        var phaseAsc: Float = 0
        var phaseDesc: Float = 0
        let dt: Float = 1.0 / Float(sampleRate)
    
        for i in 0..<frames {
            let t = Float(i) / Float(sampleRate)
            let progress = t / durF
            let ascFreq = ascStart * pow(ascEnd / ascStart, progress)
            let descFreq = descStart * pow(descEnd / descStart, progress)
            phaseAsc += 2 * .pi * ascFreq * dt
            phaseDesc += 2 * .pi * descFreq * dt
            let env = sin(.pi * progress)
            let shimmer = Float.random(in: -1...1, using: &GameRandom.shared) * 0.06
            data[i] = (sin(phaseAsc) * 0.20 + sin(phaseDesc) * 0.15 + shimmer) * env
        }
        return buffer
    }

    // MARK: - Synthesis
    private func play(buffer: AVAudioPCMBuffer) {
        effectsPlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !effectsPlayer.isPlaying { effectsPlayer.play() }
    }

    private func tone(frequency: Float, duration: TimeInterval, volume: Float, decay: Float = 12) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        let attack: Float = 0.004
        let release: Float = 0.012   // fade the tail so the note doesn't cut off with a click ("ting") on phone speakers
        let dur = Float(duration)
        for i in 0..<Int(frames) {
            let t = Float(i) / Float(sampleRate)
            var env: Float = t < attack ? t / attack : exp(-decay * (t - attack))
            if t > dur - release { env *= max(0, (dur - t) / release) }
            data[i] = sin(2 * .pi * frequency * t) * volume * env
        }
        return buffer
    }

    private func sweep(from start: Float, to end: Float, duration: TimeInterval, volume: Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        var phase: Float = 0
        let dt = 1.0 / Float(sampleRate)
        let totalT = Float(duration)
        for i in 0..<Int(frames) {
            let progress = Float(i) / Float(frames)
            let freq = start * pow(end / start, progress)
            phase += 2 * .pi * freq * dt
            let env = sin(.pi * (Float(i) / Float(frames)))
            let t = Float(i) * dt
            let release: Float = totalT - t < 0.04 ? max(0, (totalT - t) / 0.04) : 1
            data[i] = sin(phase) * volume * env * release
        }
        return buffer
    }

    private func sequence(notes: [Float], perNote: TimeInterval, volume: Float) -> AVAudioPCMBuffer {
        let totalFrames = AVAudioFrameCount(sampleRate * perNote * Double(notes.count))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames)!
        buffer.frameLength = totalFrames
        let data = buffer.floatChannelData![0]
        let perFrames = Int(sampleRate * perNote)
        for (idx, freq) in notes.enumerated() {
            let start = idx * perFrames
            for j in 0..<perFrames {
                let t = Float(j) / Float(sampleRate)
                let env = exp(-8 * t) * (t < 0.003 ? t / 0.003 : 1)
                let sample = sin(2 * .pi * freq * t) * volume * env
                data[start + j] = sample
            }
        }
        return buffer
    }

    // MARK: - Machine sounds
    private func makeBuffer(seconds: TimeInterval) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        return buffer
    }

    private func synthPrinter() -> AVAudioPCMBuffer {
        let chirpCount = 5
        let chirpDur: TimeInterval = 0.055
        let gapDur: TimeInterval = 0.028
        let total = (chirpDur + gapDur) * Double(chirpCount) + 0.18
        let buffer = makeBuffer(seconds: total)
        let data = buffer.floatChannelData![0]
        let perFrames = Int(sampleRate * chirpDur)
        let gapFrames = Int(sampleRate * gapDur)
        for c in 0..<chirpCount {
            let start = c * (perFrames + gapFrames)
            let baseFreq: Float = 540 + Float(c % 2) * 280
            for j in 0..<perFrames {
                let t = Float(j) / Float(sampleRate)
                let sq: Float = sin(2 * .pi * baseFreq * t) > 0 ? 1 : -1
                let env: Float = sin(.pi * Float(j) / Float(perFrames))
                data[start + j] = sq * env * 0.16
            }
        }
        let whirStart = chirpCount * (perFrames + gapFrames)
        let whirFrames = Int(sampleRate * 0.18)
        for j in 0..<whirFrames where whirStart + j < Int(buffer.frameLength) {
            let t = Float(j) / Float(sampleRate)
            let env = exp(-8 * t)
            let hum = sin(2 * .pi * 110 * t) * 0.06 + Float.random(in: -1...1, using: &GameRandom.shared) * 0.04
            data[whirStart + j] = hum * env
        }
        return buffer
    }

    private func synthFax() -> AVAudioPCMBuffer {
        let segments: [(freq: Float, dur: TimeInterval, gapAfter: TimeInterval)] = [
            (1100, 0.16, 0.05),
            (2100, 0.18, 0.05),
            (1500, 0.14, 0.04),
            (2400, 0.22, 0.0)
        ]
        let total = segments.reduce(0.0) { $0 + $1.dur + $1.gapAfter }
        let buffer = makeBuffer(seconds: total)
        let data = buffer.floatChannelData![0]
        var offset = 0
        for seg in segments {
            let segFrames = Int(sampleRate * seg.dur)
            for j in 0..<segFrames {
                let t = Float(j) / Float(sampleRate)
                let durF = Float(seg.dur)
                let fadeIn: Float = 0.012
                let fadeOut: Float = 0.025
                let env: Float
                if t < fadeIn { env = t / fadeIn }
                else if t > durF - fadeOut { env = max(0, (durF - t) / fadeOut) }
                else { env = 1 }
                let wobble: Float = sin(2 * .pi * 14 * t) * 6
                data[offset + j] = sin(2 * .pi * (seg.freq + wobble) * t) * 0.22 * env
            }
            offset += segFrames + Int(sampleRate * seg.gapAfter)
        }
        return buffer
    }

    private func synthPageFlip() -> AVAudioPCMBuffer {
        let total: TimeInterval = 0.55
        let buffer = makeBuffer(seconds: total)
        let data = buffer.floatChannelData![0]
        let frames = Int(buffer.frameLength)
        for i in 0..<frames { data[i] = 0 }

        let crackleCount = 50
        for _ in 0..<crackleCount {
            let startFrame = Int.random(in: 0..<(frames - 256), using: &GameRandom.shared)
            let crackleLen = Int.random(in: Int(sampleRate * 0.003)...Int(sampleRate * 0.018), using: &GameRandom.shared)
            let amp = Float.random(in: 0.15...0.55, using: &GameRandom.shared)
            for j in 0..<crackleLen {
                let idx = startFrame + j
                if idx >= frames { break }
                let t = Float(j) / Float(crackleLen)
                let env: Float = sin(.pi * t)
                data[idx] += Float.random(in: -1...1, using: &GameRandom.shared) * env * amp
            }
        }

        var lp: Float = 0
        for i in 0..<frames {
            lp = 0.82 * lp + 0.18 * data[i]
            data[i] = (data[i] - lp) * 0.85
        }

        let fade: Float = 0.05
        let durF = Float(total)
        for i in 0..<frames {
            let t = Float(i) / Float(sampleRate)
            let env: Float
            if t < fade { env = t / fade }
            else if t > durF - fade { env = max(0, (durF - t) / fade) }
            else { env = 1 }
            data[i] *= env
        }
        return buffer
    }

    private func synthCollator() -> AVAudioPCMBuffer {
        let bursts = 4
        let burstDur: TimeInterval = 0.075
        let gapDur: TimeInterval = 0.05
        let total = (burstDur + gapDur) * Double(bursts)
        let buffer = makeBuffer(seconds: total)
        let data = buffer.floatChannelData![0]
        let perBurst = Int(sampleRate * burstDur)
        let perGap = Int(sampleRate * gapDur)
        var prev: Float = 0
        for b in 0..<bursts {
            let start = b * (perBurst + perGap)
            for j in 0..<perBurst {
                let env: Float = sin(.pi * Float(j) / Float(perBurst))
                let n = Float.random(in: -1...1, using: &GameRandom.shared)
                prev = 0.4 * n + 0.6 * prev
                data[start + j] = prev * env * 0.32
            }
        }
        return buffer
    }

    private func buildBackgroundLoop() -> AVAudioPCMBuffer {
        let bpm: Double = 108
        let beat = 60.0 / bpm / 2.0
        let bassPattern: [Float] = [
            130.81, 164.81, 130.81, 196.00,
            174.61, 220.00, 174.61, 261.63,
            155.56, 196.00, 155.56, 233.08,
            174.61, 220.00, 130.81, 164.81
        ]
        let leadPattern: [Float] = [
            0, 523.25, 0, 659.25,
            0, 698.46, 0, 783.99,
            0, 622.25, 0, 740.00,
            0, 698.46, 0, 587.33
        ]
        let frames = AVAudioFrameCount(sampleRate * beat * Double(bassPattern.count))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        let perFrames = Int(sampleRate * beat)
        for (idx, bassF) in bassPattern.enumerated() {
            let leadF = leadPattern[idx]
            let start = idx * perFrames
            let slotDur = Float(perFrames) / Float(sampleRate)
            let release: Float = 0.012   // fade each note's tail so it doesn't cut off with a click on phone speakers
            for j in 0..<perFrames {
                let t = Float(j) / Float(sampleRate)
                var env = exp(-6 * t) * (t < 0.005 ? t / 0.005 : 1)
                if t > slotDur - release { env *= max(0, (slotDur - t) / release) }
                let bass = sin(2 * .pi * bassF * t) * 0.12 * env
                let lead = leadF == 0 ? 0 : sin(2 * .pi * leadF * t) * 0.06 * env * 0.7
                data[start + j] = bass + lead
            }
        }
        return buffer
    }

    private func buildSunglassesAtNightLoop() -> AVAudioPCMBuffer {
        let bpm: Double = 100
        let sixteenth = 60.0 / bpm / 4.0
        let steps = 64

        let C2: Float = 65.41
        let G2: Float = 98.00
        let Eb2: Float = 77.78
        let Ab2: Float = 103.83 
        let F2: Float = 87.31
        let bassPattern: [Float] = [
            C2, 0, C2, 0, G2, 0, C2, 0,
            Eb2, 0, Eb2, 0, G2, 0, Eb2, 0,
            C2, 0, C2, 0, G2, 0, C2, 0,
            G2, 0, Eb2, 0, C2, 0, G2, 0,
            Ab2, 0, Ab2, 0, Eb2, 0, Ab2, 0,
            F2, 0, F2, 0, C2, 0, F2, 0,
            Ab2, 0, Ab2, 0, Eb2, 0, G2, 0,
            G2, 0, G2, 0, C2, 0, G2, 0
        ]
        let G5: Float  = 783.99
        let F5: Float  = 698.46
        let Eb5: Float = 622.25
        let D5: Float  = 587.33
        let C5: Float  = 523.25
        let Bb4: Float = 466.16
        let Ab4: Float = 415.30
        let Ab5: Float = 830.61
        let C6:  Float = 1046.50
        let leadPattern: [Float] = [
            0, G5, F5, Eb5, 0, D5, 0, C5,
            0, G5, F5, Eb5, 0, F5, 0, Eb5,
            0, G5, F5, Eb5, 0, D5, 0, Bb4,
            0, C5, 0, Eb5, 0, D5, C5, 0,
            
            Ab4, 0, C5, 0, Eb5, 0, Ab5, 0,
            G5, 0, F5, 0, Eb5, 0, C5, 0,
            Ab4, 0, C5, Eb5, 0, G5, Ab5, C6,
            0, Ab5, G5, 0, Eb5, 0, C5, 0
        ]

        let frames = AVAudioFrameCount(sampleRate * sixteenth * Double(steps))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        let perFrames = Int(sampleRate * sixteenth)

        for idx in 0..<steps {
            let bassF = bassPattern[idx]
            let leadF = leadPattern[idx]
            let start = idx * perFrames
            for j in 0..<perFrames {
                let t = Float(j) / Float(sampleRate)
                let env = exp(-5.5 * t) * (t < 0.005 ? t / 0.005 : 1)
                var bass: Float = 0
                if bassF > 0 {
                    let s = sin(2 * .pi * bassF * t) + 0.45 * sin(2 * .pi * bassF * 2 * t)
                    bass = tanh(s * 1.2) * 0.14 * env
                }
                var lead: Float = 0
                if leadF > 0 {
                    let phase = leadF * t
                    let saw1 = 2 * (phase - floor(phase + 0.5))
                    let saw2 = 2 * ((leadF * 1.005) * t - floor((leadF * 1.005) * t + 0.5))
                    lead = (saw1 + saw2) * 0.05 * env
                }
                var click: Float = 0
                if idx % 4 == 0 && j < Int(sampleRate * 0.012) {
                    let n = Float.random(in: -1...1, using: &GameRandom.shared)
                    let clickEnv = exp(-90 * t)
                    click = n * clickEnv * 0.06
                }
                data[start + j] = bass + lead + click
            }
        }
        return buffer
    }

    // MARK: - Voice
    @discardableResult
    private func speak(_ text: String, priority: Bool) -> TimeInterval {
        let now = CACurrentMediaTime()
        if !priority, now - lastSpeechTime < speechCooldown { return 0 }
        lastSpeechTime = now
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.pitchMultiplier = 0.55
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        utterance.volume = 1.0
        if priority { speech.stopSpeaking(at: .immediate) }
        speech.speak(utterance)
        return Double(text.count) * 0.08 + 0.4
    }
}

#if os(macOS)
// NSObject conformer for AVSpeechSynthesizer's @objc delegate, kept off
// SoundManager so the wasm build stays NSObject-free. Forwards speech
// start/stop to the owner's ducking on the main actor.
private final class SpeechDuckDelegate: NSObject, AVSpeechSynthesizerDelegate {
    weak var owner: SoundManager?
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in owner?.setDucked(true) }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in owner?.setDucked(false) }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in owner?.setDucked(false) }
    }
}
#endif
