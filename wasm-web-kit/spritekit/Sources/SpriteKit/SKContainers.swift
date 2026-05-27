// SKEffectNode / SKCropNode: on web we render children directly (effects and
// crop masks are no-ops), which is enough for games that use them as plain
// grouping containers.
public final class SKEffectNode: SKNode {
    public var shouldEnableEffects = false
    public var shouldRasterize = false
    public var filter: AnyObject? = nil
    public var blendMode: Int = 0
}

public final class SKCropNode: SKNode {
    public var maskNode: SKNode?
}
