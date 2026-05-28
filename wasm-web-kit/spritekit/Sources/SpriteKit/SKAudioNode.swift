import KitABI

// Looping / ambient audio attached to the scene graph. Maps onto the kit's
// snd_play (with loop=1 for autoplayLooped). isPositional is recorded but
// the runtime mixes in mono — Web Audio panning would slot in here later.
//
// AsteroidZ uses these for the saucer drone (run + changeVolume). FrogMan's
// AVAudioEngine paths bypass this and go straight to AVAudioPlayer when we
// ship the AVFoundation shim.
public final class SKAudioNode: SKNode {
    public var autoplayLooped: Bool = true
    public var isPositional: Bool = false
    public var volume: Float = 1.0 { didSet { applyVolume() } }

    let fileName: String
    var buffer: Int32 = 0      // snd_by_name handle
    var voice: Int32 = -1      // snd_play voice handle, -1 when idle

    public init(fileNamed name: String) {
        self.fileName = name
        super.init()
        self.buffer = withUTF8Ptr(name) { snd_by_name($0, $1) }
    }
    // URL form: takes anything with a `lastPathComponent`, so games passing
    // Foundation `URL` work without us importing Foundation here.
    public init(url: SKAudioURL) {
        self.fileName = url.lastPathComponent
        super.init()
        self.buffer = withUTF8Ptr(self.fileName) { snd_by_name($0, $1) }
    }

    public func play() {
        if buffer == 0 { return }
        if voice >= 0 { snd_stop(voice) }
        voice = snd_play(buffer, volume, autoplayLooped ? 1 : 0)
    }
    public func pause() { if voice >= 0 { snd_stop(voice); voice = -1 } }
    public func stop()  { pause() }

    public override func removeFromParent() { stop(); super.removeFromParent() }

    func applyVolume() { if voice >= 0 { snd_set_volume(voice, volume) } }
}

// Tiny URL stand-in so we don't drag Foundation into the SpriteKit module.
// Any value that exposes a `lastPathComponent: String` satisfies it; Foundation
// `URL` already does, so consumers can pass `URL(fileURLWithPath:)` directly.
public protocol SKAudioURL { var lastPathComponent: String { get } }

public extension SKAction {
    // Node-targeted audio actions: `audioNode.run(.play(on: audioNode))` etc.
    static func play(on node: SKAudioNode) -> SKAction { SKAction.run { node.play() } }
    static func stop(on node: SKAudioNode) -> SKAction { SKAction.run { node.stop() } }
}
