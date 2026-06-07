import KitABI

// SKEmitterNode: a programmatic particle emitter. Spawns up to particleBirthRate*dt
// particles per frame (or stops at numParticlesToEmit), ages them, integrates
// velocity + accelerations, applies per-particle alpha/scale/color ramps and
// keyframe sequences, and draws each as a textured quad (or a colored circle
// when no particleTexture is set).
//
// Properties match Apple's API surface so .sks-driven games drop in once the
// .sks loader populates them. Targeted scope: rendering still happens on a
// flat Canvas2D path (no GPU shaders, no targetNode reparent yet).
public enum SKParticleRenderOrder: Int { case oldestLast, oldestFirst, dontCare }

public final class SKEmitterNode: SKNode {
    // ---- Birth / lifetime ----
    public var particleBirthRate: CGFloat = 0
    public var numParticlesToEmit: Int = 0           // 0 = continuous
    public var particleLifetime: CGFloat = 1
    public var particleLifetimeRange: CGFloat = 0

    // ---- Position spawning ----
    public var particlePosition: CGPoint = .zero
    public var particlePositionRange: CGVector = .zero

    // ---- Velocity ----
    public var particleSpeed: CGFloat = 100
    public var particleSpeedRange: CGFloat = 0
    public var emissionAngle: CGFloat = 0            // radians (0 = +x)
    public var emissionAngleRange: CGFloat = 0
    public var xAcceleration: CGFloat = 0
    public var yAcceleration: CGFloat = 0

    // ---- Alpha ----
    public var particleAlpha: CGFloat = 1
    public var particleAlphaRange: CGFloat = 0
    public var particleAlphaSpeed: CGFloat = -1      // alpha per second
    public var particleAlphaSequence: SKKeyframeSequence?

    // ---- Scale ----
    public var particleScale: CGFloat = 1
    public var particleScaleRange: CGFloat = 0
    public var particleScaleSpeed: CGFloat = 0
    public var particleScaleSequence: SKKeyframeSequence?

    // ---- Rotation ----
    public var particleRotation: CGFloat = 0
    public var particleRotationRange: CGFloat = 0
    public var particleRotationSpeed: CGFloat = 0

    // ---- Color ----
    public var particleColor: SKColor = .white
    public var particleColorBlendFactor: CGFloat = 1
    public var particleColorBlendFactorRange: CGFloat = 0
    public var particleColorBlendFactorSpeed: CGFloat = 0
    public var particleColorBlendFactorSequence: SKKeyframeSequence?
    public var particleColorSequence: SKKeyframeSequence?
    public var particleColorRedRange: CGFloat = 0
    public var particleColorGreenRange: CGFloat = 0
    public var particleColorBlueRange: CGFloat = 0
    public var particleColorAlphaRange: CGFloat = 0
    public var particleColorRedSpeed: CGFloat = 0
    public var particleColorGreenSpeed: CGFloat = 0
    public var particleColorBlueSpeed: CGFloat = 0
    public var particleColorAlphaSpeed: CGFloat = 0

    // ---- Z position (rendering depth ramp; recorded but flat draw order applies) ----
    public var particleZPosition: CGFloat = 0
    public var particleZPositionRange: CGFloat = 0
    public var particleZPositionSpeed: CGFloat = 0

    // ---- Rendering ----
    public var particleTexture: SKTexture?
    public var particleBlendMode: SKBlendMode = .alpha
    public var particleRenderOrder: SKParticleRenderOrder = .oldestLast
    public var particleSize = CGSize(width: 4, height: 4)
    public var shader: SKShader?
    public weak var targetNode: SKNode?              // recorded; particles still render under self
    public var fieldBitMask: UInt32 = 0xFFFFFFFF
    public var particleAction: SKAction?             // run on each particle as it spawns (no-op for now)

    private struct Particle {
        var x, y, vx, vy: CGFloat
        var age, life, alpha, scale, rotation, rotSpeed: CGFloat
        var r, g, b, a: CGFloat
        var blendFactor: CGFloat
    }
    private var particles: [Particle] = []
    private var emitAccum: CGFloat = 0
    private var emittedSoFar = 0

