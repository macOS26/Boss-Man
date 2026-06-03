import AppKit
import SpriteKit

final class PixelPerson: SKNode {
    let baseBodyColor: NSColor
    let baseTieColor:  NSColor
    let baseSkinColor: NSColor
    let baseTieOutlineColor: NSColor?

    private let bodyContainer = SKNode()

    // SpriteKit rasterizes each SKShapeNode to a bitmap at its native size, which
    // the camera then magnifies (soft at 150/200). Author every shape this many
    // times larger and shrink the body container by the same factor so the cache
    // is supersampled: same on-screen size/layout/animation, crisp under zoom.
    private static let pxRenderScale = RenderScale.factor

    private let torso: SKShapeNode
    private let leftArm: SKShapeNode
    private let rightArm: SKShapeNode
    private let leftLeg: SKShapeNode
    private let rightLeg: SKShapeNode
    private let tie: SKShapeNode
    private let leftShoe: SKShapeNode
    private let rightShoe: SKShapeNode
    private let walkExaggeration: CGFloat
    private var head: SKShapeNode!
    private var leftHand: SKShapeNode!
    private var rightHand: SKShapeNode!

    // MARK: - Eye tracking
    private var leftEye: SKShapeNode?
    private var rightEye: SKShapeNode?
    private static let leftEyeBase  = CGPoint(x: -3, y: 0)
    private static let rightEyeBase = CGPoint(x:  3, y: 0)

    private var walkingPaused = false
    private var walkActionsAttached: Bool { leftLeg.action(forKey: Strings.ActionKey.walk) != nil }
    var isWalking: Bool { walkActionsAttached && !walkingPaused }

    private var facingRight: Bool = true

