import AVFoundation
import Foundation

@MainActor
final class SoundManager: NSObject, AVSpeechSynthesizerDelegate {
    private let engine = AVAudioEngine()
    private let effectsPlayer = AVAudioPlayerNode()
    private let musicPlayer = AVAudioPlayerNode()
    /// Dedicated player for the power-pellet bassline loop so we can
    /// stop() it instantly when blue mode ends — `effectsPlayer`
    /// queues buffers and can't cancel them mid-flight.
    private let bassPlayer = AVAudioPlayerNode()
    private var powerPelletBeatBuffer: AVAudioPCMBuffer?
    /// Synthesized PCM buffer cache. Every sound effect used to rebuild
    /// its waveform on each call — playFootstep alone fires ~7x/sec and
    /// allocated a fresh ~1100-sample buffer each time. Cache by string
    /// key so each effect is synthesized exactly once and reused.
    private var bufferCache: [String: AVAudioPCMBuffer] = [:]
    private let speech = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice? = SoundManager.pickBossVoice()

    private static func pickBossVoice() -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        // Filter out the legacy novelty voices that sound nothing like a human.
        let robotic = ["fred", "ralph", "bahh", "bells", "boing", "bubbles",
                       "cellos", "deranged", "good news", "hysterical",
                       "pipe organ", "trinoids", "whisper", "zarvox"]
        let usable = all.filter {
            let n = $0.name.lowercased()
            return !robotic.contains(where: { n.contains($0) })
        }
        let americanMale = usable.filter { $0.language == "en-US" && $0.gender == .male }
        let englishMale  = usable.filter { $0.language.hasPrefix("en") && $0.gender == .male }

        // 1) Best en-US male, premium > enhanced, preferring the Lumbergh-ish names.
        if let v = americanMale.first(where: { $0.quality == .premium && SoundManager.looksLumberghLike($0) }) { return v }
        if let v = americanMale.first(where: { $0.quality == .premium }) { return v }
        if let v = americanMale.first(where: { $0.quality == .enhanced && SoundManager.looksLumberghLike($0) }) { return v }
        if let v = americanMale.first(where: { $0.quality == .enhanced }) { return v }

        // 2) Any installed American male, compact OK only as a last resort.
        if let v = americanMale.first(where: { SoundManager.looksLumberghLike($0) }) { return v }
        if let v = americanMale.first { return v }

        // 3) Fall back to any English male, premium first.
        if let v = englishMale.first(where: { $0.quality == .premium }) { return v }
        if let v = englishMale.first(where: { $0.quality == .enhanced }) { return v }
        if let v = englishMale.first { return v }

        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Names of macOS voices whose timbre is closest to a slow American baritone.
    /// Ordered roughly by how deep / human they sound — Reed/Rocco/Tom first,
    /// Alex/Aaron as solid fallbacks, Fred deliberately excluded (too robotic).
    private static func looksLumberghLike(_ v: AVSpeechSynthesisVoice) -> Bool {
        let id = v.identifier.lowercased()
        let name = v.name.lowercased()
        let preferred = ["reed", "rocco", "tom", "aaron", "alex", "evan", "daniel"]
        return preferred.contains(where: { id.contains($0) || name.contains($0) })
    }

    // Phonetic spellings and explicit pauses (commas / ellipses) coax AVSpeech
    // into a slower, more uneven Lumbergh cadence.
    // Each section uses a vocabulary that does NOT overlap with the others, so
    // the player can mentally pair a phrase with its event.
    private let bossCaptureLines = [
        "Aw, geez.",
        "Hey now.",
        "Whoaaa.",
        "Ouch."
    ]
    private let caughtLines = [
        "TPS reports.",
        "Cover sheet please.",
        "Saturday's the day.",
        "Memo, anyone?"
    ]
    private let fishLines = [
        "Terrific.",
        "Fantastic.",
        "Swell.",
        "Niiice."
    ]
    private let tpsLines = [
        "Atta boy.",
        "Well done.",
        "Excellent.",
        "Solid work."
    ]
    private let gameOverLines = [
        "Outta here, pal.",
        "Pack it up.",
        "Buh-bye.",
        "Security, escort him."
    ]
    private let levelStartLines = [
        "Hi there.",
        "What's happening?",
        "New floor.",
        "Welcome back."
    ]
    private let sampleRate: Double = 44100
    private let format: AVAudioFormat
    private var musicBuffer: AVAudioPCMBuffer?

