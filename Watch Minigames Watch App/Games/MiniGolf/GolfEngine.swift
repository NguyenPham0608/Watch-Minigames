//
//  GolfEngine.swift
//  Watch Minigames Watch App
//
//  Fixed-timestep 2D ball physics: fairway wall collisions, obstacles,
//  cup capture, camera follow and lightweight particles.
//

import CoreGraphics
import Foundation
import SwiftUI
import WatchKit

enum GolfBallState: Equatable {
    case intro          // flyover pan from cup to tee
    case ready          // at rest, can aim
    case rolling
    case teleporting    // riding a portal (suck in, glide, pop out)
    case sinking        // falling into the cup (animation)
    case done
}

enum GolfEvent {
    case sunk(strokes: Int)
}

final class GolfEngine {

    // MARK: Static config

    static let ballRadius = 6.0
    static let cupRadius = 10.0
    static let maxShotSpeed = 420.0
    static let maxDragPoints = 120.0

    // MARK: Course

    let hole: HoleDesign
    let geo: FairwayGeometry

    // Cached obstacle collision data
    struct ArcData { let id: UUID; let points: [Vec2] }
    struct BarrierData { let id: UUID; let a: Vec2; let b: Vec2 }
    struct CircleData { let id: UUID; let pos: Vec2; let r: Double }
    struct BoostData { let id: UUID; let pos: Vec2; let dir: Vec2; let halfW: Double; let halfL: Double; let rot: Double }
    struct SpinnerData { let id: UUID; let pos: Vec2; let armLen: Double; let phase: Double }
    struct FanData { let id: UUID; let pos: Vec2; let dir: Vec2; let halfW: Double; let len: Double }
    struct PortalData { let id: UUID; let entry: Vec2; let exit: Vec2; let r: Double }

    private(set) var arcs: [ArcData] = []
    private(set) var barriers: [BarrierData] = []
    private(set) var pillars: [CircleData] = []
    private(set) var bumpers: [CircleData] = []
    private(set) var sands: [CircleData] = []
    private(set) var boosts: [BoostData] = []
    private(set) var spinners: [SpinnerData] = []
    private(set) var coins: [CircleData] = []
    private(set) var hills: [CircleData] = []
    private(set) var vortices: [CircleData] = []
    private(set) var fans: [FanData] = []
    private(set) var portals: [PortalData] = []

    /// True when the hole holds anything that can move or wake a resting
    /// ball: spinner arms sweep, and hill/vortex/fan fields push on position
    /// alone. Everything else (bumpers, boosts, sand, walls) only ever acts
    /// on a moving ball, so a static hole can skip resting substeps outright.
    private let hasActiveField: Bool

    // MARK: Dynamic state

    var ballPos: Vec2
    var ballVel = Vec2.zero
    var state: GolfBallState = .intro
    var strokes = 0
    var collectedCoins = Set<UUID>()
    var brokenBarriers = Set<UUID>()
    /// Portals already ridden — each pair works exactly once per attempt.
    var usedPortals = Set<UUID>()
    /// id -> time the spent pair started fading out.
    var portalFadeStart: [UUID: Double] = [:]
    /// id -> time of last hit, for flash animations.
    var bumperFlash: [UUID: Double] = [:]
    var barrierFlash: [UUID: Double] = [:]
    var particles: [Particle] = []
    var floaters: [Floater] = []
    var time: Double = 0

    /// Screen shake kicked by hard impacts, decayed every frame.
    var shakeAmp = 0.0
    /// Last solid contact, for the ball's impact squash.
    var lastHitAt = -10.0
    var lastHitNormal = Vec2(0, -1)

    /// 0..1 shrink factor while sinking.
    var ballDrawScale = 1.0
    var cam: Vec2
    var zoom = 1.0
    /// Crown sets the target; `zoom` eases toward it every frame.
    var zoomTarget = 1.0

    /// Live drag while aiming, in screen points.
    var aimDrag: CGSize? = nil

    var onEvent: ((GolfEvent) -> Void)?

    private var lastDate: Date?
    private var accumulator = 0.0
    private var shotOrigin: Vec2
    private var introStart: Double? = nil
    private var sinkStart = 0.0
    private var sinkFrom = Vec2.zero
    private var padsInside = Set<UUID>()
    private var lastContainCheck = 0.0
    /// An in-flight portal ride.
    private struct TeleportRide {
        let portalID: UUID
        let from: Vec2
        let entry: Vec2
        let exit: Vec2
        let vel: Vec2
        let start: Double
        let suck: Double
        let glide: Double
        let pop: Double
    }
    private var ride: TeleportRide? = nil
    private var ridePopped = false

