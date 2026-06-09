#if os(macOS)
import Foundation

// macOS counterpart to the framework's runOnMain. SpriteKit audio completions
// fire off the main thread here, so hop to the main queue before touching
// main-actor state. (On wasm the completion already runs on the single main
// thread, so the framework's version runs the work inline.)
nonisolated func runOnMain(_ work: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async { MainActor.assumeIsolated(work) }
}
#endif
