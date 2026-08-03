//
//  StackerEngine.swift
//  Minigames Watch App
//
//  Stacker: household objects sway overhead — tap to drop them onto the
//  tower. Real statics decide survival: if the combined center of mass of
//  any section drifts past its support patch, that whole section peels off
//  and tumbles.
//

import Foundation
import CoreGraphics
import WatchKit

final class StackerEngine {

    // MARK: Objects

    enum ObjectKind: Int, CaseIterable {
        case box, book, tv, radio, toaster, mug, plant, clock, lamp
    }

    struct Spec {
        let kind: ObjectKind
        let w: Double          // visual + CoM width
        let h: Double
        let bottomW: Double    // contact width underneath
        let topW: Double       // surface the next object can rest on
        let colorIndex: Int
    }

    static func spec(for kind: ObjectKind, colorIndex: Int) -> Spec {
        switch kind {
        case .box:     return Spec(kind: kind, w: 44, h: 32, bottomW: 44, topW: 44, colorIndex: colorIndex)
        case .book:    return Spec(kind: kind, w: 48, h: 11, bottomW: 48, topW: 48, colorIndex: colorIndex)
        case .tv:      return Spec(kind: kind, w: 50, h: 36, bottomW: 46, topW: 44, colorIndex: colorIndex)
        case .radio:   return Spec(kind: kind, w: 40, h: 23, bottomW: 40, topW: 38, colorIndex: colorIndex)
        case .toaster: return Spec(kind: kind, w: 36, h: 21, bottomW: 34, topW: 28, colorIndex: colorIndex)
        case .mug:     return Spec(kind: kind, w: 24, h: 19, bottomW: 18, topW: 19, colorIndex: colorIndex)
        case .plant:   return Spec(kind: kind, w: 34, h: 34, bottomW: 20, topW: 21, colorIndex: colorIndex)
        case .clock:   return Spec(kind: kind, w: 26, h: 27, bottomW: 20, topW: 10, colorIndex: colorIndex)
        case .lamp:    return Spec(kind: kind, w: 28, h: 38, bottomW: 24, topW: 15, colorIndex: colorIndex)
        }
    }

    struct Placed {
        let spec: Spec
        var x: Double          // center
        var bottomY: Double
        /// Contact patch shared with whatever is below.
        var patchL: Double
        var patchR: Double
    }

    struct FreeBody {
        var spec: Spec
        var x: Double
        var y: Double          // bottom center
        var vx: Double
        var vy: Double
        var rot: Double
        var angVel: Double
    }

    enum Phase {
        case swaying(spec: Spec, since: Double)
        case falling(spec: Spec, x: Double, bottomY: Double, vy: Double)
        /// Just landed; waiting for the next object to spawn.
        case idle
        case tumbling(endAt: Double)
        case done
    }

    // MARK: State

    var courtW = 200.0
    var courtH = 240.0
    var phase: Phase = .swaying(spec: StackerEngine.randomSpec(), since: 0)
    var stack: [Placed] = []
    var freeBodies: [FreeBody] = []
    var score = 0
    var time = 0.0
    var shakeAmp = 0.0
    /// Tower wobble oscillator, kicked by every landing.
    var wobbleAmp = 0.0
    var lastLandAt = -10.0
    var lastPerfectAt = -10.0
    var particles: [Particle] = []
    var onGameOver: ((Int) -> Void)?

    private var lastDate: Date?
    private var swayDirection = 1.0
    private var spawnAt: Double? = nil

    var floorY: Double { courtH - 26 }
    var swayScreenY: Double { 58.0 }

    /// Where the top surface of the tower currently sits (world y).
    var towerTopY: Double {
        stack.last.map { $0.bottomY - $0.spec.h } ?? floorY
    }

    /// Camera lift so the tower top stays in the upper-middle of the screen.
    var cameraOffset: Double {
        max(0, courtH * 0.48 - towerTopY)
    }

    static func randomSpec() -> Spec {
        spec(for: ObjectKind.allCases.randomElement()!,
             colorIndex: Int.random(in: 0..<5))
    }

