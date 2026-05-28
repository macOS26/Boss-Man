import KitABI

// Minimal SKEmitterNode: a programmatic particle emitter (no .sks support). Each
// frame it spawns up to particleBirthRate*dt particles (or stops after
// numParticlesToEmit), ages them, integrates velocity, fades alpha/scales, and
// draws each as a colored circle via the kit ABI. Trig-free emission via a
// 16-entry unit-circle table (≈ 22.5° resolution) — plenty for visual bursts.
public final class SKEmitterNode: SKNode {
    public var particleBirthRate: CGFloat = 0
    public var numParticlesToEmit: Int = 0           // 0 = continuous
    public var particleLifetime: CGFloat = 1
    public var particleLifetimeRange: CGFloat = 0
    public var particleColor: SKColor = .white
    public var particleSize = CGSize(width: 4, height: 4)
    public var particleSpeed: CGFloat = 100
    public var particleSpeedRange: CGFloat = 0
    public var emissionAngle: CGFloat = 0            // radians (0 = +x)
    public var emissionAngleRange: CGFloat = 0
    public var particleAlpha: CGFloat = 1
    public var particleAlphaSpeed: CGFloat = -1      // alpha per second
    public var particleScale: CGFloat = 1
    public var particleScaleSpeed: CGFloat = 0

    private struct Particle {
        var x, y, vx, vy: CGFloat
        var age, life, alpha, scale: CGFloat
    }
    private var particles: [Particle] = []
    private var emitAccum: CGFloat = 0
    private var emittedSoFar = 0

    public override init() { super.init() }

    public func resetSimulation() { particles.removeAll(); emitAccum = 0; emittedSoFar = 0 }

    public override func tickSelf(_ dt: TimeInterval) {
        let d = CGFloat(dt)
        // age + integrate (reverse iterate for safe in-place removal)
        var i = particles.count - 1
        while i >= 0 {
            particles[i].age += d
            if particles[i].age >= particles[i].life { particles.remove(at: i); i -= 1; continue }
            particles[i].x += particles[i].vx * d
            particles[i].y += particles[i].vy * d
            particles[i].alpha = max(0, particles[i].alpha + particleAlphaSpeed * d)
            particles[i].scale = max(0, particles[i].scale + particleScaleSpeed * d)
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
        let half = emissionAngleRange / 2
        let ang = emissionAngle + (half > 0 ? Double.random(in: -half...half) : 0)
        let speed = particleSpeed + (particleSpeedRange > 0 ? Double.random(in: -particleSpeedRange/2 ... particleSpeedRange/2) : 0)
        let life = particleLifetime + (particleLifetimeRange > 0 ? Double.random(in: -particleLifetimeRange/2 ... particleLifetimeRange/2) : 0)
        let step = Double.pi / 8                       // 22.5deg per table entry
        var idx = Int(ang / step) % 16; if idx < 0 { idx += 16 }
        let (cx, cy) = SKEmitterNode.UNIT[idx]
        particles.append(Particle(x: 0, y: 0,
                                  vx: cx * speed, vy: cy * speed,
                                  age: 0, life: max(0.05, life),
                                  alpha: particleAlpha, scale: particleScale))
    }

    override func draw(alpha: CGFloat) {
        let baseRgba = particleColor
        for p in particles {
            let a = max(0, min(1, p.alpha)) * alpha
            if a <= 0.001 { continue }
            let c = SKColor(red: baseRgba.r, green: baseRgba.g, blue: baseRgba.b, alpha: a)
            let r = Float(max(0.5, particleSize.width / 2 * p.scale))
            gfx_fill_circle(Float(p.x), Float(p.y), r, c.rgba)
        }
    }
}
