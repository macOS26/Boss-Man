import KitABI

public enum SKSceneScaleMode { case fill, aspectFill, aspectFit, resizeFill }

open class SKScene: SKNode {
    public var size: CGSize
    public var backgroundColor: SKColor = SKColor(white: 0.06, alpha: 1)
    public var anchorPoint = CGPoint.zero
    public var scaleMode: SKSceneScaleMode = .aspectFit
    public let physicsWorld = SKPhysicsWorld()
    public weak var view: SKView?

    public init(size: CGSize) { self.size = size; super.init() }
    public convenience override init() { self.init(size: CGSize(width: 1184, height: 666)) }

    open func didMove(to view: SKView) {}
    open func update(_ currentTime: TimeInterval) {}
    open func didSimulatePhysics() {}
    open func didFinishUpdate() {}

    // input hooks the demo/game can override
    open func keyDown(_ key: Int) {}
    open func keyUp(_ key: Int) {}
    open func mouseDown(at p: CGPoint) {}
    open func mouseUp(at p: CGPoint) {}
    open func mouseMoved(to p: CGPoint) {}
}

public typealias TimeInterval = Double