    private var dotToggle = false
    /// Counter for the multi-stage dot ladder: 12 dots at the original
    /// pitch pair, 12 dots two scale-degrees up, 12 dots four up,
    /// 6 dots two below original, then cycle. Reset to 0 after a
    /// 1.5s pause in eating.
    private var dotsEatenInCycle: Int = 0
    private var lastDotEatTime: TimeInterval = 0
    
    /// Each stage's (low, high) toggle pair, in Hz, walking the
    /// C-major scale up then briefly below.
    private let dotStages: [(Float, Float)] = [
        (988.00, 1174.66),  // B5 / D6  — original
        (1396.91, 1174.66), // F6 / D6  — up 2 scale-degrees
        (1396.91, 1760.00), // F6 / A6  — up 4 scale-degrees
        (783.99, 987.77)    // G5 / B5  — 2 below original
    ]
    private let dotsPerStage: [Int] = [4, 2, 4, 2]
    private var lastSpeechTime: TimeInterval = 0
    private let speechCooldown: TimeInterval = 1.5
    
    private var musicEnabled = false

    private let normalEffectsVolume: Float = 1.0
    private let duckedEffectsVolume: Float = 0.25
    private let normalMusicVolume: Float = 1.0
    private let duckedMusicVolume: Float = 0.18

    override init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        super.init()
        engine.attach(effectsPlayer)
        engine.attach(musicPlayer)
        engine.attach(bassPlayer)
        engine.connect(effectsPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(musicPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(bassPlayer, to: engine.mainMixerNode, format: format)
        bassPlayer.volume = 0.9
        // Lower mixer headroom so speech + music + effects can't sum past
        // full-scale and clip — clipping is what's audible as "crackle"
        // when the speech synthesizer's audio unit kicks in alongside ours.
        engine.mainMixerNode.outputVolume = 0.55
        effectsPlayer.volume = normalEffectsVolume
        musicPlayer.volume = normalMusicVolume
        speech.delegate = self
        // Give the output audio unit a larger render slice so the HAL has
        // more slack before it logs an overload (and audibly crackles)
        // when AVSpeechSynthesizer spins up its own audio path.
        let outputAU = engine.outputNode.auAudioUnit
        outputAU.maximumFramesToRender = max(outputAU.maximumFramesToRender, 4096)
        do {
            try engine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }

    // MARK: - Speech ducking

    private func setDucked(_ ducked: Bool) {
        effectsPlayer.volume = ducked ? duckedEffectsVolume : normalEffectsVolume
        musicPlayer.volume = ducked ? duckedMusicVolume : normalMusicVolume
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.setDucked(true) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.setDucked(false) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.setDucked(false) }
    }

    // MARK: - Public events

    /// Returns the cached buffer for `key`, building it via `build` on
    /// first request. All sound effects are deterministic enough to be
    /// safely reused — trades a small amount of variation for huge CPU
    /// savings (~7 footstep + dot-blip syntheses per second).
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

        // Find which stage the current dot belongs to.
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
        let pair = dotStages[stageIndex]
        let freq = dotToggle ? pair.0 : pair.1
        let key = "dot-\(stageIndex)-\(dotToggle ? "lo" : "hi")"
        play(buffer: cached(key) { self.tone(frequency: freq, duration: 0.05, volume: 0.22) })

        dotsEatenInCycle += 1
    }

    func playPowerPellet() {
        play(buffer: cached("powerPellet") { self.sweep(from: 220, to: 660, duration: 0.45, volume: 0.35) })
    }

    func playFootstep() {
        play(buffer: cached("footstep") { self.tone(frequency: 140, duration: 0.025, volume: 0.07, decay: 60) })
    }

    func playCaptureBoss(streak: Int) {
        let base: Float = 440
        let arp: [Float] = [base, base * 1.5, base * 2, base * 3]
        let count = max(2, min(4, streak + 1))
        play(buffer: cached("captureBoss-\(count)") {
            self.sequence(notes: Array(arp.prefix(count)), perNote: 0.08, volume: 0.35)
        })
        speak(bossCaptureLines.randomElement() ?? "Yeah.", priority: false)
    }

    func playCaughtByBoss() {
        play(buffer: cached("caughtByBoss") { self.sweep(from: 330, to: 60, duration: 0.7, volume: 0.4) })
        speak(caughtLines.randomElement() ?? "Ohh, yeah.", priority: true)
    }

    func playFishOrTreat() {
        play(buffer: cached("fishOrTreat") { self.sequence(notes: [1320, 1760, 2093], perNote: 0.08, volume: 0.3) })
        speak(fishLines.randomElement() ?? "Mmm, yeah.", priority: false)
    }