    // MARK: Init

    init(hole: HoleDesign) {
        self.hole = hole
        self.geo = FairwayGeometry(paths: hole.allPaths)

        var tee = hole.tee
        if !geo.contains(tee) { tee = geo.nearestCenterPoint(to: tee) }
        self.ballPos = tee
        self.shotOrigin = tee
        self.cam = hole.cup

        for o in hole.obstacles {
            switch o.kind {
            case .arcWall: arcs.append(ArcData(id: o.id, points: o.arcPoints))
            case .barrier:
                let (a, b) = o.barrierEndpoints
                barriers.append(BarrierData(id: o.id, a: a, b: b))
            case .pillar: pillars.append(CircleData(id: o.id, pos: o.pos, r: o.pillarRadius))
            case .bumper: bumpers.append(CircleData(id: o.id, pos: o.pos, r: o.bumperRadius))
            case .sand: sands.append(CircleData(id: o.id, pos: o.pos, r: o.sandRadius))
            case .boost:
                boosts.append(BoostData(id: o.id, pos: o.pos, dir: o.direction,
                                        halfW: o.boostHalfWidth, halfL: o.boostHalfLength, rot: o.rot))
            case .spinner:
                spinners.append(SpinnerData(id: o.id, pos: o.pos, armLen: o.spinnerArmLength,
                                            phase: o.seed * .pi * 2))
            case .coin: coins.append(CircleData(id: o.id, pos: o.pos, r: o.coinRadius))
            case .hill: hills.append(CircleData(id: o.id, pos: o.pos, r: o.hillRadius))
            case .vortex: vortices.append(CircleData(id: o.id, pos: o.pos, r: o.vortexRadius))
            case .fan:
                fans.append(FanData(id: o.id, pos: o.pos, dir: o.direction,
                                    halfW: o.fanZoneHalfWidth, len: o.fanZoneLength))
            case .portal:
                portals.append(PortalData(id: o.id, entry: o.pos, exit: o.portalExit,
                                          r: o.portalRadius))
            case .tree:
                // Trees collide like small pillars.
                pillars.append(CircleData(id: o.id, pos: o.pos, r: o.treeRadius))
            case .flowers:
                break   // purely decorative
            }
        }
        hasActiveField = !spinners.isEmpty || !fans.isEmpty
            || !vortices.isEmpty || !hills.isEmpty
    }

    // MARK: Aiming / shooting

    var canAim: Bool { state == .ready }

    /// Shot vector (unit direction + power 0...1) from the current drag.
    var aimShot: (dir: Vec2, power: Double)? {
        guard let d = aimDrag else { return nil }
        let v = Vec2(-Double(d.width), -Double(d.height))
        let len = v.length
        guard len > 10 else { return nil }
        return (v.normalized, min(len / Self.maxDragPoints, 1))
    }

    func updateAim(drag: CGSize) {
        if state == .intro { skipIntro() }
        guard canAim else { return }
        aimDrag = drag
    }

    func releaseAim() {
        defer { aimDrag = nil }
        guard canAim, let shot = aimShot else { return }
        let speed = 55 + pow(shot.power, 0.85) * (Self.maxShotSpeed - 55)
        ballVel = shot.dir * speed
        strokes += 1
        state = .rolling
        shotOrigin = ballPos
        padsInside.removeAll()
        Haptics.play(.start, minInterval: 0)
    }

    func skipIntro() {
        guard state == .intro else { return }
        // No camera snap — updateCamera eases in from wherever the pan was.
        state = .ready
        introStart = nil
    }

    // MARK: Stepping

    func step(to date: Date) {
        guard let last = lastDate else {
            lastDate = date
            introStart = time
            return
        }
        var dt = date.timeIntervalSince(last)
        lastDate = date
        dt = max(0, min(dt, 1.0 / 20.0))
        time += dt
        shakeAmp *= exp(-7 * dt)
        floaters.removeAll { time - $0.bornAt > 0.95 }

        updateIntro()
        updateTeleport()
        updateSinking()

        // Substep while resting too: moving obstacles (spinners) must still
        // collide with a stationary ball and shove it back into play. On a
        // hole with no active fields a resting substep is an exact no-op —
        // skip the physics but keep draining the accumulator so the next
        // shot picks up with the same clock phase instead of burst-stepping.
        if state == .rolling || state == .ready {
            accumulator += dt
            let h = 1.0 / 240.0
            let simulate = state == .rolling || hasActiveField
            var steps = 0
            while accumulator >= h && steps < 24 {
                if simulate { substep(h) }
                accumulator -= h
                steps += 1
            }
        }

        updateParticles(&particles, dt: dt, drag: 2.6, confettiGravity: 170)
        updateCamera(dt)
    }

