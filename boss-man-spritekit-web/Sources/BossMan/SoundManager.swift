import SpriteKit
import KitABI
import Foundation       // exp / sin via wasi-libc libm

// Wasm SoundManager. Mirrors the public surface of bossman-apple's
// SoundManager so call sites compile unchanged, but the implementation is
// thinner: sound effects go through SuperBox64 SpriteKit's snd_play when a
// matching asset is preloaded in manifest.json (sounds[] entry by basename),
// and voice lines go through tts_speak (Web Speech API). When the asset is
// missing the call no-ops — preserves the contract without hard-coupling
// the gameplay to a full audio engine.
//
// The Boss-Man visit-line picker (boss capture, caught-by-boss, level
// start, etc.) walks Strings.Speech.* arrays and round-robins lines so
// the player doesn't hear the same one twice in a row.
final class SoundManager {
    enum MusicTheme { case normal, mib }

    // Speech rate / pitch / volume — tuned for the Web Speech API to
    // emulate Rocko (the deep-male Eloquence voice bossman-apple uses).
    // Web Speech API ranges: rate 0.1..10, pitch 0..2, volume 0..1.
    //   rate 0.85   slightly slower than default for Lumbergh-style drawl
    //   pitch 0.55  well below default so any picked voice reads deep
    //   volume 0.1  intentionally quiet per Todd's preference
    // The voice picker tries the real Rocko first (Safari exposes
    // Apple's Eloquence voices); the pitch/rate keep the impression
    // close when we fall back to Alex / Daniel / Microsoft David etc.
    private let speechRate:   Float = 0.85
    private let speechPitch:  Float = 0.55
    private let speechVolume: Float = 0.1

    // Round-robin indices so we don't repeat the same line back-to-back.
    private var lastIndex: [String: Int] = [:]

    // MARK: - Lifecycle

