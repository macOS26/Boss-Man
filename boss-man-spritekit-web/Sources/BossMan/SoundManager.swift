import SpriteKit
import KitABI

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
    private nonisolated(unsafe) static var rng: UInt64 = 0xDEADBEEFCAFEBABE

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
        let preferred = "alex,rocko,ralph,daniel,david,mark,fred,reed,grandpa,junior,google us english"
        let robotic   = "bahh,bells,boing,bubbles,cellos,deranged,good news,hysterical,pipe organ,trinoids,whisper,zarvox,albert,eddy"
        callCSV(preferred, tts_set_preferred_voices)
        callCSV(robotic,   tts_set_robotic_voices)
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
    func playLevelStart()      { play(named: "levelStart"); speak(.levelStart) }
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

    func startMusic(_ theme: MusicTheme = .normal) {
        let name = theme == .mib ? "musicMib" : "musicNormal"
        play(named: name, loop: true, volume: 0.5)
    }
    func stopMusic() { /* snd_stop needs the voice handle; recorded music
                         not yet wired so this is a no-op stub. */ }

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
        // xorshift64 — deterministic-ish for tests, no Foundation dependency.
        var x = Self.rng
        x ^= x << 13; x ^= x >> 7; x ^= x << 17
        Self.rng = x
        return Int(x % UInt64(max(count, 1)))
    }
}