    private func updateIntro() {
        guard state == .intro, let start = introStart else { return }
        let t = (time - start) / 1.9
        if t >= 1 {
            skipIntro()
        } else {
            let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            cam = hole.cup.lerp(to: ballPos, e)
        }
    }

    private func updateTeleport() {
        guard state == .teleporting, let ride else { return }
        let t = time - ride.start
        if t < ride.suck {
            // Shrink into the mouth.
            let u = t / ride.suck
            ballPos = ride.from.lerp(to: ride.entry, u * u)
            ballDrawScale = 1 - u
        } else if t < ride.suck + ride.glide {
            // Invisible transit: the position glides so the camera rides along.
            let u = (t - ride.suck) / ride.glide
            let e = u * u * (3 - 2 * u)
            ballPos = ride.entry.lerp(to: ride.exit, e)
            ballDrawScale = 0
        } else if t < ride.suck + ride.glide + ride.pop {
            if !ridePopped {
                ridePopped = true
                spawnSparkle(at: ride.exit)
                Haptics.play(.start, minInterval: 0)
            }
            ballPos = ride.exit
            ballDrawScale = (t - ride.suck - ride.glide) / ride.pop
        } else {
            ballPos = ride.exit
            ballDrawScale = 1
            ballVel = ride.vel
            state = .rolling
            // The spent pair fades away.
            portalFadeStart[ride.portalID] = time
            spawnPuff(at: ride.entry, color: .white)
            self.ride = nil
        }
    }

    private func updateSinking() {
        guard state == .sinking else { return }
        let t = (time - sinkStart) / 0.55
        if t >= 1 {
            state = .done
            ballDrawScale = 0
            spawnConfetti(at: hole.cup)
            floaters.append(Floater(
                pos: hole.cup + Vec2(0, -20), text: sinkTitle, bornAt: time,
                color: strokes <= hole.par ? Palette.goldDeep : Palette.wallTop))
            Haptics.play(.success, minInterval: 0)
            notifyMainAsync(onEvent, .sunk(strokes: strokes))
        } else {
            let e = t * t
            ballPos = sinkFrom.lerp(to: hole.cup, min(1, t * 1.6))
            ballDrawScale = 1 - e * 0.9
        }
    }

