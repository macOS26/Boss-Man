import KitABI

public enum SKSceneScaleMode { case fill, aspectFill, aspectFit, resizeFill }

open class SKScene: SKNode {
    public var size: CGSize
    public var backgroundColor: SKColor = SKColor(white: 0.06, alpha: 1)
    public var anchorPoint = CGPoint.zero
    public var scaleMode: SKSceneScaleMode = .aspectFit
    public let physicsWorld = SKPhysicsWorld()
    public weak var view: SKView?
    public weak var camera: SKCameraNode?      // active camera; nil = default top-down

    public init(size: CGSize) { self.size = size; super.init() }
    public convenience override init() { self.init(size: CGSize(width: 1184, height: 666)) }

    open func didMove(to view: SKView) {}
    open func willMove(from view: SKView) {}
    open func didChangeSize(_ oldSize: CGSize) {}
    open func sceneDidLoad() {}                // called once before didMove
    open func update(_ currentTime: TimeInterval) {}
    open func didEvaluateActions() {}          // after actions, before physics
    open func didSimulatePhysics() {}
    open func didApplyConstraints() {}         // before didFinishUpdate
    open func didFinishUpdate() {}

    // SKView's debug render path looks for `convertPoint(fromView:)` and the
    // inverse so games can map mouse coordinates from view space.
    open func convertPoint(fromView p: CGPoint) -> CGPoint { p }
    open func convertPoint(toView p: CGPoint) -> CGPoint { p }

    // input hooks the demo/game can override
    open func keyDown(_ key: Int) {}
    open func keyUp(_ key: Int) {}
    open func mouseDown(at p: CGPoint) {}
    open func mouseUp(at p: CGPoint) {}
    open func mouseMoved(to p: CGPoint) {}
}

public typealias TimeInterval = Double
