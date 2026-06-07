@_exported import SpriteKit
import KitABI

// =============================================================================
// AVFoundation shim — presents the AVFoundation surface that game code uses,
// backed by the kit's audio ABI (snd_*/tts_* in runtime.js). Nothing here owns
// an audio backend; it forwards to the runtime's Web Audio + Web Speech graph.
//
// Two playback surfaces are covered:
//   1. AVAudioPlayer (FrogMan, AsteroidZ): file-backed, wraps snd_play.
//   2. AVAudioEngine + AVAudioPlayerNode (BossMan): synthesized PCM buffers
//      played through snd_play so the runtime's TTS duck (which scales every
//      snd voice) covers music and SFX automatically. AVSpeechSynthesizer maps
//      to tts_*; the runtime picks the voice and ducks while it speaks.
// =============================================================================

// The mixer's outputVolume folds into every player voice's gain so the apple
// mix (player.volume x mainMixer.outputVolume) reproduces on web.
nonisolated(unsafe) var _avMasterVolume: Float = 1.0

// Runs main-actor work from an audio completion. On wasm the completion fires on
// the single main thread, so the work runs inline (a deferred main-queue hop
// would never drain here). The macOS build supplies its own version that hops to
// the main queue, since its AVFoundation completions fire off-thread.
@MainActor public func runOnMain(_ work: @escaping @MainActor () -> Void) { work() }

// Hands the game's voice-name preference lists to the runtime, which owns voice
// selection on the web (priority order, robotic-excluded, female-last). The
// macOS build ranks voices in-process instead and supplies a no-op counterpart.
public func applySpeechVoicePreferences(preferred: [String], robotic: [String], female: [String]) {
    sendVoiceCSV(preferred.joined(separator: ","), tts_set_preferred_voices)
    sendVoiceCSV(robotic.joined(separator: ","),   tts_set_robotic_voices)
    sendVoiceCSV(female.joined(separator: ","),    tts_set_female_voices)
}
private func sendVoiceCSV(_ s: String, _ f: (UnsafePointer<CChar>?, Int32) -> Void) {
    let bytes = Array(s.utf8)
    bytes.withUnsafeBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        base.withMemoryRebound(to: CChar.self, capacity: buf.count) { f($0, Int32(buf.count)) }
    }
}

// ---- AVAudioPlayerDelegate ------------------------------------------------
public protocol AVAudioPlayerDelegate: AnyObject {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool)
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?)
}
public extension AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {}
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Swift.Error?) {}
}

// ---- AVAudioPlayer --------------------------------------------------------
public final class AVAudioPlayer {
    public var volume: Float = 1.0 { didSet { if voice >= 0 { snd_set_volume(voice, volume) } } }
    public var numberOfLoops: Int = 0          // -1 = infinite (SpriteKit semantics)
    public var rate: Float = 1.0
    public var enableRate = false
    public var currentTime: TimeInterval = 0
    public var duration: TimeInterval = 0
    public var isPlaying: Bool { voice >= 0 && snd_status(voice) == 1 }
    public var pan: Float = 0
    public var meteringEnabled = false

    let buffer: Int32
    var voice: Int32 = -1

    public weak var delegate: AVAudioPlayerDelegate?

    public init(contentsOf url: SKAudioURL) throws {
        let name = url.lastPathComponent
        self.buffer = withUTF8Ptr(name) { snd_by_name($0, $1) }
    }
    public init(data: [UInt8]) throws { self.buffer = 0 }    // raw-data form: not supported on web
    public init(fileNamed name: String) throws {
        self.buffer = withUTF8Ptr(name) { snd_by_name($0, $1) }
    }

    @discardableResult public func prepareToPlay() -> Bool { buffer != 0 }
    @discardableResult public func play() -> Bool {
        if buffer == 0 { return false }
        if voice >= 0 { snd_stop(voice) }
        voice = snd_play(buffer, volume, numberOfLoops < 0 ? 1 : 0)
        return voice >= 0
    }
    public func pause() {
        if voice >= 0 { snd_stop(voice) }
        voice = -1
    }
    public func stop()  { pause() }
    public func setVolume(_ v: Float, fadeDuration: TimeInterval = 0) { self.volume = v }
}

