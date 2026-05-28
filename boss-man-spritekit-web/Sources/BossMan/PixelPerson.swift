import SpriteKit

// Pixel-art person used for Pete + the bosses. Ported from the macOS
// reference (boss-man-spritekit-swift) so the visual vocabulary matches:
//
//   bodyContainer  — wraps every visual child so face(left:) can flip the
//                    whole figure with one xScale assignment without also
//                    flipping eye/tie offsets used by setLookDirection.
//
//   Layered front-to-back:
//       legs (rect 6x8)  -> shoes (rect 8x3) as leg children
//       torso (rect 18x16 r2)
//       tie (rect 4x12)        — stroke turns on when wearsSunglasses
//       collar (child of torso, rect 8x3 at y=5)
//       arms (rect 5x14 r1)    — hands (circle r=2.5 skin) as arm children
//       head (rect 14x12 r2 skin)
//         hair (rect 14x4 hairColor at y=4)
//         eyes (rect 2x2 black) OR sunglasses emoji label
//
//   Walk animation: two SKActions running on the legs (and inverted on the
//   arms) with one offset by half a cycle so left/right alternate naturally.
//
//   Eye tracking: setLookDirection nudges both eye nodes + the tie by 1px
//   in the heading direction. Cheap, but reads convincingly.
final class PixelPerson: SKNode {
    // Initial palette captured so the boss can restore its tie/body/skin
    // after frighten mode ends (bossman-apple mutates these on the same
    // node and doesn't keep its own backup).
    let baseBodyColor: SKColor
    let baseTieColor:  SKColor
    let baseSkinColor: SKColor

    private let bodyContainer = SKNode()
    private var head: SKShapeNode!
    private var leftHand: SKShapeNode!
    private var rightHand: SKShapeNode!

    private let torso: SKShapeNode
    private let leftArm: SKShapeNode
    private let rightArm: SKShapeNode
    private let leftLeg: SKShapeNode
    private let rightLeg: SKShapeNode
    private let tie: SKShapeNode
    private let leftShoe: SKShapeNode
    private let rightShoe: SKShapeNode
    private let walkExaggeration: CGFloat

    private var leftEye: SKShapeNode?
    private var rightEye: SKShapeNode?
    private static let leftEyeBase  = CGPoint(x: -3, y: 0)
    private static let rightEyeBase = CGPoint(x:  3, y: 0)
    private static let tieBase      = CGPoint(x:  0, y: -2)

    private var walkingPaused = false
    private var walkActionsAttached: Bool { leftLeg.action(forKey: Strings.ActionKey.walk) != nil }
    var isWalking: Bool { walkActionsAttached && !walkingPaused }

    // Tracks the most recent facing so up/down inputs don't flip the body.
    private var facingRight: Bool = true