    func playTpsDeliver() {
        play(buffer: cached("tpsDeliver") { self.sequence(notes: [660, 880, 1320], perNote: 0.12, volume: 0.35) })
        speak(tpsLines.randomElement() ?? "Sounds great.", priority: false)
    }

    func playGameOver() {
        play(buffer: cached("gameOver") { self.sequence(notes: [392, 311, 261, 196], perNote: 0.18, volume: 0.4) })
        speak(gameOverLines.randomElement() ?? "yeah right!", priority: true)
    }

    func playMachine(named name: String) {
        switch name {
        case "Printer":  play(buffer: cached("printer") { self.synthPrinter() })
        case "Fax":      play(buffer: cached("fax") { self.synthFax() })
        case "Copy":     play(buffer: cached("pageFlip") { self.synthPageFlip() })
        case "Collator": play(buffer: cached("collator") { self.synthCollator() })
        default:         playDotBlip()
        }
    }

    /// Quiet, distinct "distant" cue when a roaming traveler enters the floor.
    func playTravelerArrive(_ which: TravelerSound) {
        switch which {
        case .water:
            play(buffer: cached("trav.water") { self.sweep(from: 520, to: 180, duration: 0.55, volume: 0.14) })
        case .glaze:
            play(buffer: cached("trav.glaze") { self.sequence(notes: [2093, 2637, 3136], perNote: 0.07, volume: 0.13) })
        case .crunch:
            play(buffer: cached("trav.crunch") { self.synthFiltered(noiseSeconds: 0.35, bursts: 12, volume: 0.18) })
        case .alienBleep:
            play(buffer: cached("trav.alienBleep") { self.sequence(notes: [880, 1320, 1760, 1320], perNote: 0.06, volume: 0.16) })
        case .jelly:
            play(buffer: cached("trav.jelly") { self.sweep(from: 660, to: 990, duration: 0.7, volume: 0.12) })
        case .crispTap:
            play(buffer: cached("trav.crispTap") { self.tone(frequency: 1568, duration: 0.12, volume: 0.18, decay: 22) })
        case .bellDing:
            play(buffer: cached("trav.bellDing") { self.sequence(notes: [1568, 2093], perNote: 0.22, volume: 0.16) })
        case .radioStatic:
            play(buffer: cached("trav.radioStatic") { self.synthFiltered(noiseSeconds: 0.6, bursts: 1, volume: 0.10) })
        case .magicChime:
            play(buffer: cached("trav.magicChime") { self.sequence(notes: [1318, 1976, 2637, 3520], perNote: 0.07, volume: 0.13) })
        case .ufoWhoosh:
            play(buffer: cached("trav.ufoWhoosh") { self.sweep(from: 1760, to: 220, duration: 0.65, volume: 0.13) })
        case .eyeDrone:
            play(buffer: cached("trav.eyeDrone") { self.tone(frequency: 196, duration: 0.8, volume: 0.18, decay: 2) })
        }
    }