// ---- AVAudioSession --------------------------------------------------------
public final class AVAudioSession {
    public static let sharedInstance = AVAudioSession()
    public struct Category: RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let ambient = Category(rawValue: "ambient")
        public static let soloAmbient = Category(rawValue: "soloAmbient")
        public static let playback = Category(rawValue: "playback")
        public static let record = Category(rawValue: "record")
        public static let playAndRecord = Category(rawValue: "playAndRecord")
    }
    public struct CategoryOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mixWithOthers = CategoryOptions(rawValue: 1 << 0)
        public static let duckOthers = CategoryOptions(rawValue: 1 << 1)
        public static let defaultToSpeaker = CategoryOptions(rawValue: 1 << 2)
    }
    public struct Mode: RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let `default` = Mode(rawValue: "default")
        public static let gameChat = Mode(rawValue: "gameChat")
    }
    public func setCategory(_ c: Category, mode: Mode = .default, options: CategoryOptions = []) throws {}
    public func setActive(_ active: Bool, options: Int = 0) throws {}
    public func setActive(_ active: Bool) throws {}
}

// ---- AVSpeechSynthesizer --------------------------------------------------
// The runtime owns voice selection (tts_set_preferred_voices) and ducking
// (tts_speak's onstart/onend scale every snd voice). The delegate exists so
// apple's delegate-driven ducking compiles; the shim never invokes it because
// the runtime ducks on its own.
public enum AVSpeechBoundary: Int, Sendable { case immediate = 0, word = 1 }

public protocol AVSpeechSynthesizerDelegate: AnyObject {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance)
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance)
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance)
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance)
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance)
}
public extension AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {}
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {}
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {}
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {}
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {}
}

public let AVSpeechUtteranceDefaultSpeechRate: Float = 1.0
public let AVSpeechUtteranceMinimumSpeechRate: Float = 0.0
public let AVSpeechUtteranceMaximumSpeechRate: Float = 1.0

public final class AVSpeechSynthesizer {
    public weak var delegate: AVSpeechSynthesizerDelegate?
    public var isSpeaking = false
    public var isPaused = false

    public init() {}

    public func speak(_ utterance: AVSpeechUtterance) {
        isSpeaking = true
        withUTF8Ptr(utterance.speechString) { p, n in
            _ = tts_speak(p, n, utterance.rate, utterance.pitchMultiplier, utterance.volume)
        }
    }
    @discardableResult public func stopSpeaking(at boundary: AVSpeechBoundary = .immediate) -> Bool {
        tts_cancel()
        isSpeaking = false
        isPaused = false
        return true
    }
    @discardableResult public func pauseSpeaking(at boundary: AVSpeechBoundary = .word) -> Bool {
        tts_cancel()
        isPaused = true
        return true
    }
    @discardableResult public func continueSpeaking() -> Bool {
        isPaused = false
        return true
    }
}

public final class AVSpeechUtterance {
    public var speechString: String
    public var voice: AVSpeechSynthesisVoice?
    public var rate: Float = 0.5
    public var pitchMultiplier: Float = 1.0
    public var volume: Float = 1.0
    public var preUtteranceDelay: TimeInterval = 0
    public var postUtteranceDelay: TimeInterval = 0
    public init(string: String) { self.speechString = string }
    public init(attributedString: String) { self.speechString = attributedString }
}

public enum AVSpeechSynthesisVoiceGender: Int, Sendable { case unspecified = 0, male = 1, female = 2 }
public enum AVSpeechSynthesisVoiceQuality: Int, Sendable { case `default` = 1, enhanced = 2, premium = 3 }

public final class AVSpeechSynthesisVoice {
    public let language: String
    public let identifier: String
    public let name: String
    public var gender: AVSpeechSynthesisVoiceGender = .unspecified
    public var quality: AVSpeechSynthesisVoiceQuality = .default
    public init?(language: String) {
        self.language = language
        self.identifier = language
        self.name = language
    }
    public init(identifier: String) {
        self.identifier = identifier
        self.language = identifier
        self.name = identifier
    }
    public static func currentLanguageCode() -> String { "en-US" }
    // The runtime enumerates and picks voices itself; Swift-side selection is a
    // no-op on web, so the pool is empty and callers fall back to a default.
    public static func speechVoices() -> [AVSpeechSynthesisVoice] { [] }
}

