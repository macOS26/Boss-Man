import AVFoundation

#if os(macOS)
// NSObject conformer for AVSpeechSynthesizer's @objc delegate, kept out of the
// common SoundManager so the wasm build stays NSObject-free. Forwards speech
// start/stop to the owner's ducking on the main actor.
final class SpeechDuckDelegate: NSObject, AVSpeechSynthesizerDelegate {
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

// macOS ranks voices in-process (pickBossVoice), so the runtime handoff that the
// framework performs on wasm is a no-op here.
func applySpeechVoicePreferences(preferred: [String], robotic: [String], female: [String]) {}

extension SoundManager {
    // Wires speech ducking. macOS rides the @objc delegate; wasm ducks in the
    // runtime, so there's nothing to install.
    func configureSpeechDucking() {
        let duck = SpeechDuckDelegate()
        duck.owner = self
        speech.delegate = duck
        speechDuckRetain = duck
    }
}
#elseif os(WASI)
extension SoundManager {
    // wasm ducks in the runtime, so there's nothing to install in-process.
    func configureSpeechDucking() {}
}
#endif