    init(bodyColor: NSColor,
         tieColor: NSColor,
         hairColor: NSColor,
         shoeOutlineColor: NSColor,
         pantsColor: NSColor,
         walkExaggeration: CGFloat = 0,
         wearsSunglasses: Bool = false,
         headYOffset: CGFloat = 0) {
        self.walkExaggeration = walkExaggeration
        self.baseBodyColor = bodyColor
        self.baseTieColor  = tieColor
        self.baseTieOutlineColor = wearsSunglasses ? .white : nil
        let skin = NSColor(calibratedRed: 0.96, green: 0.78, blue: 0.62, alpha: 1)
        self.baseSkinColor = skin
        let shoeColor = NSColor(calibratedRed: 0.12, green: 0.08, blue: 0.05, alpha: 1)

        let rs = PixelPerson.pxRenderScale
        leftLeg = SKShapeNode(rectOf: CGSize(width: 6 * rs, height: 8 * rs))
        rightLeg = SKShapeNode(rectOf: CGSize(width: 6 * rs, height: 8 * rs))
        torso = SKShapeNode(rectOf: CGSize(width: 18 * rs, height: 16 * rs), cornerRadius: 1 * rs)
        tie = SKShapeNode(rectOf: CGSize(width: 4 * rs, height: 12 * rs))
        leftArm = SKShapeNode(rectOf: CGSize(width: 5 * rs, height: 14 * rs), cornerRadius: 1 * rs)
        rightArm = SKShapeNode(rectOf: CGSize(width: 5 * rs, height: 14 * rs), cornerRadius: 1 * rs)
        leftShoe = SKShapeNode(rectOf: CGSize(width: 8 * rs, height: 3 * rs))
        rightShoe = SKShapeNode(rectOf: CGSize(width: 8 * rs, height: 3 * rs))
        super.init()
        addChild(bodyContainer)
        bodyContainer.setScale(1 / rs)

        leftLeg.fillColor = pantsColor
        leftLeg.strokeColor = .clear
        leftLeg.position = CGPoint(x: -4 * rs, y: -14 * rs)
        leftLeg.zPosition = 1
        bodyContainer.addChild(leftLeg)

        rightLeg.fillColor = leftLeg.fillColor
        rightLeg.strokeColor = .clear
        rightLeg.position = CGPoint(x: 4 * rs, y: -14 * rs)
        rightLeg.zPosition = 1
        bodyContainer.addChild(rightLeg)

        leftShoe.fillColor = shoeColor
        leftShoe.strokeColor = shoeOutlineColor
        leftShoe.lineWidth = 1 * rs
        leftShoe.position = CGPoint(x: 1 * rs, y: -5 * rs)
        leftLeg.addChild(leftShoe)

        rightShoe.fillColor = shoeColor
        rightShoe.strokeColor = shoeOutlineColor
        rightShoe.lineWidth = 1 * rs
        rightShoe.position = CGPoint(x: 1 * rs, y: -5 * rs)
        rightLeg.addChild(rightShoe)

        let needsBacking = bodyColor.alphaComponent < 1.0
        if needsBacking {
            let torsoBack = SKShapeNode(rectOf: CGSize(width: 18 * rs, height: 16 * rs), cornerRadius: 2 * rs)
            torsoBack.fillColor = .white
            torsoBack.strokeColor = .clear
            torsoBack.position = CGPoint(x: 0, y: -2 * rs)
            torsoBack.zPosition = 1.5
            bodyContainer.addChild(torsoBack)
        }

        torso.fillColor = bodyColor
        torso.strokeColor = .white
        torso.lineWidth = 1.5 * rs
        torso.position = CGPoint(x: 0, y: -2 * rs)
        torso.zPosition = 2
        bodyContainer.addChild(torso)

        tie.fillColor = tieColor
        tie.strokeColor = wearsSunglasses ? .white : .clear
        tie.lineWidth = (wearsSunglasses ? 1 : 0) * rs
        tie.position = CGPoint(x: 0, y: -2 * rs)
        tie.zPosition = 3
        bodyContainer.addChild(tie)

        let collar = SKShapeNode(rectOf: CGSize(width: 8 * rs, height: 3 * rs))
        collar.fillColor = .white
        collar.strokeColor = .clear
        collar.position = CGPoint(x: 0, y: 5 * rs)
        torso.addChild(collar)

        if needsBacking {
            let leftArmBack = SKShapeNode(rectOf: CGSize(width: 5 * rs, height: 14 * rs), cornerRadius: 1 * rs)
            leftArmBack.fillColor = .white
            leftArmBack.strokeColor = .clear
            leftArmBack.position = CGPoint(x: -11 * rs, y: -2 * rs)
            leftArmBack.zPosition = 2.5
            bodyContainer.addChild(leftArmBack)
            let rightArmBack = SKShapeNode(rectOf: CGSize(width: 5 * rs, height: 14 * rs), cornerRadius: 1 * rs)
            rightArmBack.fillColor = .white
            rightArmBack.strokeColor = .clear
            rightArmBack.position = CGPoint(x: 11 * rs, y: -2 * rs)
            rightArmBack.zPosition = 2.5
            bodyContainer.addChild(rightArmBack)
        }

        leftArm.fillColor = bodyColor
        leftArm.strokeColor = .white
        leftArm.lineWidth = 1 * rs
        leftArm.position = CGPoint(x: -11 * rs, y: -2 * rs)
        leftArm.zPosition = 3
        bodyContainer.addChild(leftArm)

        rightArm.fillColor = bodyColor
        rightArm.strokeColor = .white
        rightArm.lineWidth = 1 * rs
        rightArm.position = CGPoint(x: 11 * rs, y: -2 * rs)
        rightArm.zPosition = 3
        bodyContainer.addChild(rightArm)

        let lh = SKShapeNode(circleOfRadius: 2.5 * rs)
        lh.fillColor = skin
        lh.strokeColor = .clear
        lh.position = CGPoint(x: 0, y: -8 * rs)
        leftArm.addChild(lh)
        leftHand = lh

        let rh = SKShapeNode(circleOfRadius: 2.5 * rs)
        rh.fillColor = skin
        rh.strokeColor = .clear
        rh.position = CGPoint(x: 0, y: -8 * rs)
        rightArm.addChild(rh)
        rightHand = rh

        let hd = SKShapeNode(rectOf: CGSize(width: 14 * rs, height: 12 * rs), cornerRadius: 2 * rs)
        hd.fillColor = skin
        hd.strokeColor = NSColor(calibratedWhite: 0.0, alpha: 0.5)
        hd.lineWidth = 1 * rs
        hd.position = CGPoint(x: 0, y: (13 + headYOffset) * rs)
        hd.zPosition = 4
        bodyContainer.addChild(hd)
        head = hd

        let hair = SKShapeNode(rectOf: CGSize(width: 14 * rs, height: 4 * rs))
        hair.fillColor = hairColor
        hair.strokeColor = .clear
        hair.position = CGPoint(x: 0, y: 4 * rs)
        head.addChild(hair)

        if wearsSunglasses {
            let shades = SKLabelNode(text: Strings.Emoji.sunglasses)
            shades.fontSize = 11 * rs
            shades.verticalAlignmentMode = .center
            shades.horizontalAlignmentMode = .center
            shades.position = CGPoint(x: 0.5 * rs, y: 0)
            shades.zPosition = 5
            head.addChild(shades)
        } else {
            let l = SKShapeNode(rectOf: CGSize(width: 2 * rs, height: 2 * rs))
            l.fillColor = .black
            l.strokeColor = .clear
            l.position = CGPoint(x: Self.leftEyeBase.x * rs, y: Self.leftEyeBase.y * rs)
            head.addChild(l)
            leftEye = l

            let rEye = SKShapeNode(rectOf: CGSize(width: 2 * rs, height: 2 * rs))
            rEye.fillColor = .black
            rEye.strokeColor = .clear
            rEye.position = CGPoint(x: Self.rightEyeBase.x * rs, y: Self.rightEyeBase.y * rs)
            head.addChild(rEye)
            rightEye = rEye
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

    func setShirtOutlineColor(_ color: NSColor) {
        torso.strokeColor = color
        leftArm.strokeColor = color
        rightArm.strokeColor = color
    }

    func setTieColor(_ color: NSColor) {
        tie.fillColor = color
    }

    // MARK: - Tie outline (used to mark flee-mode bosses)
    func setTieOutline(color: NSColor?, lineWidth: CGFloat = 1) {
        if let color {
            tie.strokeColor = color
            tie.lineWidth = lineWidth * Self.pxRenderScale
        } else if let base = baseTieOutlineColor {
            // Clearing falls back to the MIB boss's own white tie outline rather
            // than wiping it, so a flee-mode round doesn't strip it permanently.
            tie.strokeColor = base
            tie.lineWidth = 1 * Self.pxRenderScale
        } else {
            tie.strokeColor = .clear
            tie.lineWidth = 0
        }
    }

    // Frighten-mode face/hands tint. Brightness matches the original skin
    // (same channel sums, just B-dominant instead of R-dominant) so the
    // figure reads as blue without flattening to a uniform fill.
    func setSkinColor(_ color: NSColor) {
        head.fillColor      = color
        leftHand.fillColor  = color
        rightHand.fillColor = color
    }

    func setShoeOutlineColor(_ color: NSColor) {
        leftShoe.strokeColor = color
        rightShoe.strokeColor = color
    }

    func face(left: Bool) {
        bodyContainer.xScale = (left ? -1 : 1) / Self.pxRenderScale
        facingRight = !left
    }

    func setFacing(_ direction: MoveDirection) {
        switch direction {
        case .left:  face(left: true)
        case .right: face(left: false)
        case .up, .down: break
        }
        setLookDirection(direction)
    }

    // Like setFacing, but ignores a single direction reversal so the eyes/tie/
    // body keep the general heading instead of flipping forward-opposite-forward
    // on per-tile AI jitter (most visible in square mode's dwell). A reversal
    // that persists 2+ tiles still turns. Bosses use this; Pete uses setFacing
    // directly so the player gets an instant turn.
    private var smoothedFaceDir: MoveDirection?
    private var faceReverseSkips = 0
    func setFacingSmoothed(_ direction: MoveDirection) {
        if let last = smoothedFaceDir {
            let a = direction.delta, b = last.delta
            if a.dx == -b.dx && a.dy == -b.dy {        // exact reversal
                faceReverseSkips += 1
                if faceReverseSkips < 2 { return }     // skip an isolated flip-flop
            }
        }
        faceReverseSkips = 0
        smoothedFaceDir = direction
        setFacing(direction)
    }

    // MARK: - Eye tracking
    func setLookDirection(_ dir: MoveDirection?) {
        let offset: CGPoint
        switch dir {
        case .left, .right: offset = CGPoint(x: 1, y: 0)
        case .up:           offset = CGPoint(x: 0, y: 1)
        case .down:         offset = CGPoint(x: 0, y: -1)
        case .none:         offset = .zero
        }
        let rs = Self.pxRenderScale
        // Tie tracks for everyone, including sunglasses bosses (no eye nodes).
        tie.position = CGPoint(x: (Self.tieBase.x + offset.x) * rs, y: (Self.tieBase.y + offset.y) * rs)
        guard let leftEye, let rightEye else { return }
        leftEye.position  = CGPoint(x: (Self.leftEyeBase.x  + offset.x) * rs, y: (Self.leftEyeBase.y  + offset.y) * rs)
        rightEye.position = CGPoint(x: (Self.rightEyeBase.x + offset.x) * rs, y: (Self.rightEyeBase.y + offset.y) * rs)
    }

    private static let tieBase = CGPoint(x: 0, y: -2)

    func setEyeColor(_ color: NSColor) {
        leftEye?.fillColor = color
        rightEye?.fillColor = color
    }

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
        let legLift: CGFloat = (3 + walkExaggeration) * Self.pxRenderScale
        let armSwing: CGFloat = (2 + walkExaggeration) * Self.pxRenderScale

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
