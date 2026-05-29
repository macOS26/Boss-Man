import SpriteKit
import KitABI
import Foundation       // exp / sin / pow / tanh via wasi-libc libm

// Wasm SoundManager. Mirrors the public surface of bossman-apple's SoundManager
// so call sites compile unchanged. Sound effects are SYNTHESIZED the same way as
// bossman-apple (tone / sweep / sequence / machine synths), uploaded to the
// framework as Float32 PCM via snd_create_pcm, and played with snd_play. The
// background music loop and the gold-disc bass line are synthesized the same
// way. Voice lines go through tts_speak (Web Speech API).
final class SoundManager {
    enum MusicTheme { case normal, mib }

    private let speechRate:   Float = 0.85
    private let speechPitch:  Float = 0.55
    private let speechVolume: Float = 1.0   // full; the runtime ducks music/SFX while speaking

    private var lastIndex: [String: Int] = [:]

    private let sampleRate: Int32 = 44100
    private let normalMusicVolume: Float = 30   // snd_play uses 0..100
    private let effectVolume: Float = 60
    private var currentTheme: MusicTheme = .normal

    // MARK: - Lifecycle

    init() {
        // Preference chain: Rocko -> Ralph -> Fred -> Daniel (the picker takes the
        // first one actually present, so Chrome gets Rocko, Safari falls to Ralph
        // since Rocko isn't exposed there). The rest are deeper safety fallbacks.
        let preferred = "rocko,ralph,fred,daniel,alex,david,mark,reed,grandpa,junior,google us english"
        let robotic   = "bahh,bells,boing,bubbles,cellos,deranged,good news,hysterical,pipe organ,trinoids,whisper,zarvox,albert,eddy"
        let female    = "samantha,karen,tessa,moira,ava,susan,victoria,allison,veena,fiona,kate,kathy,sandy,whisper,paulina,monica,marie,zira,hazel,heather,jenny,aria,catherine,clara,linda,sara,google uk english female,google us english female"
        callCSV(preferred, tts_set_preferred_voices)
        callCSV(robotic,   tts_set_robotic_voices)
        callCSV(female,    tts_set_female_voices)
    }