    init(bodyColor: SKColor,
         tieColor: SKColor,
         hairColor: SKColor,
         shoeOutlineColor: SKColor,
         pantsColor: SKColor,
         walkExaggeration: CGFloat = 0,
         wearsSunglasses: Bool = false,
         headYOffset: CGFloat = 0) {
        self.walkExaggeration = walkExaggeration
        self.baseBodyColor = bodyColor
        self.baseTieColor  = tieColor
        let skin = SKColor(red: 0.96, green: 0.78, blue: 0.62, alpha: 1)
        self.baseSkinColor = skin
        let shoeColor = SKColor(red: 0.12, green: 0.08, blue: 0.05, alpha: 1)

        leftLeg   = SKShapeNode(rectOf: CGSize(width: 6, height: 8))
        rightLeg  = SKShapeNode(rectOf: CGSize(width: 6, height: 8))
        torso     = SKShapeNode(rectOf: CGSize(width: 18, height: 16), cornerRadius: 2)
        tie       = SKShapeNode(rectOf: CGSize(width: 4, height: 12))
        leftArm   = SKShapeNode(rectOf: CGSize(width: 5, height: 14), cornerRadius: 1)
        rightArm  = SKShapeNode(rectOf: CGSize(width: 5, height: 14), cornerRadius: 1)
        leftShoe  = SKShapeNode(rectOf: CGSize(width: 8, height: 3))
        rightShoe = SKShapeNode(rectOf: CGSize(width: 8, height: 3))
        super.init()
        addChild(bodyContainer)

        leftLeg.fillColor = pantsColor
        leftLeg.strokeColor = .clear
        leftLeg.position = CGPoint(x: -4, y: -14)
        leftLeg.zPosition = 1
        bodyContainer.addChild(leftLeg)

        rightLeg.fillColor = pantsColor
        rightLeg.strokeColor = .clear
        rightLeg.position = CGPoint(x: 4, y: -14)
        rightLeg.zPosition = 1
        bodyContainer.addChild(rightLeg)

        leftShoe.fillColor = shoeColor
        leftShoe.strokeColor = shoeOutlineColor
        leftShoe.lineWidth = 1
        leftShoe.position = CGPoint(x: 1, y: -5)
        leftLeg.addChild(leftShoe)

        rightShoe.fillColor = shoeColor
        rightShoe.strokeColor = shoeOutlineColor
        rightShoe.lineWidth = 1
        rightShoe.position = CGPoint(x: 1, y: -5)
        rightLeg.addChild(rightShoe)

        torso.fillColor = bodyColor
        torso.strokeColor = .white
        torso.lineWidth = 1.5
        torso.position = CGPoint(x: 0, y: -2)
        torso.zPosition = 2
        bodyContainer.addChild(torso)

        tie.fillColor = tieColor
        tie.strokeColor = wearsSunglasses ? .white : .clear
        tie.lineWidth = wearsSunglasses ? 1 : 0
        tie.position = Self.tieBase
        tie.zPosition = 3
        bodyContainer.addChild(tie)

        let collar = SKShapeNode(rectOf: CGSize(width: 8, height: 3))
        collar.fillColor = .white
        collar.strokeColor = .clear
        collar.position = CGPoint(x: 0, y: 5)
        torso.addChild(collar)

        leftArm.fillColor = bodyColor
        leftArm.strokeColor = .white
        leftArm.lineWidth = 1
        leftArm.position = CGPoint(x: -11, y: -2)
        leftArm.zPosition = 3
        bodyContainer.addChild(leftArm)

        rightArm.fillColor = bodyColor
        rightArm.strokeColor = .white
        rightArm.lineWidth = 1
        rightArm.position = CGPoint(x: 11, y: -2)
        rightArm.zPosition = 3
        bodyContainer.addChild(rightArm)

        let lh = SKShapeNode(circleOfRadius: 2.5)
        lh.fillColor = skin
        lh.strokeColor = .clear
        lh.position = CGPoint(x: 0, y: -8)
        leftArm.addChild(lh)
        leftHand = lh

        let rh = SKShapeNode(circleOfRadius: 2.5)
        rh.fillColor = skin
        rh.strokeColor = .clear
        rh.position = CGPoint(x: 0, y: -8)
        rightArm.addChild(rh)
        rightHand = rh

        let hd = SKShapeNode(rectOf: CGSize(width: 14, height: 12), cornerRadius: 2)
        hd.fillColor = skin
        hd.strokeColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        hd.lineWidth = 1
        hd.position = CGPoint(x: 0, y: 13 + headYOffset)
        hd.zPosition = 4
        bodyContainer.addChild(hd)
        head = hd

        let hair = SKShapeNode(rectOf: CGSize(width: 14, height: 4))
        hair.fillColor = hairColor
        hair.strokeColor = .clear
        hair.position = CGPoint(x: 0, y: 4)
        head.addChild(hair)

        if wearsSunglasses {
            let shades = SKLabelNode(text: Strings.Emoji.sunglasses)
            shades.fontSize = 11
            shades.verticalAlignmentMode = .center
            shades.horizontalAlignmentMode = .center
            shades.position = CGPoint(x: 0, y: 0)
            shades.zPosition = 5
            head.addChild(shades)
        } else {
            let l = SKShapeNode(rectOf: CGSize(width: 2, height: 2))
            l.fillColor = .black
            l.strokeColor = .clear
            l.position = Self.leftEyeBase
            head.addChild(l)
            leftEye = l

            let r = SKShapeNode(rectOf: CGSize(width: 2, height: 2))
            r.fillColor = .black
            r.strokeColor = .clear
            r.position = Self.rightEyeBase
            head.addChild(r)
            rightEye = r
        }

        // Auto-start the walk loop so every actor animates without each
        // caller having to remember to enable it. Idempotent — startWalking()
        // no-ops if the actions are already attached.
        startWalking()
    }