    // MARK: Stepping

    func step(to date: Date) {
        guard let last = lastDate else {
            lastDate = date
            return
        }
        let dt = max(0, min(date.timeIntervalSince(last), 1.0 / 30.0))
        lastDate = date
        time += dt
        shakeAmp *= exp(-7 * dt)
        wobbleAmp *= exp(-2.2 * dt)
        updateParticles(dt)
        updateFreeBodies(dt)

        if let s = spawnAt, time >= s {
            spawnAt = nil
            phase = .swaying(spec: Self.randomSpec(), since: time)
        }

        switch phase {
        case .falling(let spec, let x, let bottomY, let vy):
            let newVy = vy + 950 * dt
            let newBottom = bottomY + newVy * dt
            let surface = towerTopY
            if newBottom >= surface {
                land(spec: spec, x: x, bottomY: surface)
            } else {
                phase = .falling(spec: spec, x: x, bottomY: newBottom, vy: newVy)
            }
        case .tumbling(let endAt):
            if time >= endAt {
                phase = .done
                let final = score
                let cb = onGameOver
                DispatchQueue.main.async { cb?(final) }
            }
        default:
            break
        }
    }

    /// Sway position of the hovering object.
    func swayX(spec: Spec, since: Double) -> Double {
        let amplitude = max(20, courtW / 2 - spec.w / 2 - 8)
        let speed = min(1.5 + Double(stack.count) * 0.07, 2.9)
        return courtW / 2 + amplitude * sin((time - since) * speed) * swayDirection
    }

    // MARK: Dropping

    func drop() {
        guard case .swaying(let spec, let since) = phase else { return }
        let x = swayX(spec: spec, since: since)
        phase = .falling(spec: spec, x: x, bottomY: swayScreenY - cameraOffset + spec.h, vy: 40)
        Haptics.play(.click, minInterval: 0)
    }

    private func land(spec: Spec, x: Double, bottomY: Double) {
        // Contact patch with the support below.
        let myL = x - spec.bottomW / 2
        let myR = x + spec.bottomW / 2
        let supportL: Double
        let supportR: Double
        if let top = stack.last {
            supportL = top.x - top.spec.topW / 2
            supportR = top.x + top.spec.topW / 2
        } else {
            supportL = -.infinity
            supportR = .infinity
        }
        let patchL = max(myL, supportL)
        let patchR = min(myR, supportR)

        // The floor is infinite, so its "center" is wherever the piece is.
        let supportCenter = stack.isEmpty ? x : (supportL + supportR) / 2

        // Missed entirely, or center of mass beyond the patch: it tips off.
        if patchL >= patchR || x < patchL - 3 || x > patchR + 3 {
            let lean: Double = x > supportCenter ? 1 : -1
            freeBodies.append(FreeBody(spec: spec, x: x, y: bottomY,
                                       vx: lean * Double.random(in: 30...60),
                                       vy: -40,
                                       rot: 0,
                                       angVel: lean * Double.random(in: 2.5...4.5)))
            gameOver()
            return
        }

        var placed = Placed(spec: spec, x: x, bottomY: bottomY,
                            patchL: patchL, patchR: patchR)
        if stack.isEmpty {
            placed.patchL = myL
            placed.patchR = myR
        }
        stack.append(placed)
        score += 1
        lastLandAt = time
        wobbleAmp = min(wobbleAmp + 0.05 + abs(x - supportCenter) * 0.002, 0.12)
        spawnDust(at: Vec2(x, bottomY), width: spec.bottomW)

        // Perfect placement: dead center on the support.
        if stack.count > 1, abs(x - supportCenter) < 3 {
            score += 1
            lastPerfectAt = time
            spawnSparkle(at: Vec2(x, bottomY - spec.h / 2))
            Haptics.play(.success, minInterval: 0)
        } else {
            Haptics.play(.directionDown, minInterval: 0)
        }

        // Real statics: walk down the tower — the combined center of mass of
        // everything above each joint must sit over that joint's patch.
        if let breakIndex = firstUnstableJoint() {
            breakTower(at: breakIndex)
            return
        }

        swayDirection *= -1
        phase = .idle
        spawnAt = time + 0.22
    }