    private func substep(_ h: Double) {
        var maxImpact = 0.0

        // -- Friction (heavier in sand)
        let inSand = sands.contains { $0.pos.distance(to: ballPos) < $0.r + Self.ballRadius * 0.4 }
        let expDamp = inSand ? 3.6 : 0.85
        let linDamp = inSand ? 95.0 : 22.0
        let speed0 = ballVel.length
        if speed0 > 0 {
            var s = speed0 * exp(-expDamp * h) - linDamp * h
            if s < 0 { s = 0 }
            ballVel = ballVel.normalized * s
        }

        // -- Cup gravity assist + capture
        let cupVec = hole.cup - ballPos
        let cupDist = cupVec.length
        let speed = ballVel.length
        if cupDist < Self.cupRadius && state == .rolling {
            // Any speed sinks — no lip-outs.
            beginSink()
            return
        } else if cupDist < 26, speed > 1, speed < 150 {
            let pull = 95.0 * (1 - cupDist / 26)
            ballVel += cupVec.normalized * pull * h
        }

        // -- Field forces: hills push the ball off, vortices pull it in with a
        // swirl, fans blow a steady breeze down their zone.
        for hill in hills {
            let delta = ballPos - hill.pos
            let d = delta.length
            if d < hill.r, d > 1e-6 {
                let f = (d / hill.r) * (1 - d / hill.r) * 4   // peaks mid-slope
                ballVel += (delta / d) * (300 * f * h)
            }
        }
        for vortex in vortices {
            let delta = vortex.pos - ballPos
            let d = delta.length
            if d < vortex.r, d > 1e-6 {
                // Pull stays strong out to the rim so a caught ball keeps
                // creeping inward instead of stalling against friction.
                let f = 0.35 + 0.65 * (1 - d / vortex.r)
                let inward = delta / d
                ballVel += (inward * 260 + inward.perp * 150) * (f * h)
            }
        }
        for fan in fans {
            let rel = ballPos - fan.pos
            let along = rel.dot(fan.dir)
            if along > 4, along < fan.len, abs(rel.dot(fan.dir.perp)) < fan.halfW {
                ballVel += fan.dir * (240 * (1 - along / fan.len) * h)
            }
        }

        // -- Integrate
        ballPos += ballVel * h

        // -- Fairway walls. The fairway is every point within half-width of
        // the centerline, so the wall is just that distance limit. This stays
        // correct where a tight bend overlaps itself, which a polygon outline
        // cannot express.
        let near = geo.nearest(ballPos)
        let limit = max(1.0, near.half - Self.ballRadius)
        if near.dist > limit {
            let outward = near.dist > 1e-6 ? (ballPos - near.point) / near.dist : Vec2(0, -1)
            ballPos = near.point + outward * limit
            let into = ballVel.dot(outward)
            if into > 0 {
                ballVel -= outward * into * 1.78
                maxImpact = max(maxImpact, into)
                registerHit(normal: -outward,
                            contact: ballPos + outward * Self.ballRadius,
                            impact: into)
            }
        }

        // -- Arc walls (thick: half thickness 3)
        for arc in arcs {
            for i in 0..<(arc.points.count - 1) {
                collideSegment(arc.points[i], arc.points[i + 1],
                               radius: Self.ballRadius + 3, restitution: 0.78, impact: &maxImpact)
            }
        }

        // -- Breakable barriers
        for barrier in barriers where !brokenBarriers.contains(barrier.id) {
            let closest = closestPointOnSegment(ballPos, barrier.a, barrier.b)
            let delta = ballPos - closest
            let dist = delta.length
            let rr = Self.ballRadius + 3.5
            if dist < rr {
                let normal = dist > 1e-6 ? delta / dist : Vec2(0, -1)
                let approach = -ballVel.dot(normal)
                if approach > 155 {
                    brokenBarriers.insert(barrier.id)
                    ballVel = ballVel * 0.72
                    shakeAmp = max(shakeAmp, 3)
                    spawnShards(at: closest, along: (barrier.b - barrier.a).normalized)
                    Haptics.play(.retry, minInterval: 0)
                } else {
                    ballPos = closest + normal * rr
                    if ballVel.dot(normal) < 0 {
                        ballVel -= normal * ballVel.dot(normal) * 1.6
                        barrierFlash[barrier.id] = time
                        maxImpact = max(maxImpact, approach)
                    }
                }
            }
        }

        // -- Pillars
        for pillar in pillars {
            collideCircle(center: pillar.pos, r: pillar.r, restitution: 0.75, impact: &maxImpact)
        }

        // -- Bumpers: bouncy, add energy
        for bumper in bumpers {
            let delta = ballPos - bumper.pos
            let dist = delta.length
            let rr = bumper.r + Self.ballRadius
            if dist < rr {
                let normal = dist > 1e-6 ? delta / dist : Vec2(0, -1)
                ballPos = bumper.pos + normal * rr
                let into = ballVel.dot(normal)
                if into < 0 {
                    ballVel -= normal * into * 2.05
                    ballVel += normal * 85
                    if ballVel.length > 520 { ballVel = ballVel.normalized * 520 }
                    bumperFlash[bumper.id] = time
                    lastHitAt = time
                    lastHitNormal = normal
                    shakeAmp = max(shakeAmp, 1.6)
                    Haptics.play(.directionUp, minInterval: 0.09)
                    spawnPuff(at: bumper.pos + normal * bumper.r, color: .white)
                }
            }
        }

        // -- Spinners: rotating arms behave as moving walls
        for spinner in spinners {
            let omega = 1.7
            let base = time * omega + spinner.phase
            for arm in 0..<3 {
                let ang = base + Double(arm) * (.pi * 2 / 3)
                let dir = Vec2(cos(ang), sin(ang))
                let tip = spinner.pos + dir * spinner.armLen
                let closest = closestPointOnSegment(ballPos, spinner.pos, tip)
                let delta = ballPos - closest
                let dist = delta.length
                let rr = Self.ballRadius + 2.8
                if dist < rr {
                    let normal = dist > 1e-6 ? delta / dist : dir.perp
                    // Velocity of the arm at the contact point.
                    let radiusVec = closest - spinner.pos
                    let armVel = radiusVec.perp * omega
                    ballPos = closest + normal * rr
                    let rel = ballVel - armVel
                    if rel.dot(normal) < 0 {
                        let reflected = rel - normal * rel.dot(normal) * 1.7
                        ballVel = reflected + armVel
                        maxImpact = max(maxImpact, -rel.dot(normal))
                        Haptics.play(.directionDown, minInterval: 0.15)
                    }
                }
            }
        }

        // -- Boost pads (fire once per entry)
        for pad in boosts {
            let local = ballPos - pad.pos
            let rotated = local.rotated(by: -pad.rot)
            let inside = abs(rotated.x) < pad.halfW && abs(rotated.y) < pad.halfL
            if inside {
                if !padsInside.contains(pad.id) {
                    padsInside.insert(pad.id)
                    let boosted = max(ballVel.length * 1.05, 300)
                    ballVel = pad.dir * min(boosted, 430)
                    Haptics.play(.start, minInterval: 0.15)
                    spawnPuff(at: ballPos, color: .white)
                }
            } else {
                padsInside.remove(pad.id)
            }
        }

        // -- Coins
        for coin in coins where !collectedCoins.contains(coin.id) {
            if coin.pos.distance(to: ballPos) < coin.r + Self.ballRadius {
                collectedCoins.insert(coin.id)
                spawnSparkle(at: coin.pos)
                floaters.append(Floater(pos: coin.pos + Vec2(0, -12), text: "+1",
                                        bornAt: time, color: Palette.goldDeep))
                Haptics.play(.click, minInterval: 0)
            }
        }

        // -- Portals: one way, one use — the pair vanishes after the ride.
        for p in portals where !usedPortals.contains(p.id)
            && ballPos.distance(to: p.entry) < p.r + Self.ballRadius * 0.5 {
            // Smooth ride instead of an instant jump: shrink into the
            // mouth, glide the view to the pad, pop back out.
            let distance = p.entry.distance(to: p.exit)
            ride = TeleportRide(portalID: p.id, from: ballPos, entry: p.entry,
                                exit: p.exit, vel: ballVel, start: time, suck: 0.16,
                                glide: min(max(distance / 700, 0.2), 0.7),
                                pop: 0.16)
            ridePopped = false
            state = .teleporting
            ballVel = .zero
            usedPortals.insert(p.id)
            spawnPuff(at: p.entry, color: .white)
            Haptics.play(.click, minInterval: 0)
            break
        }

        if maxImpact > 0 {
            Haptics.bounce(impactSpeed: maxImpact)
            // Hard hits rattle the camera a little.
            if maxImpact > 130 {
                shakeAmp = max(shakeAmp, min(maxImpact / 110, 3.2))
            }
        }

        // -- Rest detection / wake-up
        if state == .rolling && ballVel.length < 7 {
            ballVel = .zero
            state = .ready
            shotOrigin = ballPos
        } else if state == .ready && ballVel.length > 12 {
            // A spinner arm (or other moving obstacle) knocked the resting ball.
            state = .rolling
        }

        // -- Escape safety net
        if time - lastContainCheck > 0.5 {
            lastContainCheck = time
            if !ballPos.x.isFinite || !ballPos.y.isFinite || !geo.contains(ballPos) {
                ballPos = geo.contains(shotOrigin) ? shotOrigin : geo.nearestCenterPoint(to: shotOrigin)
                ballVel = .zero
                state = .ready
                Haptics.play(.failure, minInterval: 0.5)
            }
        }
    }