    public override init() { super.init() }

    // Programmatic load from a particle file (.sks). Without a parser we hand
    // back an emitter with defaults — call sites compile.
    public init?(fileNamed name: String) { super.init() }

    public func resetSimulation() { particles.removeAll()
    emitAccum = 0
    emittedSoFar = 0 }
    public func advanceSimulationTime(_ t: TimeInterval) {
        let dt: TimeInterval = 1.0 / 60.0
        var remaining = t
        while remaining > 0 { tickSelf(min(dt, remaining))
        remaining -= dt }
    }

    public override func tickSelf(_ dt: TimeInterval) {
        let d = CGFloat(dt)
        // age + integrate (reverse iterate for safe in-place removal)
        var i = particles.count - 1
        while i >= 0 {
            particles[i].age += d
            let p = particles[i]
            if p.age >= p.life { particles.remove(at: i)
            i -= 1
            continue }

            // Velocity integration (with global acceleration).
            particles[i].vx += xAcceleration * d
            particles[i].vy += yAcceleration * d
            particles[i].x  += particles[i].vx * d
            particles[i].y  += particles[i].vy * d

            // Alpha, scale, rotation.
            let agePct = p.life > 0 ? p.age / p.life : 1
            if let s = particleAlphaSequence?.sample(atTime: Double(agePct)) as? CGFloat {
                particles[i].alpha = s
            } else {
                particles[i].alpha = max(0, p.alpha + particleAlphaSpeed * d)
            }
            if let s = particleScaleSequence?.sample(atTime: Double(agePct)) as? CGFloat {
                particles[i].scale = s
            } else {
                particles[i].scale = max(0, p.scale + particleScaleSpeed * d)
            }
            particles[i].rotation += p.rotSpeed * d

            // Per-channel color drift.
            particles[i].r = clamp01(p.r + particleColorRedSpeed   * d)
            particles[i].g = clamp01(p.g + particleColorGreenSpeed * d)
            particles[i].b = clamp01(p.b + particleColorBlueSpeed  * d)
            particles[i].a = clamp01(p.a + particleColorAlphaSpeed * d)
            particles[i].blendFactor = clamp01(p.blendFactor + particleColorBlendFactorSpeed * d)
            if let c = particleColorSequence?.sample(atTime: Double(agePct)) as? SKColor {
                particles[i].r = c.r
                particles[i].g = c.g
                particles[i].b = c.b
                particles[i].a = c.a
            }
            if let bf = particleColorBlendFactorSequence?.sample(atTime: Double(agePct)) as? CGFloat {
                particles[i].blendFactor = bf
            }
            i -= 1
        }
        // spawn
        let exhausted = numParticlesToEmit > 0 && emittedSoFar >= numParticlesToEmit
        if !exhausted && particleBirthRate > 0 {
            emitAccum += particleBirthRate * d
            while emitAccum >= 1 {
                emitAccum -= 1
                emitOne()
                emittedSoFar += 1
                if numParticlesToEmit > 0 && emittedSoFar >= numParticlesToEmit { break }
            }
        }
    }