    /// Index of the first piece whose section above overloads its joint.
    private func firstUnstableJoint() -> Int? {
        guard stack.count >= 2 else { return nil }
        for j in stride(from: stack.count - 2, through: 0, by: -1) {
            let above = stack[(j + 1)...]
            var mass = 0.0
            var moment = 0.0
            for p in above {
                let m = p.spec.w * p.spec.h
                mass += m
                moment += m * p.x
            }
            let com = moment / mass
            let patch = stack[j + 1]
            if com < patch.patchL - 3 || com > patch.patchR + 3 {
                return j + 1
            }
        }
        return nil
    }

    /// Everything from `index` up peels off and tumbles.
    private func breakTower(at index: Int) {
        let falling = stack[index...]
        var mass = 0.0
        var moment = 0.0
        for p in falling {
            let m = p.spec.w * p.spec.h
            mass += m
            moment += m * p.x
        }
        let com = moment / mass
        let pivot = stack[index]
        let lean: Double = com > (pivot.patchL + pivot.patchR) / 2 ? 1 : -1
        for (i, p) in falling.enumerated() {
            freeBodies.append(FreeBody(
                spec: p.spec, x: p.x, y: p.bottomY,
                vx: lean * Double.random(in: 20...55) + Double(i) * lean * 6,
                vy: -Double.random(in: 10...50),
                rot: 0,
                angVel: lean * Double.random(in: 1.8...4.2)))
        }
        stack.removeSubrange(index...)
        shakeAmp = 5
        gameOver()
    }

    private func gameOver() {
        Haptics.play(.failure, minInterval: 0)
        shakeAmp = max(shakeAmp, 3.5)
        phase = .tumbling(endAt: time + 1.5)
    }

    func reset() {
        stack.removeAll()
        freeBodies.removeAll()
        particles.removeAll()
        score = 0
        wobbleAmp = 0
        swayDirection = 1
        spawnAt = nil
        phase = .swaying(spec: Self.randomSpec(), since: time)
    }

    // MARK: Free bodies

    private func updateFreeBodies(_ dt: Double) {
        guard !freeBodies.isEmpty else { return }
        for i in freeBodies.indices {
            freeBodies[i].vy += 950 * dt
            freeBodies[i].x += freeBodies[i].vx * dt
            freeBodies[i].y += freeBodies[i].vy * dt
            freeBodies[i].rot += freeBodies[i].angVel * dt
        }
        let limit = courtH + 120 - cameraOffset + 200
        freeBodies.removeAll { $0.y > limit }
    }

    // MARK: Particles

    private func updateParticles(_ dt: Double) {
        guard !particles.isEmpty else { return }
        for i in particles.indices {
            particles[i].life -= dt
            particles[i].pos += particles[i].vel * dt
            particles[i].vel = particles[i].vel * exp(-3.0 * dt)
        }
        particles.removeAll { $0.life <= 0 }
    }

    private func spawnDust(at p: Vec2, width: Double) {
        for _ in 0..<7 {
            let side = Bool.random() ? 1.0 : -1.0
            let life = Double.random(in: 0.25...0.45)
            particles.append(Particle(
                pos: Vec2(p.x + side * width / 2, p.y - 2),
                vel: Vec2(side * Double.random(in: 20...60), -Double.random(in: 5...30)),
                life: life, maxLife: life,
                size: Double.random(in: 1.4...2.6), hue: .shard))
        }
    }

    private func spawnSparkle(at p: Vec2) {
        for _ in 0..<10 {
            let a = Double.random(in: 0..<(2 * .pi))
            let life = Double.random(in: 0.35...0.6)
            particles.append(Particle(pos: p, vel: Vec2(cos(a), sin(a)) * Double.random(in: 30...90),
                                      life: life, maxLife: life,
                                      size: Double.random(in: 1.4...2.4), hue: .gold))
        }
    }
}
