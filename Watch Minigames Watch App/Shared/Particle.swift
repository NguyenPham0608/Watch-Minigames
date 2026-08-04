//
//  Particle.swift
//  Minigames Watch App
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