// ---- QuartzCore -----------------------------------------------------------
// Monotonic media clock, fed by the kit's per-frame elapsed time.
public func CACurrentMediaTime() -> Double { Double(SKSpriteNode.kitClock()) }

// =============================================================================
// AVAudioEngine — node graph that forwards structure through eng_* while actual
// playback goes through snd_play (so ducking covers it). The graph wiring is
// kept so engine.start()/connect() are harmless and the audio context resumes.
// =============================================================================
public final class AVAudioEngine {
    public let mainMixerNode: AVAudioMixerNode
    public let outputNode = AVAudioOutputNode()
    public var isRunning = false

    public init() {
        self.mainMixerNode = AVAudioMixerNode()
        eng_connect(self.mainMixerNode.nodeId, -1)
    }
    public func attach(_ node: AnyObject) {}
    public func detach(_ node: AnyObject) {
        if let n = node as? AVAudioNode, n.nodeId >= 0 {
            eng_player_release(n.nodeId)
            n.nodeId = -1
        }
    }
    public func connect(_ src: AnyObject, to dst: AnyObject, format: Any?) {
        guard let s = src as? AVAudioNode, let d = dst as? AVAudioNode else { return }
        eng_connect(s.nodeId, d.nodeId)
    }
    public func connect(_ src: AnyObject, to dst: AnyObject, fromBus: Int, toBus: Int, format: Any?) {
        connect(src, to: dst, format: format)
    }
    public func disconnectNodeInput(_ node: AnyObject) {}
    public func disconnectNodeOutput(_ node: AnyObject) {}
    public func prepare() {}
    public func start() throws {
        eng_start()
        isRunning = true
    }
    public func stop() {
        eng_stop()
        isRunning = false
    }
    public func reset() {}
}

public class AVAudioNode {
    var nodeId: Int32 = -1
    public init() {}
    public var volume: Float = 1.0 { didSet { applyVolume() } }
    public var pan: Float = 0 { didSet { applyPan() } }
    func applyVolume() { if nodeId >= 0 { eng_node_set_volume(nodeId, volume) } }
    func applyPan() { if nodeId >= 0 { eng_node_set_pan(nodeId, pan) } }
}

public final class AVAudioMixerNode: AVAudioNode {
    public override init() {
        super.init()
        self.nodeId = eng_mixer_create()
    }
    public var outputVolume: Float = 1.0 { didSet { _avMasterVolume = outputVolume } }
}

public final class AUAudioUnit {
    public var maximumFramesToRender: AVAudioFrameCount = 4096
    public init() {}
}
public final class AVAudioOutputNode: AVAudioNode {
    public let auAudioUnit = AUAudioUnit()
    public override init() {
        super.init()
        self.nodeId = -1
    }  // -1 => audioCtx.destination
}

public struct AVAudioPlayerNodeBufferOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let loops = AVAudioPlayerNodeBufferOptions(rawValue: 1 << 0)
    public static let interrupts = AVAudioPlayerNodeBufferOptions(rawValue: 1 << 1)
    public static let interruptsAtLoop = AVAudioPlayerNodeBufferOptions(rawValue: 1 << 2)
}
public final class AVAudioTime { public init() {} }

public final class AVAudioPlayerNode: AVAudioNode {
    private var currentVoice: Int32 = -1

    public override init() {
        super.init()
        self.nodeId = eng_player_create()
    }

    public var isPlaying: Bool { currentVoice >= 0 && snd_status(currentVoice) == 1 }

