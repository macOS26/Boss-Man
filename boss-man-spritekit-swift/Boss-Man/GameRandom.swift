// Xoshiro256** (Blackman & Vigna, public domain) — a fast, high-quality, fully
// portable PRNG. SystemRandomNumberGenerator has no working entropy source on
// wasm, so shared game code routes its randomness through this via
// .random(in:using:), giving identical dependency-free results on Apple and
// wasm. Seeded once via SplitMix64, deterministic (reproducible) by design.
struct Xoshiro256: RandomNumberGenerator {
    private var s: (UInt64, UInt64, UInt64, UInt64)

    nonisolated init(seed: UInt64) {
        var sm = seed
        func splitmix() -> UInt64 {
            sm &+= 0x9E3779B97F4A7C15
            var z = sm
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        s = (splitmix(), splitmix(), splitmix(), splitmix())
    }

    nonisolated mutating func next() -> UInt64 {
        func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 { (x << k) | (x >> (64 &- k)) }
        let result = rotl(s.1 &* 5, 7) &* 9
        let t = s.1 << 17
        s.2 ^= s.0
        s.3 ^= s.1
        s.1 ^= s.2
        s.0 ^= s.3
        s.2 ^= t
        s.3 = rotl(s.3, 45)
        return result
    }
}

enum GameRandom {
    nonisolated(unsafe) static var shared = Xoshiro256(seed: 0x2545F4914F6CDD1D)
}