    private static let UNIT: [(CGFloat, CGFloat)] = [
        (1, 0), (0.924, 0.383), (0.707, 0.707), (0.383, 0.924), (0, 1),
        (-0.383, 0.924), (-0.707, 0.707), (-0.924, 0.383), (-1, 0),
        (-0.924, -0.383), (-0.707, -0.707), (-0.383, -0.924), (0, -1),
        (0.383, -0.924), (0.707, -0.707), (0.924, -0.383),
    ]
    private func emitOne() {
        let halfAng = emissionAngleRange / 2
        let ang = emissionAngle + (halfAng > 0 ? Double.random(in: -halfAng...halfAng) : 0)
        let speed = particleSpeed + (particleSpeedRange > 0 ? Double.random(in: -particleSpeedRange/2 ... particleSpeedRange/2) : 0)
        let life = particleLifetime + (particleLifetimeRange > 0 ? Double.random(in: -particleLifetimeRange/2 ... particleLifetimeRange/2) : 0)
        let step = Double.pi / 8                       // 22.5° per table entry
        var idx = Int(ang / step) % 16
        if idx < 0 { idx += 16 }
        let (cx, cy) = SKEmitterNode.UNIT[idx]

        // Position jitter inside particlePositionRange (treated as ±halfRange).
        let px = particlePosition.x + (particlePositionRange.dx > 0
                                       ? Double.random(in: -particlePositionRange.dx/2 ... particlePositionRange.dx/2)
                                       : 0)
        let py = particlePosition.y + (particlePositionRange.dy > 0
                                       ? Double.random(in: -particlePositionRange.dy/2 ... particlePositionRange.dy/2)
                                       : 0)

        let initialScale = particleScale + (particleScaleRange > 0
                                            ? Double.random(in: -particleScaleRange/2 ... particleScaleRange/2)
                                            : 0)
        let initialAlpha = particleAlpha + (particleAlphaRange > 0
                                            ? Double.random(in: -particleAlphaRange/2 ... particleAlphaRange/2)
                                            : 0)
        let initialRot   = particleRotation + (particleRotationRange > 0
                                               ? Double.random(in: -particleRotationRange/2 ... particleRotationRange/2)
                                               : 0)

        // Per-channel color initialization with range.
        let r0 = clamp01(particleColor.r + randRange(particleColorRedRange))
        let g0 = clamp01(particleColor.g + randRange(particleColorGreenRange))
        let b0 = clamp01(particleColor.b + randRange(particleColorBlueRange))
        let a0 = clamp01(particleColor.a + randRange(particleColorAlphaRange))
        let bf0 = clamp01(particleColorBlendFactor + randRange(particleColorBlendFactorRange))

        particles.append(Particle(x: px, y: py,
                                  vx: cx * speed, vy: cy * speed,
                                  age: 0, life: max(0.05, life),
                                  alpha: initialAlpha, scale: initialScale,
                                  rotation: initialRot, rotSpeed: particleRotationSpeed,
                                  r: r0, g: g0, b: b0, a: a0, blendFactor: bf0))
    }

    private func randRange(_ range: CGFloat) -> CGFloat {
        range > 0 ? Double.random(in: -range/2 ... range/2) : 0
    }
    private func clamp01(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }

    override func draw(alpha: CGFloat) {
        // Sort order honored only when oldestFirst (reverse drawing). dontCare/
        // oldestLast keep insertion order (newest on top).
        let list: [Particle] = particleRenderOrder == .oldestFirst ? particles.reversed() : particles
        for p in list {
            let aOut = max(0, min(1, p.alpha)) * alpha * p.a
            if aOut <= 0.001 { continue }
            let bf = p.blendFactor
            // Blend particleColor into the per-particle (r,g,b) channel by blendFactor.
            let r = particleColor.r * bf + p.r * (1 - bf)
            let g = particleColor.g * bf + p.g * (1 - bf)
            let b = particleColor.b * bf + p.b * (1 - bf)
            let c = SKColor(red: r, green: g, blue: b, alpha: aOut)

            if let tex = particleTexture {
                // Textured quad — pull the registered image handle through
                // gfx_draw_image. Rotation honored via gfx_save/rotate/restore.
                let w = Float(particleSize.width * p.scale)
                let h = Float(particleSize.height * p.scale)
                gfx_save()
                gfx_translate(Float(p.x), Float(p.y))
                if p.rotation != 0 { gfx_rotate(Float(p.rotation * 180.0 / Double.pi)) }
                gfx_draw_image(tex.handle, 0, 0, 0, 0, -w/2, -h/2, w, h, c.rgba)
                gfx_restore()
            } else {
                let r = Float(max(0.5, particleSize.width / 2 * p.scale))
                gfx_fill_circle(Float(p.x), Float(p.y), r, c.rgba)
            }
        }
    }
}