    init() {
        // Voice preference ordered DEEP-MALE first across browsers, then
        // by impersonation of Rocko's depth/timbre. Browsers expose
        // different voice pools — the picker walks this list in order and
        // takes the first match it finds in the pool:
        //   alex     Apple's "Alex" — deep, natural US male; closest to
        //            Rocko available outside Safari's Eloquence pool.
        //   rocko    The real Eloquence Rocko voice (Safari on macOS).
        //   ralph    Apple Eloquence backup, also quite deep.
        //   daniel   Apple British male — deep, slow.
        //   david    Microsoft David — deep US male on Edge/Chrome/Windows.
        //   mark     Microsoft Mark — alternate deep US male.
        //   fred     Apple's robotic-deep voice (last resort).
        //   reed     Eloquence reed voice (occasionally exposed).
        //   "google us english"  Chrome's default US-male variant.
        let preferred = "rocko,alex,ralph,daniel,david,mark,fred,reed,grandpa,junior,google us english"
        let robotic   = "bahh,bells,boing,bubbles,cellos,deranged,good news,hysterical,pipe organ,trinoids,whisper,zarvox,albert,eddy"
        // Common female-voice name fragments across Apple, Microsoft, and
        // Google Web Speech pools. The picker tries male voices first
        // (entire en-US -> any-English -> all pipeline) before touching
        // anything in this list, so we never fall through to a female
        // voice when a male one exists somewhere.
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

    // MARK: - Sound effects (snd_play with named buffer)

    func playDotBlip()         { play(named: "dot") }
    func playGoldDisc()        { play(named: "goldDisc") }
    func playWaterGunPickup()  { play(named: "waterGunPickup") }
    func playWaterGunShoot()   { play(named: "waterGunShoot") }
    func playWaterGunSplash()  { play(named: "waterGunSplash") }
    func playFootstep()        { play(named: "footstep") }
    func playTeleport()        { play(named: "teleport") }
    func playLevelStart()      { speak(.levelStart) }
    func playGameOver()        { play(named: "gameOver");   speak(.gameOver) }
    func playCaptureBoss(streak: Int = 0) {
        play(named: "captureBoss")
        speak(.bossCapture)
        _ = streak
    }
    func playCaughtByBoss()    { play(named: "caughtByBoss"); speak(.caught) }
    func playFishOrTreat()     { play(named: "fishOrTreat");  speak(.fish) }
    func playTpsDeliver()      { play(named: "tpsDeliver");   speak(.tps) }
    func playTpsMissingItems(_ items: [String]) {
        play(named: "tpsDeliver")
        guard !items.isEmpty else { return }
        let list = items.joined(separator: ", ")
        speak(text: "Still missing: \(list).")
    }
    func playMachine(named name: String) {
        switch name {
        case "printer": play(named: "machinePrinter")
        case "fax":     play(named: "machineFax")
        case "binder":  play(named: "machineBinder")
        default:        playDotBlip()
        }
    }

    func playTravelerArrive(_ which: TravelerSound) {
        let name: String
        switch which {
        case .water:       name = "water"
        case .glaze:       name = "glaze"
        case .crunch:      name = "crunch"
        case .alienBleep:  name = "alienBleep"
        case .jelly:       name = "jelly"
        case .crispTap:    name = "crispTap"
        case .bellDing:    name = "bellDing"
        case .radioStatic: name = "radioStatic"
        case .magicChime:  name = "magicChime"
        case .ufoWhoosh:   name = "ufoWhoosh"
        case .eyeDrone:    name = "eyeDrone"
        case .bigEye:      name = "bigEye"
        }
        play(named: name)
    }

    // bossman-apple's SoundManager synthesizes the bassline + lead loop
    // in Swift using AVAudioEngine. We do the exact same synthesis here,
    // hand the resulting Float32 buffer to the framework via the new
    // snd_create_pcm ABI, then loop it with snd_play.
    private var musicBuffers: [MusicTheme: Int32] = [:]
    private var musicVoice: Int32 = 0
    private let sampleRate: Int32 = 44100
    private let normalMusicVolume: Float = 30   // snd_play uses 0..100

    func startMusic(_ theme: MusicTheme = .normal) {
        stopMusic()
        let handle = musicBuffers[theme] ?? {
            let samples = theme == .mib ? buildSunglassesAtNightLoop()
                                        : buildBackgroundLoop()
            let h = uploadPCM(samples)
            musicBuffers[theme] = h
            return h
        }()
        guard handle > 0 else { return }
        musicVoice = snd_play(handle, normalMusicVolume, 1)   // loop=1
    }

    func stopMusic() {
        if musicVoice > 0 { snd_stop(musicVoice); musicVoice = 0 }
    }

    private func uploadPCM(_ samples: [Float]) -> Int32 {
        return samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return Int32(0) }
            return snd_create_pcm(base, Int32(buf.count), sampleRate)
        }
    }

    // Verbatim port of bossman-apple's SoundManager.buildBackgroundLoop
    // (Boss-Man/SoundManager.swift:695-727). 108 BPM, 16-step bass + lead
    // patterns, exponential decay envelope, ~4.44 seconds per loop.
    private func buildBackgroundLoop() -> [Float] {
        let bpm: Double = 108
        let beat = 60.0 / bpm / 2.0
        let bass: [Float] = [
            130.81, 164.81, 130.81, 196.00,
            174.61, 220.00, 174.61, 261.63,
            155.56, 196.00, 155.56, 233.08,
            174.61, 220.00, 130.81, 164.81,
        ]
        let lead: [Float] = [
            0,      523.25, 0,      659.25,
            0,      698.46, 0,      783.99,
            0,      622.25, 0,      740.00,
            0,      698.46, 0,      587.33,
        ]
        return synthesize(bass: bass, lead: lead, beat: beat, decay: 6,
                          bassGain: 0.12, leadGain: 0.06 * 0.7)
    }

    // Verbatim port of SoundManager.buildSunglassesAtNightLoop (the
    // "Men in Black" theme used on every 12th level). 100 BPM, 64-step
    // 16th-note loop, slightly slower decay, ~9.6 seconds.
    private func buildSunglassesAtNightLoop() -> [Float] {
        let bpm: Double = 100
        let sixteenth = 60.0 / bpm / 4.0
        let C2: Float = 65.41, G2: Float = 98.00, Eb2: Float = 77.78
        let Ab2: Float = 103.83, F2: Float = 87.31
        let bass: [Float] = [
            C2, 0, C2, 0, G2, 0, C2, 0,
            Eb2, 0, Eb2, 0, G2, 0, Eb2, 0,
            C2, 0, C2, 0, G2, 0, C2, 0,
            G2, 0, Eb2, 0, C2, 0, G2, 0,
            Ab2, 0, Ab2, 0, Eb2, 0, Ab2, 0,
            F2, 0, F2, 0, C2, 0, F2, 0,
            Ab2, 0, Ab2, 0, Eb2, 0, G2, 0,
            G2, 0, G2, 0, C2, 0, G2, 0,
        ]
        let G5: Float = 783.99, F5: Float = 698.46, Eb5: Float = 622.25
        let D5: Float = 587.33, C5: Float = 523.25, Bb4: Float = 466.16
        let Ab4: Float = 415.30, Ab5: Float = 830.61, C6: Float = 1046.50
        let lead: [Float] = [
            0, G5, F5, Eb5, 0, D5, 0, C5,
            0, G5, F5, Eb5, 0, F5, 0, Eb5,
            0, G5, F5, Eb5, 0, D5, 0, Bb4,
            0, C5, 0, Eb5, 0, D5, C5, 0,
            Ab4, 0, C5, 0, Eb5, 0, Ab5, 0,
            G5, 0, F5, 0, Eb5, 0, C5, 0,
            Ab4, 0, C5, Eb5, 0, G5, Ab5, C6,
            0, Ab5, G5, 0, Eb5, 0, C5, 0,
        ]
        return synthesize(bass: bass, lead: lead, beat: sixteenth, decay: 5.5,
                          bassGain: 0.12, leadGain: 0.06)
    }

    // Shared synthesis kernel. For each step, synthesize one beat of:
    //   bass = sin(2π * bassF * t) * env(t) * bassGain
    //   lead = sin(2π * leadF * t) * env(t) * leadGain   (skipped when freq=0)
    //   env(t) = exp(-decay * t) * (t < 0.005 ? t/0.005 : 1)   // pluck envelope
    private func synthesize(bass: [Float], lead: [Float], beat: Double, decay: Float,
                            bassGain: Float, leadGain: Float) -> [Float] {
        let perFrames = Int(Double(sampleRate) * beat)
        let total = perFrames * bass.count
        var out = [Float](repeating: 0, count: total)
        for idx in 0..<bass.count {
            let bF = bass[idx]
            let lF = lead[idx]
            let start = idx * perFrames
            for j in 0..<perFrames {
                let t = Float(j) / Float(sampleRate)
                let attack: Float = t < 0.005 ? t / 0.005 : 1
                let env = exp(-decay * t) * attack
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
        // Round-robin so consecutive plays don't repeat.
        var idx = randIndex(in: lines.count)
        if lines.count > 1, idx == lastIndex[key] {
            idx = (idx + 1) % lines.count
        }
        lastIndex[key] = idx
        speak(text: lines[idx])
    }

    private func speak(text: String) {
        let bytes = Array(text.utf8)
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            base.withMemoryRebound(to: CChar.self, capacity: buf.count) { cBase in
                _ = tts_speak(cBase, Int32(buf.count), speechRate, speechPitch, speechVolume)
            }
        }
    }

    // tts_speak / snd_by_name aren't declared via Swift modules; they
    // come in through KitABI's C shim that SpriteKit already imports.
    // Forward-declare here so the compiler links them.

    // MARK: - Sound asset playback

    private func play(named name: String, loop: Bool = false, volume: Float = 1.0) {
        let bytes = Array(name.utf8)
        let h: Int32 = bytes.withUnsafeBufferPointer { buf in
            guard let p = buf.baseAddress else { return Int32(0) }
            return p.withMemoryRebound(to: CChar.self, capacity: buf.count) { cp in
                snd_by_name(cp, Int32(buf.count))
            }
        }
        guard h > 0 else { return }    // asset not preloaded — skip silently
        _ = snd_play(h, volume, loop ? 1 : 0)
    }

    private func randIndex(in count: Int) -> Int {
        // Int.random uses SystemRandomNumberGenerator, which on wasi-libc
        // dispatches to random_get -> crypto.getRandomValues in the kit's
        // runtime — real entropy, different on every load. The previous
        // xorshift seed was a constant, so the *first* speak after a fresh
        // page load always picked the same line (which is why "Welcome
        // back" played every game start).
        guard count > 0 else { return 0 }
        return Int.random(in: 0..<count)
    }
}
