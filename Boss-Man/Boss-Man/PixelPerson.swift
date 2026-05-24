import AppKit
import SpriteKit

final class PixelPerson: SKNode {
    private let bodyContainer = SKNode()

    private let torso: SKShapeNode
    private let leftArm: SKShapeNode
    private let rightArm: SKShapeNode
    private let leftLeg: SKShapeNode
    private let rightLeg: SKShapeNode
    private let tie: SKShapeNode
    private let walkExaggeration: CGFloat

    // MARK: - Eye tracking
    private var leftEye: SKShapeNode?
    private var rightEye: SKShapeNode?
    private static let leftEyeBase  = CGPoint(x: -3, y: 0)
    private static let rightEyeBase = CGPoint(x:  3, y: 0)

    private var walkingPaused = false
    private var walkActionsAttached: Bool { leftLeg.action(forKey: Strings.ActionKey.walk) != nil }
    var isWalking: Bool { walkActionsAttached && !walkingPaused }

    init(bodyColor: NSColor,
         tieColor: NSColor,
         hairColor: NSColor,
         shoeOutlineColor: NSColor,
         pantsColor: NSColor,
         walkExaggeration: CGFloat = 0,
         wearsSunglasses: Bool = false,
         headYOffset: CGFloat = 0) {
        self.walkExaggeration = walkExaggeration
        let skin = NSColor(calibratedRed: 0.96, green: 0.78, blue: 0.62, alpha: 1)
        let shoeColor = NSColor(calibratedRed: 0.12, green: 0.08, blue: 0.05, alpha: 1)

        leftLeg = SKShapeNode(rectOf: CGSize(width: 6, height: 8))
        rightLeg = SKShapeNode(rectOf: CGSize(width: 6, height: 8))
        torso = SKShapeNode(rectOf: CGSize(width: 18, height: 16), cornerRadius: 2)
        tie = SKShapeNode(rectOf: CGSize(width: 4, height: 12))
        leftArm = SKShapeNode(rectOf: CGSize(width: 5, height: 14), cornerRadius: 1)
        rightArm = SKShapeNode(rectOf: CGSize(width: 5, height: 14), cornerRadius: 1)
        super.init()
        addChild(bodyContainer)

        leftLeg.fillColor = pantsColor
        leftLeg.strokeColor = .clear
        leftLeg.position = CGPoint(x: -4, y: -14)
        leftLeg.zPosition = 1
        bodyContainer.addChild(leftLeg)

        rightLeg.fillColor = leftLeg.fillColor
        rightLeg.strokeColor = .clear
        rightLeg.position = CGPoint(x: 4, y: -14)
        rightLeg.zPosition = 1
        bodyContainer.addChild(rightLeg)

        let leftShoe = SKShapeNode(rectOf: CGSize(width: 8, height: 3))
        leftShoe.fillColor = shoeColor
        leftShoe.strokeColor = shoeOutlineColor
        leftShoe.lineWidth = 1
        leftShoe.position = CGPoint(x: 1, y: -5)
        leftLeg.addChild(leftShoe)

        let rightShoe = SKShapeNode(rectOf: CGSize(width: 8, height: 3))
        rightShoe.fillColor = shoeColor
        rightShoe.strokeColor = shoeOutlineColor
        rightShoe.lineWidth = 1
        rightShoe.position = CGPoint(x: 1, y: -5)
        rightLeg.addChild(rightShoe)

        let needsBacking = bodyColor.alphaComponent < 1.0
        if needsBacking {
            let torsoBack = SKShapeNode(rectOf: CGSize(width: 18, height: 16), cornerRadius: 2)
            torsoBack.fillColor = .white
            torsoBack.strokeColor = .clear
            torsoBack.position = CGPoint(x: 0, y: -2)
            torsoBack.zPosition = 1.5
            bodyContainer.addChild(torsoBack)
        }

        torso.fillColor = bodyColor
        torso.strokeColor = .white
        torso.lineWidth = 1.5
        torso.position = CGPoint(x: 0, y: -2)
        torso.zPosition = 2
        bodyContainer.addChild(torso)

        tie.fillColor = tieColor
        tie.strokeColor = wearsSunglasses ? .white : .clear
        tie.lineWidth = wearsSunglasses ? 1 : 0
        tie.position = CGPoint(x: 0, y: -2)
        tie.zPosition = 3
        bodyContainer.addChild(tie)

        let collar = SKShapeNode(rectOf: CGSize(width: 8, height: 3))
        collar.fillColor = .white
        collar.strokeColor = .clear
        collar.position = CGPoint(x: 0, y: 5)
        torso.addChild(collar)

        if needsBacking {
            let leftArmBack = SKShapeNode(rectOf: CGSize(width: 5, height: 14), cornerRadius: 1)
            leftArmBack.fillColor = .white
            leftArmBack.strokeColor = .clear
            leftArmBack.position = CGPoint(x: -11, y: -2)
            leftArmBack.zPosition = 2.5
            bodyContainer.addChild(leftArmBack)
            let rightArmBack = SKShapeNode(rectOf: CGSize(width: 5, height: 14), cornerRadius: 1)
            rightArmBack.fillColor = .white
            rightArmBack.strokeColor = .clear
            rightArmBack.position = CGPoint(x: 11, y: -2)
            rightArmBack.zPosition = 2.5
            bodyContainer.addChild(rightArmBack)
        }

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

        let leftHand = SKShapeNode(circleOfRadius: 2.5)
        leftHand.fillColor = skin
        leftHand.strokeColor = .clear
        leftHand.position = CGPoint(x: 0, y: -8)
        leftArm.addChild(leftHand)

        let rightHand = SKShapeNode(circleOfRadius: 2.5)
        rightHand.fillColor = skin
        rightHand.strokeColor = .clear
        rightHand.position = CGPoint(x: 0, y: -8)
        rightArm.addChild(rightHand)

        let head = SKShapeNode(rectOf: CGSize(width: 14, height: 12), cornerRadius: 2)
        head.fillColor = skin
        head.strokeColor = NSColor(calibratedWhite: 0.0, alpha: 0.5)
        head.lineWidth = 1
        head.position = CGPoint(x: 0, y: 13 + headYOffset)
        head.zPosition = 4
        bodyContainer.addChild(head)

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
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError(Strings.System.initCoderUnsupported)
    }

