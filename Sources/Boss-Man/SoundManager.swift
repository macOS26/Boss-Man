import AVFoundation
import Foundation

@MainActor
final class SoundManager {
    private let engine = AVAudioEngine()
    private let effectsPlayer = AVAudioPlayerNode()
    private let musicPlayer = AVAudioPlayerNode()
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
    private var lastSpeechTime: TimeInterval = 0
    private let speechCooldown: TimeInterval = 1.5
    private var musicEnabled = false

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(effectsPlayer)
        engine.attach(musicPlayer)
        engine.connect(effectsPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(musicPlayer, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.8
        do {
            try engine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }

    // MARK: - Public events

    func playDotBlip() {
        dotToggle.toggle()
        let freq: Float = dotToggle ? 988 : 1175 // alternating two-note "wakka"
        play(buffer: tone(frequency: freq, duration: 0.05, volume: 0.22))
    }

    func playPowerPellet() {
        play(buffer: sweep(from: 220, to: 660, duration: 0.45, volume: 0.35))
    }

    func playFootstep() {
        play(buffer: tone(frequency: 140, duration: 0.025, volume: 0.07, decay: 60))
    }

    func playCaptureBoss(streak: Int) {
        let base: Float = 440
        let arp: [Float] = [base, base * 1.5, base * 2, base * 3]
        let segDuration: TimeInterval = 0.08
        let buffer = sequence(notes: Array(arp.prefix(max(2, min(4, streak + 1)))),
                              perNote: segDuration,
                              volume: 0.35)
        play(buffer: buffer)
        speak(bossCaptureLines.randomElement() ?? "Yeah.", priority: false)
    }

    func playCaughtByBoss() {
        play(buffer: sweep(from: 330, to: 60, duration: 0.7, volume: 0.4))
        speak(caughtLines.randomElement() ?? "Yeah.", priority: true)
    }

    func playFishOrTreat() {
        play(buffer: sequence(notes: [1320, 1760, 2093], perNote: 0.08, volume: 0.3))
        speak(fishLines.randomElement() ?? "Mmm, yeah.", priority: false)
    }

    func playTpsDeliver() {
        play(buffer: sequence(notes: [660, 880, 1320], perNote: 0.12, volume: 0.35))
        speak(tpsLines.randomElement() ?? "Sounds great.", priority: false)
    }

    func playGameOver() {
        play(buffer: sequence(notes: [392, 311, 261, 196], perNote: 0.18, volume: 0.4))
        speak(gameOverLines.randomElement() ?? "Yeah.", priority: true)
    }

    func playMachine(named name: String) {
        switch name {
        case "Printer":  play(buffer: synthPrinter())
        case "Fax":      play(buffer: synthFax())
        case "Copy":     play(buffer: synthPageFlip())
        case "Collator": play(buffer: synthCollator())
        default:         playDotBlip()
        }
    }

    func playLevelStart() {
        play(buffer: sequence(notes: [523, 659, 784, 1046], perNote: 0.12, volume: 0.3))
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

    /// Dot-matrix perforation tear: rapid short "tk-tk-tk-tk" clicks.
    private func synthPageFlip() -> AVAudioPCMBuffer {
        let clickCount = 14
        let clickDur: TimeInterval = 0.008
        let gapDur: TimeInterval = 0.022
        let total = (clickDur + gapDur) * Double(clickCount)
        let buffer = makeBuffer(seconds: total)
        let data = buffer.floatChannelData![0]
        let perClick = Int(sampleRate * clickDur)
        let perGap = Int(sampleRate * gapDur)
        for c in 0..<clickCount {
            let start = c * (perClick + perGap)
            for j in 0..<perClick {
                let t = Float(j) / Float(sampleRate)
                let env: Float = exp(-180 * t)            // very fast decay → click
                let n = Float.random(in: -1...1)
                let tk = sin(2 * .pi * 1700 * t) * 0.55 + sin(2 * .pi * 3200 * t) * 0.25
                data[start + j] = (n * 0.5 + tk * 0.5) * env * 0.55
            }
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
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.78  // slow but not sluggish
        utterance.volume = 0.9
        utterance.pitchMultiplier = 0.86                            // deeper than default, still articulate
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.05
        if priority { speech.stopSpeaking(at: .immediate) }
        speech.speak(utterance)
    }
}
