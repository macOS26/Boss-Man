import SpriteKit

// First-pass PixelPerson for the wasm port. The macOS original draws a
// detailed pixel-art body (head, torso, tie, pants, shoes, walk anim,
// optional sunglasses) with SKShapeNode children. Here we ship a slimmer
// stand-in: a colored body circle + a stripe (tie or belt) + two dot eyes,
// good enough to read at maze scale. Walk animation flips horizontally to
// match the facing direction. We can iterate to full pixel detail later
// without changing the call sites — the type and the public properties stay
// the same.
final class PixelPerson: SKNode {
    let bodyColor: SKColor
    let tieColor: SKColor
    let hairColor: SKColor
    let shoeOutlineColor: SKColor
    let pantsColor: SKColor
    let wearsSunglasses: Bool

    private let body: SKShapeNode
    private let tie:  SKShapeNode
    private let leftEye:  SKShapeNode
    private let rightEye: SKShapeNode
    private var facingRight: Bool = true

    init(bodyColor: SKColor,
         tieColor: SKColor,
         hairColor: SKColor,
         shoeOutlineColor: SKColor,
         pantsColor: SKColor,
         wearsSunglasses: Bool = false,
         walkExaggeration: CGFloat = 0,
         headYOffset: CGFloat = 0) {
        self.bodyColor = bodyColor
        self.tieColor = tieColor
        self.hairColor = hairColor
        self.shoeOutlineColor = shoeOutlineColor
        self.pantsColor = pantsColor
        self.wearsSunglasses = wearsSunglasses

        self.body = SKShapeNode(circleOfRadius: 9)
        body.fillColor = bodyColor
        body.strokeColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.6)
        body.lineWidth = 1

        // Stripe down the front — tie for Pete, gold band for bosses.
        let tieRect = CGRect(x: -2, y: -10, width: 4, height: 9)
        self.tie = SKShapeNode(rect: tieRect)
        tie.fillColor = tieColor
        tie.strokeColor = .clear

        let eyeRadius: CGFloat = 1.4
        self.leftEye  = SKShapeNode(circleOfRadius: eyeRadius)
        self.rightEye = SKShapeNode(circleOfRadius: eyeRadius)
        let eyeFill: SKColor = wearsSunglasses ? .black : .black
        leftEye.fillColor  = eyeFill; leftEye.strokeColor  = .clear
        rightEye.fillColor = eyeFill; rightEye.strokeColor = .clear
        leftEye.position  = CGPoint(x: -3, y: 3)
        rightEye.position = CGPoint(x:  3, y: 3)

        super.init()
        addChild(body)
        addChild(tie)
        addChild(leftEye)
        addChild(rightEye)
        if wearsSunglasses { addSunglasses() }
        _ = walkExaggeration   // recorded for the future detailed body
        _ = headYOffset
    }

    private func addSunglasses() {
        let bar = SKShapeNode(rect: CGRect(x: -5, y: 1.5, width: 10, height: 3.5),
                              cornerRadius: 0.8)
        bar.fillColor = .black
        bar.strokeColor = .clear
        addChild(bar)
    }

    // Flip the person to face left/right. Eyes shift slightly with facing so
    // the gaze sells the heading at a glance.
    func setFacing(_ direction: MoveDirection) {
        let right: Bool
        switch direction {
        case .left:  right = false
        case .right: right = true
        case .up, .down: right = facingRight
        }
        if right == facingRight { return }
        facingRight = right
        xScale = right ? 1 : -1
    }
}