    /// Filtered-noise bed used by crunch/static traveler cues.
    /// `bursts == 1` → continuous shaped noise (radio); higher counts → granular crackle.
    private func synthFiltered(noiseSeconds total: TimeInterval, bursts: Int, volume: Float) -> AVAudioPCMBuffer {
        let buffer = makeBuffer(seconds: total)
        let data = buffer.floatChannelData![0]
        let frames = Int(buffer.frameLength)
        for i in 0..<frames { data[i] = 0 }
        if bursts <= 1 {
            for i in 0..<frames {
                data[i] = Float.random(in: -1...1)
            }
        } else {
            for _ in 0..<bursts {
                let startFrame = Int.random(in: 0..<max(1, frames - 1024))
                let len = Int.random(in: Int(sampleRate * 0.01)...Int(sampleRate * 0.04))
                for j in 0..<len where startFrame + j < frames {
                    let t = Float(j) / Float(len)
                    data[startFrame + j] += Float.random(in: -1...1) * sin(.pi * t)
                }
            }
        }
        // One-pole low-pass → subtract to brighten, gives a thin, distant timbre.
        var lp: Float = 0
        for i in 0..<frames {
            lp = 0.78 * lp + 0.22 * data[i]
            data[i] = (data[i] - lp) * volume
        }
        // Fade in/out so it doesn't pop.
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

    func playLevelStart() {
        play(buffer: cached("levelStart") { self.sequence(notes: [523, 659, 784, 1046], perNote: 0.12, volume: 0.3) })
        speak(levelStartLines.randomElement() ?? "Yeah.", priority: false)
    }

    func startBackgroundMusic() {
        guard !musicEnabled else { return }
        musicEnabled = true
        let buffer = musicBuffer ?? buildBackgroundLoop()
        musicBuffer = buffer
        musicPlayer.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        if !musicPlayer.isPlaying { musicPlayer.play() }
    }

    func stopBackgroundMusic() {
        musicEnabled = false
        musicPlayer.stop()
    }

    // MARK: - Power-pellet beat

    /// Starts the power-pellet bassline looping on its own player. The
    /// dedicated bassPlayer lets us cancel the loop instantly via
    /// stopPowerPelletBass() — without it, queued buffers on the
    /// shared effectsPlayer continue playing for up to a full pattern
    /// cycle after blue mode ends, sounding out of sync once the
    /// bosses return to normal.
    func startPowerPelletBass() {
        if powerPelletBeatBuffer == nil {
            powerPelletBeatBuffer = buildPowerPelletBeat()
        }
        guard let buffer = powerPelletBeatBuffer else { return }
        bassPlayer.stop()
        bassPlayer.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        if !bassPlayer.isPlaying { bassPlayer.play() }
    }

    func stopPowerPelletBass() {
        bassPlayer.stop()
    }

    private func buildPowerPelletBeat() -> AVAudioPCMBuffer {
        // Original pop-punk bass groove. 16 sixteenth-note slots over
        // 2 seconds (120 BPM) with root pulses on E2, octave jumps to
        // E3 for energy, walking-up motion through G/A/B, and a few
        // rests to give it swing. Synthesis is fundamental + a few
        // harmonics run through soft tanh saturation for a gritty
        // P-bass-through-an-overdrive timbre.
        let duration: TimeInterval = 2.0
        let buffer = makeBuffer(seconds: duration)
        let data = buffer.floatChannelData![0]
        let frames = Int(buffer.frameLength)

        let E2: Float = 82.41
        let E3: Float = 164.81
        let G2: Float = 98.00
        let A2: Float = 110.00
        let B2: Float = 123.47
        let _: Float = 0   // marker for readability of the rest

        // -- Original riff. 16 slots, each ~125ms. Rests = 0. --
        let pattern: [Float] = [
            E2, E2, 0,  E3,  E2, 0,  G2, G2,
            E2, 0,  A2, A2,  G2, 0,  B2, E3
        ]
        let slotFrames = frames / pattern.count
        let attack: Float = 0.005

        for (slot, freq) in pattern.enumerated() {
            let startFrame = slot * slotFrames
            guard freq > 0 else {
                for j in 0..<slotFrames where startFrame + j < frames {
                    data[startFrame + j] = 0
                }
                continue
            }
            for j in 0..<slotFrames where startFrame + j < frames {
                let t = Float(j) / Float(sampleRate)
                let env: Float
                if t < attack {
                    env = t / attack
                } else {
                    // Punchy pluck — quick attack, fast decay, short
                    // gap before the next note so the groove reads
                    // rhythmically rather than as a sustained drone.
                    env = exp(-3.8 * (t - attack))
                }
                // Layer fundamental + 2nd + 3rd harmonics, then run
                // through tanh saturation for the slightly clipped
                // "bass-through-an-overdrive" punk texture.
                let f1 = sin(2 * .pi * freq * t)
                let f2 = sin(2 * .pi * freq * 2 * t) * 0.35
                let f3 = sin(2 * .pi * freq * 3 * t) * 0.12
                let raw = (f1 + f2 + f3) * 1.8 * env
                data[startFrame + j] = tanh(raw) * 0.34
            }
        }
        return buffer
    }

    /// Star-Trek-style transporter shimmer used during the boss spawn /
    /// respawn fade. Pairs an ascending sweep with a descending sweep
    /// plus high-frequency sparkle, bell-enveloped over the fade window.
    func playTeleport() {
        play(buffer: cached("teleport") { self.buildTeleport() })
    }

    private func buildTeleport() -> AVAudioPCMBuffer {
        let duration: TimeInterval = 1.5
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
            let env = sin(.pi * progress) // bell — 0 at edges, 1 mid
            let shimmer = Float.random(in: -1...1) * 0.06
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
        for i in 0..<Int(frames) {
            let t = Float(i) / Float(sampleRate)
            let env: Float
            if t < attack {
                env = t / attack
            } else {
                env = exp(-decay * (t - attack))
            }
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
            let env = sin(.pi * (Float(i) / Float(frames))) // bell envelope
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

    /// Inkjet-style mechanical chirps with a quick whir tail.
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
            let baseFreq: Float = 540 + Float(c % 2) * 280   // alternate back-and-forth head pass
            for j in 0..<perFrames {
                let t = Float(j) / Float(sampleRate)
                let sq: Float = sin(2 * .pi * baseFreq * t) > 0 ? 1 : -1   // square buzz
                let env: Float = sin(.pi * Float(j) / Float(perFrames))
                data[start + j] = sq * env * 0.16
            }
        }
        // Trailing motor whir (low broadband hum)
        let whirStart = chirpCount * (perFrames + gapFrames)
        let whirFrames = Int(sampleRate * 0.18)
        for j in 0..<whirFrames where whirStart + j < Int(buffer.frameLength) {
            let t = Float(j) / Float(sampleRate)
            let env = exp(-8 * t)
            let hum = sin(2 * .pi * 110 * t) * 0.06 + Float.random(in: -1...1) * 0.04
            data[whirStart + j] = hum * env
        }
        return buffer
    }

    /// Fax handshake — distinct CNG / CED / training tones with small gaps,
    /// not a continuous warble.
    private func synthFax() -> AVAudioPCMBuffer {
        let segments: [(freq: Float, dur: TimeInterval, gapAfter: TimeInterval)] = [
            (1100, 0.16, 0.05),    // calling tone
            (2100, 0.18, 0.05),    // answer tone
            (1500, 0.14, 0.04),
            (2400, 0.22, 0.0)      // training tail
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
                let wobble: Float = sin(2 * .pi * 14 * t) * 6  // gentle, not gurgling
                data[offset + j] = sin(2 * .pi * (seg.freq + wobble) * t) * 0.22 * env
            }
            offset += segFrames + Int(sampleRate * seg.gapAfter)
        }
        return buffer
    }

