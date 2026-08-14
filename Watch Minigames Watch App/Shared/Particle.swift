//
//  Particle.swift
//  Watch Minigames Watch App
//
//  The one particle every game bursts, sparkles and confettis with.
//

import Foundation

struct Particle {
    var pos: Vec2
    var vel: Vec2
    var life: Double
    var maxLife: Double
    var size: Double
    var hue: ParticleHue

    enum ParticleHue { case gold, shard, grass, white, confetti(Int) }
}

/// Standard per-frame particle pass shared by every engine: age out, drift,
/// slow under exponential drag, prune the dead. A non-zero `confettiGravity`
/// makes confetti-hued sparks flutter downward (golf's sink celebration).
func updateParticles(_ particles: inout [Particle], dt: Double, drag: Double,
                     confettiGravity: Double = 0) {
    guard !particles.isEmpty else { return }
    for i in particles.indices {
        particles[i].life -= dt
        particles[i].pos += particles[i].vel * dt
        particles[i].vel = particles[i].vel * exp(-drag * dt)
        if confettiGravity != 0, case .confetti = particles[i].hue {
            particles[i].vel.y += confettiGravity * dt
        }
    }
    particles.removeAll { $0.life <= 0 }
}

/// Delivers an engine event on the next main-queue turn. Engines mutate
/// during view-body evaluation (the TimelineView step), so callbacks that
/// set @State must never fire synchronously.
func notifyMainAsync<T>(_ callback: ((T) -> Void)?, _ value: T) {
    DispatchQueue.main.async { callback?(value) }
}

/// Uniform radial burst: `count` sparks fly out at random angles, with
/// speed, life and size each drawn from their range; `hue` maps the spark's
/// index to its color.
func spawnRadialBurst(into particles: inout [Particle], at p: Vec2, count: Int,
                      speed: ClosedRange<Double>, life: ClosedRange<Double>,
                      size: ClosedRange<Double>, hue: (Int) -> Particle.ParticleHue) {
    for k in 0..<count {
        let a = Double.random(in: 0..<(2 * .pi))
        let l = Double.random(in: life)
        particles.append(Particle(
            pos: p, vel: Vec2(cos(a), sin(a)) * Double.random(in: speed),
            life: l, maxLife: l,
            size: Double.random(in: size), hue: hue(k)))
    }
}