    private func beginSink() {
        state = .sinking
        sinkStart = time
        sinkFrom = ballPos
        spawnSparkle(at: hole.cup)
    }

    /// The scoreline for the hole just played ("Birdie!", "Bogey"…).
    var sinkTitle: String {
        if strokes == 1 { return "Ace!" }
        switch strokes - hole.par {
        case ..<(-1): return "Eagle!"
        case -1: return "Birdie!"
        case 0: return "Par"
        case 1: return "Bogey"
        default: return "+\(strokes - hole.par)"
        }
    }

    /// Records a solid contact: squash orientation, and a dust puff when the
    /// ball really slams in.
    private func registerHit(normal: Vec2, contact: Vec2, impact: Double) {
        guard impact > 34 else { return }
        lastHitAt = time
        lastHitNormal = normal
        if impact > 100 {
            spawnPuff(at: contact, color: .shard)
        }
    }

    private func collideSegment(_ a: Vec2, _ b: Vec2, radius: Double,
                                restitution: Double, impact: inout Double) {
        let closest = closestPointOnSegment(ballPos, a, b)
        let delta = ballPos - closest
        let dist = delta.length
        guard dist < radius else { return }
        let normal = dist > 1e-6 ? delta / dist : (b - a).normalized.perp
        ballPos = closest + normal * radius
        let into = ballVel.dot(normal)
        if into < 0 {
            ballVel -= normal * into * (1 + restitution)
            impact = max(impact, -into)
            registerHit(normal: normal, contact: closest, impact: -into)
        }
    }