    // Synthesized PCM played through snd_play. A non-nil completion handler is
    // registered for per-frame snd_status polling (drives BossMan's teleport
    // one-shot guard, where AVAudioPlayerNode would fire it natively on apple).
    public func scheduleBuffer(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime? = nil,
                               options: AVAudioPlayerNodeBufferOptions = [],
                               completionHandler h: (() -> Void)? = nil) {
        let handle = buffer.uploadedHandle()
        guard handle > 0 else {
            h?()
            return
        }
        let v = snd_play(handle, effectiveVolume(), options.contains(.loops) ? 1 : 0)
        currentVoice = v
        if let h = h {
            if v >= 0 { _kitRegisterAudioCompletion(v, h) } else { h() }
        }
    }
    public func scheduleFile(_ file: AVAudioFile, at when: AVAudioTime? = nil, completionHandler h: (() -> Void)? = nil) {
        if file.soundHandle > 0 {
            currentVoice = snd_play(file.soundHandle, effectiveVolume(), 0)
            if let h = h { if currentVoice >= 0 { _kitRegisterAudioCompletion(currentVoice, h) } else { h() } }
        } else { h?() }
    }

    public func play() { snd_resume_all() }
    public func play(at when: AVAudioTime?) { play() }
    public func stop() {
        if currentVoice >= 0 {
            snd_stop(currentVoice)
            currentVoice = -1
        }
    }
    public func pause() { snd_pause_all() }

    override func applyVolume() { if currentVoice >= 0 { snd_set_volume(currentVoice, effectiveVolume()) } }

    private func effectiveVolume() -> Float { max(0, min(100, volume * _avMasterVolume * 100)) }
}

public final class AVAudioFile {
    public var soundHandle: Int32 = 0
    public init(forReading url: SKAudioURL) throws {
        self.soundHandle = withUTF8Ptr(url.lastPathComponent) { snd_by_name($0, $1) }
    }
    public var length: Int64 = 0
    public var processingFormat: AVAudioFormat = AVAudioFormat()
    public func read(into buffer: AVAudioPCMBuffer) throws { buffer.soundHandle = self.soundHandle }
}

public final class AVAudioFormat {
    public var sampleRate: Double = 44100
    public var channelCount: UInt32 = 1
    public init() {}
    public init?(standardFormatWithSampleRate r: Double, channels: UInt32) {
        self.sampleRate = r
        self.channelCount = channels
    }
}

public typealias AVAudioFrameCount = UInt32

// Mono float PCM buffer. Synthesis writes through floatChannelData[0]; the
// first play uploads frameLength frames to the runtime (snd_create_pcm) and
// caches the resulting reusable sound handle.
public final class AVAudioPCMBuffer {
    public var frameCapacity: AVAudioFrameCount = 0
    public var frameLength: AVAudioFrameCount = 0
    public var soundHandle: Int32 = 0      // file-backed (AVAudioFile.read(into:))

    var sampleRate: Double = 44100
    private var samples: UnsafeMutablePointer<Float>?
    private var channelPtrs: UnsafeMutablePointer<UnsafeMutablePointer<Float>>?
    private var uploaded: Int32 = 0

    public init() {}
    public init?(pcmFormat: AVAudioFormat, frameCapacity: AVAudioFrameCount) {
        self.frameCapacity = frameCapacity
        self.sampleRate = pcmFormat.sampleRate
        let n = max(1, Int(frameCapacity))
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: n)
        buf.initialize(repeating: 0, count: n)
        self.samples = buf
        let cp = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 1)
        cp.initialize(to: buf)
        self.channelPtrs = cp
    }

    public var floatChannelData: UnsafeMutablePointer<UnsafeMutablePointer<Float>>? { channelPtrs }

    // snd_create_pcm copies the samples into a Web Audio buffer synchronously,
    // so once uploaded the Swift-side backing is freed; the cached handle is
    // reused on every replay (floatChannelData is only written pre-upload).
    func uploadedHandle() -> Int32 {
        if uploaded > 0 { return uploaded }
        if soundHandle > 0 {
            uploaded = soundHandle
            return uploaded
        }
        guard let s = samples, frameLength > 0 else { return 0 }
        uploaded = snd_create_pcm(s, Int32(frameLength), Int32(sampleRate))
        if uploaded > 0 {
            samples?.deallocate()
            samples = nil
            channelPtrs?.deallocate()
            channelPtrs = nil
        }
        return uploaded
    }
}