    func setBodyColor(_ color: NSColor) {
        torso.fillColor = color
        leftArm.fillColor = color
        rightArm.fillColor = color
    }

    func setTieColor(_ color: NSColor) {
        tie.fillColor = color
    }

    // MARK: - Tie outline (used to mark flee-mode bosses)
    func setTieOutline(color: NSColor?, lineWidth: CGFloat = 1) {
        if let color {
            tie.strokeColor = color
            tie.lineWidth = lineWidth
        } else {
            tie.strokeColor = .clear
            tie.lineWidth = 0
        }
    }

    func face(left: Bool) {
        bodyContainer.xScale = left ? -1 : 1
    }

    // MARK: - Eye tracking
    func setLookDirection(_ dir: MoveDirection?) {
        guard let leftEye, let rightEye else { return }
        let offset: CGPoint
        switch dir {
        case .left, .right: offset = CGPoint(x: 1, y: 0)
        case .up:           offset = CGPoint(x: 0, y: 1)
        case .down:         offset = CGPoint(x: 0, y: -1)
        case .none:         offset = .zero
        }
        leftEye.position  = CGPoint(x: Self.leftEyeBase.x  + offset.x, y: Self.leftEyeBase.y  + offset.y)
        rightEye.position = CGPoint(x: Self.rightEyeBase.x + offset.x, y: Self.rightEyeBase.y + offset.y)
        tie.position = CGPoint(x: Self.tieBase.x + offset.x, y: Self.tieBase.y + offset.y)
    }

    private static let tieBase = CGPoint(x: 0, y: -2)

    func startWalking() {
        if walkingPaused {
            walkingPaused = false
            leftLeg.speed = 1
            rightLeg.speed = 1
            leftArm.speed = 1
            rightArm.speed = 1
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
        leftLeg.speed = 0
        rightLeg.speed = 0
        leftArm.speed = 0
        rightArm.speed = 0
    }
}