    private func callCSV(_ s: String, _ f: (UnsafePointer<CChar>?, Int32) -> Void) {
        let bytes = Array(s.utf8)
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            base.withMemoryRebound(to: CChar.self, capacity: buf.count) { cBase in
                f(cBase, Int32(buf.count))
            }
        }
    }

    // MARK: - Sound effects (synthesized, matching bossman-apple recipes)

    // Pac-Man-style ascending dot blip; cycles through 4 stages of [4,2,4,2]
    // dots, toggling high/low each bite (bossman-apple SoundManager.playDotBlip).
    private var dotToggle = false
    private var dotsEatenInCycle = 0
    private let dotStages: [(Float, Float)] = [
        (988.00, 1174.66), (1396.91, 1174.66), (1396.91, 1760.00), (783.99, 987.77),
    ]
    private let mibDotStages: [(Float, Float)] = [
        (523.25, 622.25), (622.25, 783.99), (783.99, 1046.50), (932.33, 783.99),
    ]
    private let dotsPerStage: [Int] = [4, 2, 4, 2]

    func playDotBlip() {
        let cycleLen = dotsPerStage.reduce(0, +)
        let pos = dotsEatenInCycle % cycleLen
        var stageIndex = 0, threshold = 0
        for (i, c) in dotsPerStage.enumerated() {
            threshold += c
            if pos < threshold { stageIndex = i; break }
        }
        dotToggle.toggle()
        let mib = currentTheme == .mib
        let pair = mib ? mibDotStages[stageIndex] : dotStages[stageIndex]
        let freq = dotToggle ? pair.0 : pair.1
        let vol: Float = mib ? 0.11 : 0.22
        playEffect("dot.\(stageIndex).\(dotToggle).\(mib)") {
            self.tone(frequency: freq, duration: 0.05, volume: vol)
        }
        dotsEatenInCycle += 1
    }

    func playGoldDisc()       { playEffect("goldDisc")       { self.sweep(from: 220, to: 660,  duration: 0.45, volume: 0.35) } }
    func playWaterGunPickup() { playEffect("waterGunPickup") { self.sweep(from: 440, to: 1320, duration: 0.3,  volume: 0.30) } }
    func playWaterGunShoot()  { playEffect("waterGunShoot")  { self.sweep(from: 880, to: 440,  duration: 0.08, volume: 0.25) } }
    func playWaterGunSplash() { playEffect("waterGunSplash") { self.sweep(from: 660, to: 220,  duration: 0.3,  volume: 0.35) } }
    func playFootstep()       { playEffect("footstep")       { self.tone(frequency: 140, duration: 0.025, volume: 0.07, decay: 60) } }
    func playTeleport()       { playEffect("teleport")       { self.sweep(from: 200, to: 1200, duration: 0.18, volume: 0.20) } }

    func playLevelStart() {
        playEffect("levelStart") { self.sequence(notes: [523, 659, 784, 1046], perNote: 0.12, volume: 0.30) }
        speak(.levelStart)
    }
    func playGameOver() {
        playEffect("gameOver") { self.sequence(notes: [392, 311, 261, 196], perNote: 0.18, volume: 0.40) }
        speak(.gameOver)
    }
    func playCaptureBoss(streak: Int = 0) {
        let base: Float = 440
        let arp: [Float] = [base, base * 1.5, base * 2, base * 3]
        let count = max(2, min(4, streak + 1))
        playEffect("captureBoss.\(count)") {
            self.sequence(notes: Array(arp.prefix(count)), perNote: 0.08, volume: 0.35)
        }
        speak(.bossCapture)
    }
    func playCaughtByBoss() {
        playEffect("caughtByBoss") { self.sweep(from: 330, to: 60, duration: 0.7, volume: 0.40) }
        speak(.caught)
    }
    func playFishOrTreat() {
        playEffect("fishOrTreat") { self.sequence(notes: [1320, 1760, 2093], perNote: 0.08, volume: 0.30) }
        speak(.fish)
    }
    func playTpsDeliver() {
        playEffect("tpsDeliver") { self.sequence(notes: [660, 880, 1320], perNote: 0.12, volume: 0.35) }
        speak(.tps)
    }
    func playTpsMissingItems(_ items: [String]) {
        playEffect("tpsDeliver") { self.sequence(notes: [660, 880, 1320], perNote: 0.12, volume: 0.35) }
        guard !items.isEmpty else { return }
        speak(text: "Still missing: \(items.joined(separator: ", ")).", priority: true)
    }
    func playMachine(named name: String) {
        switch name {
        case "printer": playEffect("printer")  { self.synthPrinter()  }
        case "fax":     playEffect("fax")       { self.synthFax()      }
        case "binder":  playEffect("collator")  { self.synthCollator() }
        default:        playEffect("pageFlip")  { self.synthPageFlip() }
        }
    }

    func playTravelerArrive(_ which: TravelerSound) {
        switch which {
        case .water:       playEffect("tr.water")       { self.sweep(from: 520, to: 180, duration: 0.55, volume: 0.14) }
        case .glaze:       playEffect("tr.glaze")       { self.sequence(notes: [2093, 2637, 3136], perNote: 0.07, volume: 0.13) }
        case .crunch:      playEffect("tr.crunch")      { self.synthFiltered(noiseSeconds: 0.35, bursts: 12, volume: 0.18) }
        case .alienBleep:  playEffect("tr.alienBleep")  { self.sequence(notes: [880, 1320, 1760, 1320], perNote: 0.06, volume: 0.16) }
        case .jelly:       playEffect("tr.jelly")       { self.sweep(from: 660, to: 990, duration: 0.7, volume: 0.12) }
        case .crispTap:    playEffect("tr.crispTap")    { self.tone(frequency: 1568, duration: 0.12, volume: 0.18, decay: 22) }
        case .bellDing:    playEffect("tr.bellDing")    { self.sequence(notes: [1568, 2093], perNote: 0.22, volume: 0.16) }
        case .radioStatic: playEffect("tr.radioStatic") { self.synthFiltered(noiseSeconds: 0.6, bursts: 1, volume: 0.10) }
        case .magicChime:  playEffect("tr.magicChime")  { self.sequence(notes: [1318, 1976, 2637, 3520], perNote: 0.07, volume: 0.13) }
        case .ufoWhoosh:   playEffect("tr.ufoWhoosh")   { self.sweep(from: 1760, to: 220, duration: 0.65, volume: 0.13) }
        case .eyeDrone:    playEffect("tr.eyeDrone")    { self.tone(frequency: 196, duration: 0.8, volume: 0.18, decay: 2) }
        case .bigEye:      playEffect("tr.bigEye")      { self.sequence(notes: [659, 880, 1175, 1568], perNote: 0.07, volume: 0.14) }
        }
    }

    // Synthesize once, upload as PCM, cache the buffer handle, then play.
    private var effectBuffers: [String: Int32] = [:]
    private func playEffect(_ key: String, _ build: () -> [Float]) {
        let handle = effectBuffers[key] ?? {
            let h = uploadPCM(build())
            effectBuffers[key] = h
            return h
        }()
        guard handle > 0 else { return }
        _ = snd_play(handle, effectVolume, 0)
    }

    // MARK: - Synthesis primitives (verbatim recipes from bossman-apple)

    private func samples(seconds: TimeInterval) -> [Float] {
        [Float](repeating: 0, count: Int(Double(sampleRate) * seconds))
    }

    private func tone(frequency: Float, duration: TimeInterval, volume: Float, decay: Float = 12) -> [Float] {
        let frames = Int(Double(sampleRate) * duration)
        var out = [Float](repeating: 0, count: frames)
        let attack: Float = 0.004
        for i in 0..<frames {
            let t = Float(i) / Float(sampleRate)
            let env: Float = t < attack ? t / attack : exp(-decay * (t - attack))
            out[i] = sin(2 * .pi * frequency * t) * volume * env
        }
        return out
    }

    private func sweep(from start: Float, to end: Float, duration: TimeInterval, volume: Float) -> [Float] {
        let frames = Int(Double(sampleRate) * duration)
        var out = [Float](repeating: 0, count: frames)
        var phase: Float = 0
        let dt = 1.0 / Float(sampleRate)
        let totalT = Float(duration)
        for i in 0..<frames {
            let progress = Float(i) / Float(frames)
            let freq = start * pow(end / start, progress)
            phase += 2 * .pi * freq * dt
            let env = sin(.pi * (Float(i) / Float(frames)))
            let t = Float(i) * dt
            let release: Float = totalT - t < 0.04 ? max(0, (totalT - t) / 0.04) : 1
            out[i] = sin(phase) * volume * env * release
        }
        return out
    }

    private func sequence(notes: [Float], perNote: TimeInterval, volume: Float) -> [Float] {
        let perFrames = Int(Double(sampleRate) * perNote)
        var out = [Float](repeating: 0, count: perFrames * notes.count)
        for (idx, freq) in notes.enumerated() {
            let start = idx * perFrames
            for j in 0..<perFrames {
                let t = Float(j) / Float(sampleRate)
                let env = exp(-8 * t) * (t < 0.003 ? t / 0.003 : 1)
                out[start + j] = sin(2 * .pi * freq * t) * volume * env
            }
        }
        return out
    }

    // MARK: - Machine + texture synths

    private func synthPrinter() -> [Float] {
        let chirpCount = 5
        let chirpDur: TimeInterval = 0.055
        let gapDur: TimeInterval = 0.028
        let total = (chirpDur + gapDur) * Double(chirpCount) + 0.18
        var out = samples(seconds: total)
        let frames = out.count
        let perFrames = Int(Double(sampleRate) * chirpDur)
        let gapFrames = Int(Double(sampleRate) * gapDur)
        for c in 0..<chirpCount {
            let start = c * (perFrames + gapFrames)
            let baseFreq: Float = 540 + Float(c % 2) * 280
            for j in 0..<perFrames where start + j < frames {
                let t = Float(j) / Float(sampleRate)
                let sq: Float = sin(2 * .pi * baseFreq * t) > 0 ? 1 : -1
                let env: Float = sin(.pi * Float(j) / Float(perFrames))
                out[start + j] = sq * env * 0.16
            }
        }
        let whirStart = chirpCount * (perFrames + gapFrames)
        let whirFrames = Int(Double(sampleRate) * 0.18)
        for j in 0..<whirFrames where whirStart + j < frames {
            let t = Float(j) / Float(sampleRate)
            let env = exp(-8 * t)
            let hum = sin(2 * .pi * 110 * t) * 0.06 + Float.random(in: -1...1) * 0.04
            out[whirStart + j] = hum * env
        }
        return out
    }

    private func synthFax() -> [Float] {
        let segments: [(freq: Float, dur: TimeInterval, gapAfter: TimeInterval)] = [
            (1100, 0.16, 0.05), (2100, 0.18, 0.05), (1500, 0.14, 0.04), (2400, 0.22, 0.0),
        ]
        let total = segments.reduce(0.0) { $0 + $1.dur + $1.gapAfter }
        var out = samples(seconds: total)
        let frames = out.count
        var offset = 0
        for seg in segments {
            let segFrames = Int(Double(sampleRate) * seg.dur)
            for j in 0..<segFrames where offset + j < frames {
                let t = Float(j) / Float(sampleRate)
                let durF = Float(seg.dur)
                let fadeIn: Float = 0.012, fadeOut: Float = 0.025
                let env: Float
                if t < fadeIn { env = t / fadeIn }
                else if t > durF - fadeOut { env = max(0, (durF - t) / fadeOut) }
                else { env = 1 }
                let wobble: Float = sin(2 * .pi * 14 * t) * 6
                out[offset + j] = sin(2 * .pi * (seg.freq + wobble) * t) * 0.22 * env
            }
            offset += segFrames + Int(Double(sampleRate) * seg.gapAfter)
        }
        return out
    }

    private func synthPageFlip() -> [Float] {
        let total: TimeInterval = 0.55
        var out = samples(seconds: total)
        let frames = out.count
        let crackleCount = 50
        for _ in 0..<crackleCount {
            let startFrame = Int.random(in: 0..<max(1, frames - 256))
            let crackleLen = Int.random(in: Int(Double(sampleRate) * 0.003)...Int(Double(sampleRate) * 0.018))
            let amp = Float.random(in: 0.15...0.55)
            for j in 0..<crackleLen where startFrame + j < frames {
                let t = Float(j) / Float(crackleLen)
                out[startFrame + j] += Float.random(in: -1...1) * sin(.pi * t) * amp
            }
        }
        var lp: Float = 0
        for i in 0..<frames {
            lp = 0.82 * lp + 0.18 * out[i]
            out[i] = (out[i] - lp) * 0.85
        }
        let fade: Float = 0.05, durF = Float(total)
        for i in 0..<frames {
            let t = Float(i) / Float(sampleRate)
            let env: Float
            if t < fade { env = t / fade }
            else if t > durF - fade { env = max(0, (durF - t) / fade) }
            else { env = 1 }
            out[i] *= env
        }
        return out
    }

    private func synthCollator() -> [Float] {
        let bursts = 4
        let burstDur: TimeInterval = 0.075
        let gapDur: TimeInterval = 0.05
        let total = (burstDur + gapDur) * Double(bursts)
        var out = samples(seconds: total)
        let frames = out.count
        let perBurst = Int(Double(sampleRate) * burstDur)
        let perGap = Int(Double(sampleRate) * gapDur)
        var prev: Float = 0
        for b in 0..<bursts {
            let start = b * (perBurst + perGap)
            for j in 0..<perBurst where start + j < frames {
                let env: Float = sin(.pi * Float(j) / Float(perBurst))
                let n = Float.random(in: -1...1)
                prev = 0.4 * n + 0.6 * prev
                out[start + j] = prev * env * 0.32
            }
        }
        return out
    }

    private func synthFiltered(noiseSeconds total: TimeInterval, bursts: Int, volume: Float) -> [Float] {
        var out = samples(seconds: total)
        let frames = out.count
        if bursts <= 1 {
            for i in 0..<frames { out[i] = Float.random(in: -1...1) }
        } else {
            for _ in 0..<bursts {
                let startFrame = Int.random(in: 0..<max(1, frames - 1024))
                let len = Int.random(in: Int(Double(sampleRate) * 0.01)...Int(Double(sampleRate) * 0.04))
                for j in 0..<len where startFrame + j < frames {
                    let t = Float(j) / Float(len)
                    out[startFrame + j] += Float.random(in: -1...1) * sin(.pi * t)
                }
            }
        }
        var lp: Float = 0
        for i in 0..<frames {
            lp = 0.78 * lp + 0.22 * out[i]
            out[i] = (out[i] - lp) * volume
        }
        let fade: Float = 0.04, durF = Float(total)
        for i in 0..<frames {
            let t = Float(i) / Float(sampleRate)
            let env: Float
            if t < fade { env = t / fade }
            else if t > durF - fade { env = max(0, (durF - t) / fade) }
            else { env = 1 }
            out[i] *= env
        }
        return out
    }

    // MARK: - Music

    private var musicBuffers: [MusicTheme: Int32] = [:]
    private var musicVoice: Int32 = 0

    func startMusic(_ theme: MusicTheme = .normal) {
        stopMusic()
        currentTheme = theme
        let handle = musicBuffers[theme] ?? {
            let s = theme == .mib ? buildSunglassesAtNightLoop() : buildBackgroundLoop()
            let h = uploadPCM(s)
            musicBuffers[theme] = h
            return h
        }()
        guard handle > 0 else { return }
        // bossman-apple themeMusicMultiplier: the MIB theme plays at 0.625x.
        let vol = normalMusicVolume * (theme == .mib ? 0.625 : 1.0)
        musicVoice = snd_play(handle, vol, 1)   // loop=1
    }

    func stopMusic() {
        if musicVoice > 0 { snd_stop(musicVoice); musicVoice = 0 }
    }

    // MARK: - Gold-disc bass ("baseline") — a separate looping bass voice that
    // plays during the gold-disc / frighten window, mirroring bossman-apple's
    // bassPlayer + buildGoldDiscBeat / buildMIBGoldDiscBeat.

    private var bassBuffers: [MusicTheme: Int32] = [:]
    private var bassVoice: Int32 = 0
    private let bassVolume: Float = 70

    func startGoldDiscBass() {
        stopGoldDiscBass()
        let mib = currentTheme == .mib
        let theme: MusicTheme = mib ? .mib : .normal
        let handle = bassBuffers[theme] ?? {
            let s = mib ? buildMIBGoldDiscBeat() : buildGoldDiscBeat()
            let h = uploadPCM(s)
            bassBuffers[theme] = h
            return h
        }()
        guard handle > 0 else { return }
        bassVoice = snd_play(handle, bassVolume * (mib ? 0.75 : 1.0), 1)   // loop=1
    }

    func stopGoldDiscBass() {
        if bassVoice > 0 { snd_stop(bassVoice); bassVoice = 0 }
    }

    private func buildGoldDiscBeat() -> [Float] {
        var out = samples(seconds: 2.0)
        let frames = out.count
        let E2: Float = 82.41, E3: Float = 164.81, G2: Float = 98.00, A2: Float = 110.00, B2: Float = 123.47
        let pattern: [Float] = [
            E2, E2, 0, E3, E2, 0, G2, G2,
            E2, 0, A2, A2, G2, 0, B2, E3,
        ]
        let slotFrames = frames / pattern.count
        let attack: Float = 0.005
        for (slot, freq) in pattern.enumerated() where freq > 0 {
            let startFrame = slot * slotFrames
            for j in 0..<slotFrames where startFrame + j < frames {
                let t = Float(j) / Float(sampleRate)
                let env: Float = t < attack ? t / attack : exp(-3.8 * (t - attack))
                let f1 = sin(2 * .pi * freq * t)
                let f2 = sin(2 * .pi * freq * 2 * t) * 0.35
                let f3 = sin(2 * .pi * freq * 3 * t) * 0.12
                out[startFrame + j] = tanh((f1 + f2 + f3) * 1.8 * env) * 0.34
            }
        }
        return out
    }

    private func buildMIBGoldDiscBeat() -> [Float] {
        var out = samples(seconds: 60.0 / 100.0 * 4.0)
        let frames = out.count
        let C2: Float = 65.41, G2: Float = 98.00
        let pattern: [Float] = [C2, 0, C2, 0, G2, 0, C2, 0]
        let slotFrames = frames / pattern.count
        let attack: Float = 0.006
        for (slot, freq) in pattern.enumerated() where freq > 0 {
            let startFrame = slot * slotFrames
            let slotDuration = Float(slotFrames) / Float(sampleRate)
            let release: Float = 0.02
            for j in 0..<slotFrames where startFrame + j < frames {
                let t = Float(j) / Float(sampleRate)
                var env: Float = t < attack ? t / attack : exp(-3.2 * (t - attack))
                let tailStart = slotDuration - release
                if t > tailStart { env *= max(0, (slotDuration - t) / release) }
                out[startFrame + j] = sin(2 * .pi * freq * t) * 0.34 * env
            }
        }
        return out
    }

    // MARK: - Audio context lifecycle

    func pauseAudio() {
        snd_pause_all()
        tts_cancel()
    }

    func resumeAudio() {
        snd_resume_all()
    }

    func stopAllAudio() {
        snd_resume_all()
        stopMusic()
        stopGoldDiscBass()
        tts_cancel()
    }

    private func uploadPCM(_ samples: [Float]) -> Int32 {
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return Int32(0) }
            return snd_create_pcm(base, Int32(buf.count), sampleRate)
        }
    }

    // 108 BPM, 16-step bass + lead, ~4.44s loop (bossman-apple buildBackgroundLoop).
    private func buildBackgroundLoop() -> [Float] {
        let beat = 60.0 / 108.0 / 2.0
        let bass: [Float] = [
            130.81, 164.81, 130.81, 196.00,
            174.61, 220.00, 174.61, 261.63,
            155.56, 196.00, 155.56, 233.08,
            174.61, 220.00, 130.81, 164.81,
        ]
        let lead: [Float] = [
            0, 523.25, 0, 659.25, 0, 698.46, 0, 783.99,
            0, 622.25, 0, 740.00, 0, 698.46, 0, 587.33,
        ]
        return synthesize(bass: bass, lead: lead, beat: beat, decay: 6, bassGain: 0.12, leadGain: 0.06 * 0.7)
    }

    // 100 BPM, 64-step 16th-note "Men in Black" loop (every 12th level).
    private func buildSunglassesAtNightLoop() -> [Float] {
        let sixteenth = 60.0 / 100.0 / 4.0
        let C2: Float = 65.41, G2: Float = 98.00, Eb2: Float = 77.78, Ab2: Float = 103.83, F2: Float = 87.31
        let bass: [Float] = [
            C2, 0, C2, 0, G2, 0, C2, 0,  Eb2, 0, Eb2, 0, G2, 0, Eb2, 0,
            C2, 0, C2, 0, G2, 0, C2, 0,  G2, 0, Eb2, 0, C2, 0, G2, 0,
            Ab2, 0, Ab2, 0, Eb2, 0, Ab2, 0,  F2, 0, F2, 0, C2, 0, F2, 0,
            Ab2, 0, Ab2, 0, Eb2, 0, G2, 0,  G2, 0, G2, 0, C2, 0, G2, 0,
        ]
        let G5: Float = 783.99, F5: Float = 698.46, Eb5: Float = 622.25, D5: Float = 587.33
        let C5: Float = 523.25, Bb4: Float = 466.16, Ab4: Float = 415.30, Ab5: Float = 830.61, C6: Float = 1046.50
        let lead: [Float] = [
            0, G5, F5, Eb5, 0, D5, 0, C5,  0, G5, F5, Eb5, 0, F5, 0, Eb5,
            0, G5, F5, Eb5, 0, D5, 0, Bb4,  0, C5, 0, Eb5, 0, D5, C5, 0,
            Ab4, 0, C5, 0, Eb5, 0, Ab5, 0,  G5, 0, F5, 0, Eb5, 0, C5, 0,
            Ab4, 0, C5, Eb5, 0, G5, Ab5, C6,  0, Ab5, G5, 0, Eb5, 0, C5, 0,
        ]
        // Verbatim bossman-apple synthesis (NOT the generic sine `synthesize`):
        // a 2nd-harmonic, tanh-saturated bass; a detuned dual-sawtooth lead; and
        // a noise click on every 4th step. The note arrays match the master; only
        // the timbre was wrong before (plain sine), so MIB levels (12/24) sounded
        // off vs the Xcode version.
        let steps = 64
        let perFrames = Int(Double(sampleRate) * sixteenth)
        var out = [Float](repeating: 0, count: perFrames * steps)
        let clickFrames = Int(Double(sampleRate) * 0.012)
        for idx in 0..<steps {
            let bassF = bass[idx], leadF = lead[idx], start = idx * perFrames
            for j in 0..<perFrames {
                let t = Float(j) / Float(sampleRate)
                let env = exp(-5.5 * t) * (t < 0.005 ? t / 0.005 : 1)
                var v: Float = 0
                if bassF > 0 {
                    let s = sin(2 * .pi * bassF * t) + 0.45 * sin(2 * .pi * bassF * 2 * t)
                    v += tanh(s * 1.2) * 0.14 * env
                }
                if leadF > 0 {
                    let phase = leadF * t
                    let saw1 = 2 * (phase - floor(phase + 0.5))
                    let p2 = leadF * 1.005 * t
                    let saw2 = 2 * (p2 - floor(p2 + 0.5))
                    v += (saw1 + saw2) * 0.05 * env
                }
                if idx % 4 == 0 && j < clickFrames {
                    v += Float.random(in: -1...1) * exp(-90 * t) * 0.06
                }
                out[start + j] = v
            }
        }
        return out
    }

    private func synthesize(bass: [Float], lead: [Float], beat: Double, decay: Float,
                            bassGain: Float, leadGain: Float) -> [Float] {
        let perFrames = Int(Double(sampleRate) * beat)
        var out = [Float](repeating: 0, count: perFrames * bass.count)
        for idx in 0..<bass.count {
            let bF = bass[idx], lF = lead[idx], start = idx * perFrames
            for j in 0..<perFrames {
                let t = Float(j) / Float(sampleRate)
                let env = exp(-decay * t) * (t < 0.005 ? t / 0.005 : 1)
                var v: Float = 0
                if bF > 0 { v += sin(2 * .pi * bF * t) * bassGain * env }
                if lF > 0 { v += sin(2 * .pi * lF * t) * leadGain * env }
                out[start + j] = v
            }
        }
        return out
    }

    // MARK: - Speech

    private enum SpeechKind {
        case bossCapture, caught, fish, tps, gameOver, levelStart
        var priority: Bool {
            switch self {
            case .caught, .gameOver: return true
            case .bossCapture, .fish, .tps, .levelStart: return false
            }
        }
    }

    private func speak(_ kind: SpeechKind) {
        let lines: [String]
        let key: String
        switch kind {
        case .bossCapture: lines = Strings.Speech.bossCaptureLines; key = "bossCapture"
        case .caught:      lines = Strings.Speech.caughtLines;      key = "caught"
        case .fish:        lines = Strings.Speech.fishLines;        key = "fish"
        case .tps:         lines = Strings.Speech.tpsLines;         key = "tps"
        case .gameOver:    lines = Strings.Speech.gameOverLines;    key = "gameOver"
        case .levelStart:  lines = Strings.Speech.levelStartLines;  key = "levelStart"
        }
        guard !lines.isEmpty else { return }
        var idx = randIndex(in: lines.count)
        if lines.count > 1, idx == lastIndex[key] { idx = (idx + 1) % lines.count }
        lastIndex[key] = idx
        speak(text: lines[idx], priority: kind.priority)
    }

    private func speak(text: String, priority: Bool = false) {
        if priority { tts_cancel() }
        let bytes = Array(text.utf8)
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            base.withMemoryRebound(to: CChar.self, capacity: buf.count) { cBase in
                _ = tts_speak(cBase, Int32(buf.count), speechRate, speechPitch, speechVolume)
            }
        }
    }

    private func randIndex(in count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int.random(in: 0..<count)
    }
}
