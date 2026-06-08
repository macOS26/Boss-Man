// A latch that passes once per frame. passOnce() returns true the first time
// it's called since the last clear() and then latches false; the game loop
// calls clear() once per frame (e.g. from SKScene.update). Use it to collapse a
// burst of identical events fired in a single frame — say every boss spawning
// at once should trigger ONE sound, not N overlapping ones.
//
// This exists because Task.sleep / asyncAfter never fire on single-threaded
// WASI, so a sleep-based cooldown would latch shut forever after the first use.
// Clearing from the frame loop is the reliable equivalent. Reusable by any
// ported game, so the workaround lives in the framework.
public final class FrameGate {
    private var latched = false
    public init() {}

    // True the first call since clear(); false on every later call until the
    // next clear().
    public func passOnce() -> Bool {
        if latched { return false }
        latched = true
        return true
    }

    public func clear() { latched = false }
}