    func setBodyColor(_ color: SKColor) {
        torso.fillColor = color
        leftArm.fillColor = color
        rightArm.fillColor = color
    }

    func setShirtOutlineColor(_ color: SKColor) {
        torso.strokeColor = color
        leftArm.strokeColor = color
        rightArm.strokeColor = color
    }

    func setTieColor(_ color: SKColor) {
        tie.fillColor = color
    }

    func setTieOutline(color: SKColor?, lineWidth: CGFloat = 1) {
        if let color {
            tie.strokeColor = color
            tie.lineWidth = lineWidth
        } else {
            tie.strokeColor = .clear
            tie.lineWidth = 0
        }
    }

    // Mutates head + both hands to a new skin tone (used by frighten mode
    // to give the boss a blue-tinted face/hands while keeping the same
    // per-channel brightness as the original skin).
    func setSkinColor(_ color: SKColor) {
        head.fillColor      = color
        leftHand.fillColor  = color
        rightHand.fillColor = color
    }

    func setShoeOutlineColor(_ color: SKColor) {
        leftShoe.strokeColor = color
        rightShoe.strokeColor = color
    }

    func face(left: Bool) {
        bodyContainer.xScale = left ? -1 : 1
        facingRight = !left
    }

    // Heading-aware: left/right flips the body, up/down keeps the prior
    // facing and only nudges the eye-tracking offset.
    func setFacing(_ direction: MoveDirection) {
        switch direction {
        case .left:  face(left: true)
        case .right: face(left: false)
        case .up, .down: break
        }
        setLookDirection(direction)
    }

    func setLookDirection(_ dir: MoveDirection?) {
        guard let leftEye, let rightEye else { return }
        let offset: CGPoint
        switch dir {
        case .left, .right: offset = CGPoint(x: 1, y: 0)
        case .up:           offset = CGPoint(x: 0, y: 1)
        case .down:         offset = CGPoint(x: 0, y: -1)
        case .none:         offset = .zero
        }
        leftEye.position  = CGPoint(x: Self.leftEyeBase.x  + offset.x,
                                    y: Self.leftEyeBase.y  + offset.y)
        rightEye.position = CGPoint(x: Self.rightEyeBase.x + offset.x,
                                    y: Self.rightEyeBase.y + offset.y)
        tie.position = CGPoint(x: Self.tieBase.x + offset.x,
                               y: Self.tieBase.y + offset.y)
    }

    func setEyeColor(_ color: SKColor) {
        leftEye?.fillColor = color
        rightEye?.fillColor = color
    }

    func startWalking() {
        if walkingPaused {
            walkingPaused = false
            leftLeg.speed = 1; rightLeg.speed = 1
            leftArm.speed = 1; rightArm.speed = 1
            return
        }
        guard !walkActionsAttached else { return }
        let stepDuration: TimeInterval = 0.16
        let legLift: CGFloat = 3 + walkExaggeration
        let armSwing: CGFloat = 2 + walkExaggeration

        let legCycle = SKAction.repeatForever(.sequence([
            SKAction.moveBy(x: 0, y: legLift, duration: stepDuration),
            SKAction.moveBy(x: 0, y: -legLift, duration: stepDuration)
        ]))
        let legCycleOffset = SKAction.sequence([
            SKAction.wait(forDuration: stepDuration),
            legCycle
        ])
        leftLeg.run(legCycle, withKey: Strings.ActionKey.walk)
        rightLeg.run(legCycleOffset, withKey: Strings.ActionKey.walk)

        let armCycle = SKAction.repeatForever(.sequence([
            SKAction.moveBy(x: 0, y: -armSwing, duration: stepDuration),
            SKAction.moveBy(x: 0, y: armSwing, duration: stepDuration)
        ]))
        let armCycleOffset = SKAction.sequence([
            SKAction.wait(forDuration: stepDuration),
            armCycle
        ])
        leftArm.run(armCycleOffset, withKey: Strings.ActionKey.walk)
        rightArm.run(armCycle, withKey: Strings.ActionKey.walk)
    }

    func stopWalking() {
        guard isWalking else { return }
        walkingPaused = true
        leftLeg.speed = 0; rightLeg.speed = 0
        leftArm.speed = 0; rightArm.speed = 0
    }
}