    /// Flattening a crinkled piece of paper — sparse random crackles, high-passed.
    private func synthPageFlip() -> AVAudioPCMBuffer {
        let total: TimeInterval = 0.55
        let buffer = makeBuffer(seconds: total)
        let data = buffer.floatChannelData![0]
        let frames = Int(buffer.frameLength)
        for i in 0..<frames { data[i] = 0 }

        // Random short crackles at irregular intervals.
        let crackleCount = 50
        for _ in 0..<crackleCount {
            let startFrame = Int.random(in: 0..<(frames - 256))
            let crackleLen = Int.random(in: Int(sampleRate * 0.003)...Int(sampleRate * 0.018))
            let amp = Float.random(in: 0.15...0.55)
            for j in 0..<crackleLen {
                let idx = startFrame + j
                if idx >= frames { break }
                let t = Float(j) / Float(crackleLen)
                let env: Float = sin(.pi * t)
                data[idx] += Float.random(in: -1...1) * env * amp
            }
        }

        // High-pass: subtract a one-pole low-pass to brighten the noise.
        var lp: Float = 0
        for i in 0..<frames {
            lp = 0.82 * lp + 0.18 * data[i]
            data[i] = (data[i] - lp) * 0.85
        }

        // Overall fade in / out so the sample doesn't pop.
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

    /// Four short paper-shuffle bursts simulating a collator stacking pages.
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
                let n = Float.random(in: -1...1)
                prev = 0.4 * n + 0.6 * prev
                data[start + j] = prev * env * 0.32
            }
        }
        return buffer
    }

    private func buildBackgroundLoop() -> AVAudioPCMBuffer {
        // Simple two-bar walking-bass loop at ~110 bpm (8 eighths per bar).
        let bpm: Double = 108
        let beat = 60.0 / bpm / 2.0 // 8th note
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
            for j in 0..<perFrames {
                let t = Float(j) / Float(sampleRate)
                let env = exp(-6 * t) * (t < 0.005 ? t / 0.005 : 1)
                let bass = sin(2 * .pi * bassF * t) * 0.12 * env
                let lead = leadF == 0 ? 0 : sin(2 * .pi * leadF * t) * 0.06 * env * 0.7
                data[start + j] = bass + lead
            }
        }
        return buffer
    }

    // MARK: - Voice

    private func speak(_ text: String, priority: Bool) {
        let now = CACurrentMediaTime()
        if !priority, now - lastSpeechTime < speechCooldown { return }
        lastSpeechTime = now
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.70  // slower drawl
        utterance.volume = 0.9
        utterance.pitchMultiplier = 0.80                            // deeper baritone
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.06
        if priority { speech.stopSpeaking(at: .immediate) }
        speech.speak(utterance)
    }
}