    private func collideCircle(center: Vec2, r: Double, restitution: Double, impact: inout Double) {
        let delta = ballPos - center
        let dist = delta.length
        let rr = r + Self.ballRadius
        guard dist < rr else { return }
        let normal = dist > 1e-6 ? delta / dist : Vec2(0, -1)
        ballPos = center + normal * rr
        let into = ballVel.dot(normal)
        if into < 0 {
            ballVel -= normal * into * (1 + restitution)
            impact = max(impact, -into)
            registerHit(normal: normal, contact: center + normal * r, impact: -into)
        }
    }

    // MARK: Camera

    private func updateCamera(_ dt: Double) {
        // Zoom always eases toward the crown's target, even during the intro.
        zoom += (1 - exp(-8.0 * dt)) * (zoomTarget - zoom)
        // Settle-snap: once the ease is inside a sub-pixel margin, land it
        // exactly so a resting scene stops changing frame to frame.
        if abs(zoom - zoomTarget) < 0.0005 { zoom = zoomTarget }

        guard state != .intro else { return }
        var target = ballPos
        if state == .ready, let shot = aimShot {
            target = ballPos + shot.dir * (shot.power * 34)
        }
        // Keep the camera inside the course bounds (with breathing room).
        let inset = 30.0
        let b = geo.bounds.insetBy(dx: -inset, dy: -inset)
        target.x = min(max(target.x, b.minX), b.maxX)
        target.y = min(max(target.y, b.minY), b.maxY)
        // Exponential ease: frame-rate-independent fraction of the remaining
        // distance every frame, so the camera glides with no snaps. Portal
        // rides track tighter so the view keeps up with the transit.
        let rate = state == .teleporting ? 9.0 : 6.0
        let k = 1 - exp(-rate * dt)
        cam = cam.lerp(to: target, k)
        // 0.005 world units is ~0.01 screen points — invisible, and applied
        // to the whole scene at once.
        if cam.distance(to: target) < 0.005 { cam = target }
    }

    // MARK: Particles

    /// Celebration burst when the ball drops in.
    private func spawnConfetti(at p: Vec2) {
        for k in 0..<36 {
            let a = Double.random(in: 0..<(2 * .pi))
            let s = Double.random(in: 40...180)
            var v = Vec2(cos(a), sin(a)) * s
            v.y -= Double.random(in: 70...190)   // pop upward first
            let life = Double.random(in: 0.7...1.4)
            particles.append(Particle(pos: p, vel: v, life: life, maxLife: life,
                                      size: Double.random(in: 1.8...3.4),
                                      hue: .confetti(k)))
        }
    }

    private func spawnSparkle(at p: Vec2) {
        for _ in 0..<9 {
            let a = Double.random(in: 0..<(2 * .pi))
            let s = Double.random(in: 24...85)
            particles.append(Particle(pos: p, vel: Vec2(cos(a), sin(a)) * s,
                                      life: 0.55, maxLife: 0.55,
                                      size: Double.random(in: 1.4...2.6), hue: .gold))
        }
    }

    private func spawnShards(at p: Vec2, along dir: Vec2) {
        for _ in 0..<10 {
            let spread = dir * Double.random(in: -18...18)
            let n = dir.perp * Double.random(in: -70...70)
            particles.append(Particle(pos: p + spread * 0.2, vel: spread + n,
                                      life: 0.6, maxLife: 0.6,
                                      size: Double.random(in: 1.6...3.2), hue: .shard))
        }
    }

    private func spawnPuff(at p: Vec2, color: Particle.ParticleHue) {
        for _ in 0..<5 {
            let a = Double.random(in: 0..<(2 * .pi))
            particles.append(Particle(pos: p, vel: Vec2(cos(a), sin(a)) * Double.random(in: 12...40),
                                      life: 0.35, maxLife: 0.35,
                                      size: Double.random(in: 1.2...2.2), hue: color))
        }
    }
}
