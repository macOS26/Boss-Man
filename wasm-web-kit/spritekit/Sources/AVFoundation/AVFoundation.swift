import SpriteKit
import KitABI

// =============================================================================
// AVFoundation shim — covers the two surfaces game code hits in practice:
//   1. AVAudioPlayer (FrogMan, AsteroidZ): wraps snd_play with volume/loops.
//   2. AVSpeechSynthesizer (FidgetX, Space-Bar): wraps the kit's tts_speak ABI,
//      backed by window.speechSynthesis in runtime.js.
//
// AVAudioEngine + its node graph (FrogMan) is too large for a useful stub
// without dragging the actual mixer in; we re-export a flat node list whose
// methods no-op so games compile, and recommend they migrate FX hits to the
// simpler AVAudioPlayer path on web.
// =============================================================================

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
    public func pause() { if voice >= 0 { snd_stop(voice); voice = -1 } }
    public func stop()  { pause() }
    public func setVolume(_ v: Float, fadeDuration: TimeInterval = 0) { self.volume = v }
}

// ---- AVAudioSession --------------------------------------------------------
public final class AVAudioSession {
    public static let sharedInstance = AVAudioSession()
    public struct Category: RawRepresentable, Sendable { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
        public static let ambient = Category(rawValue: "ambient")
        public static let soloAmbient = Category(rawValue: "soloAmbient")
        public static let playback = Category(rawValue: "playback")
        public static let record = Category(rawValue: "record")
        public static let playAndRecord = Category(rawValue: "playAndRecord")
    }
    public struct CategoryOptions: OptionSet, Sendable {
        public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mixWithOthers = CategoryOptions(rawValue: 1 << 0)
        public static let duckOthers = CategoryOptions(rawValue: 1 << 1)
        public static let defaultToSpeaker = CategoryOptions(rawValue: 1 << 2)
    }
    public struct Mode: RawRepresentable, Sendable { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
        public static let `default` = Mode(rawValue: "default")
        public static let gameChat = Mode(rawValue: "gameChat")
    }
    public func setCategory(_ c: Category, mode: Mode = .default, options: CategoryOptions = []) throws {}
    public func setActive(_ active: Bool, options: Int = 0) throws {}
    public func setActive(_ active: Bool) throws {}
}

// ---- AVSpeechSynthesizer --------------------------------------------------
public final class AVSpeechSynthesizer {
    public var delegate: AnyObject?
    public var isSpeaking = false
    public var isPaused = false

    public init() {}

    public func speak(_ utterance: AVSpeechUtterance) {
        isSpeaking = true
        withUTF8Ptr(utterance.speechString) { p, n in
            _ = tts_speak(p, n, utterance.rate, utterance.pitchMultiplier, utterance.volume)
        }
    }
    @discardableResult public func stopSpeaking(at boundary: Int = 0) -> Bool { tts_cancel(); isSpeaking = false; return true }
    @discardableResult public func pauseSpeaking(at boundary: Int = 0) -> Bool { isPaused = true; return true }
    @discardableResult public func continueSpeaking() -> Bool { isPaused = false; return true }
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

public final class AVSpeechSynthesisVoice {
    public let language: String
    public let identifier: String
    public let name: String
    public init?(language: String) { self.language = language; self.identifier = language; self.name = language }
    public init(identifier: String) { self.identifier = identifier; self.language = identifier; self.name = identifier }
    public static func currentLanguageCode() -> String { "en-US" }
    public static func speechVoices() -> [AVSpeechSynthesisVoice] { [] }
}

// =============================================================================
// AVAudioEngine — compile-only no-op graph so games compile. Audio doesn't play
// through this path on web; consumers should layer AVAudioPlayer on top.
// =============================================================================
public final class AVAudioEngine {
    public let mainMixerNode = AVAudioMixerNode()
    public let outputNode = AVAudioOutputNode()
    public init() {}
    public func attach(_ node: AnyObject) {}
    public func detach(_ node: AnyObject) {}
    public func connect(_ src: AnyObject, to dst: AnyObject, format: Any?) {}
    public func connect(_ src: AnyObject, to dst: AnyObject, fromBus: Int, toBus: Int, format: Any?) {}
    public func disconnectNodeInput(_ node: AnyObject) {}
    public func disconnectNodeOutput(_ node: AnyObject) {}
    public func prepare() {}
    public func start() throws {}
    public func stop() {}
    public func reset() {}
    public var isRunning = false
}
public class AVAudioNode { public init() {} }
public final class AVAudioMixerNode: AVAudioNode { public var volume: Float = 1 }
public final class AVAudioOutputNode: AVAudioNode {}
public final class AVAudioPlayerNode: AVAudioNode {
    public var pan: Float = 0
    public var volume: Float = 1
    public func play() {}
    public func play(at when: Any?) {}
    public func stop() {}
    public func pause() {}
    public func scheduleBuffer(_ buffer: AnyObject, completionHandler h: (() -> Void)? = nil) { h?() }
    public func scheduleBuffer(_ buffer: AnyObject, at when: Any?, options: Int, completionHandler h: (() -> Void)? = nil) { h?() }
    public func scheduleFile(_ file: AnyObject, at when: Any?, completionHandler h: (() -> Void)? = nil) { h?() }
}

public final class AVAudioFile {
    public init(forReading url: SKAudioURL) throws {}
    public var length: Int64 = 0
    public var processingFormat: AVAudioFormat = AVAudioFormat()
    public func read(into buffer: AVAudioPCMBuffer) throws {}
}
public final class AVAudioFormat {
    public init() {}
    public init(standardFormatWithSampleRate r: Double, channels: UInt32) {}
}
public final class AVAudioPCMBuffer {
    public var frameCapacity: UInt32 = 0
    public var frameLength: UInt32 = 0
    public init() {}
    public init(pcmFormat: AVAudioFormat, frameCapacity: UInt32) { self.frameCapacity = frameCapacity }
}
public typealias AVAudioFrameCount = UInt32
