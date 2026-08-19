//
//  PongEngine.swift
//  Watch Minigames Watch App
//
//  Super Pong: crown-controlled paddle vs a smooth predictive bot, with
//  charge-up smash attacks, power orbs, particles and haptics.
//

import CoreGraphics
import Foundation
import WatchKit

final class PongEngine {

    enum Side { case player, bot }

    struct Orb {
        enum Kind: CaseIterable { case bolt, grow }
        var kind: Kind
        var pos: Vec2
        var born: Double
    }

    // MARK: Config

    static let ballR = 4.5
    static let paddleW = 5.5
    static let basePaddleH = 36.0
    static let paddleInset = 12.0
    static let winScore = 5
    static let playerChargeMax = 3
    /// Seconds an uncollected orb stays on court.
    static let orbLife = 9.0

    /// 0 easy, 1 medium, 2 hard.
    var difficulty = 2

    /// Bot returns needed to arm its smash; easy bots never smash.
    /// Defaults absorb any out-of-range difficulty, like botMaxSpeed().
    var botChargeThreshold: Int {
        switch difficulty { case 0: return 99; case 1: return 5; default: return 4 }
    }
    private var botEaseRate: Double {
        switch difficulty { case 0: return 5.0; case 1: return 6.5; default: return 8.0 }
    }
    private var botErrorRange: Double {
        switch difficulty { case 0: return 26.0; case 1: return 16.0; default: return 9.0 }
    }

    /// Court size in world units — the view keeps this matched to the screen.
    var courtW = 180.0
    var courtH = 200.0

    // MARK: State

    var ballPos = Vec2(90, 100)
    var ballVel = Vec2.zero
    var trail: [Vec2] = []
    var playerY = 100.0
    var playerTarget = 100.0
    var botY = 100.0
    var playerScore = 0
    var botScore = 0
    var playerCharge = 0
    var botCharge = 0
    var playerGrowUntil = -1.0
    var botGrowUntil = -1.0
    /// The ball is currently a smash shot (renders hot).
    var smashActive = false
    var orb: Orb? = nil
    var lastHitter: Side? = nil
    var particles: [Particle] = []
    /// Expanding impact rings drawn by the renderer.
    struct Ripple { let pos: Vec2; let at: Double; let gold: Bool }
    var ripples: [Ripple] = []
    /// Timing for juice: ball squash, paddle bumps, score number flashes.
    var lastHitAt = -10.0
    var playerHitAt = -10.0
    var botHitAt = -10.0
    var lastScoreAt = -10.0
    var lastScoreSide: Side? = nil
    var time = 0.0
    /// Screen-shake amplitude, decays after smashes and scores.
    var shakeAmp = 0.0
    /// Pending serve fire time; ball waits at center until then.
    var serveAt: Double? = 0.9
    var gameOver: Side? = nil

    var onGameOver: ((Side) -> Void)?

    private var lastDate: Date?
    private var matchStart = 0.0
    var serveToward: Side = .player
    private var nextOrbAt = 4.0
    private var botError = 0.0

    /// Rally pace: creeps up slowly over the match (~+130 per minute) so
    /// games escalate gradually. Smashes spike above it; returns settle back
    /// onto it.
    var pace: Double { min(150 + (time - matchStart) * 2.2, 300) }

    var playerH: Double { Self.basePaddleH * (time < playerGrowUntil ? 1.55 : 1) }
    var botH: Double { Self.basePaddleH * (time < botGrowUntil ? 1.55 : 1) }
    var playerSmashReady: Bool { playerCharge >= Self.playerChargeMax }

    init() {
        botY = courtH / 2
        playerY = courtH / 2
        ballPos = Vec2(courtW / 2, courtH / 2)
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
        updateParticles(&particles, dt: dt, drag: 3.2)
        ripples.removeAll { time - $0.at > 0.5 }

        guard gameOver == nil else { return }

        // Paddles: crown target for the player, prediction for the bot —
        // both eased so movement stays silky.
        playerY += (playerTarget - playerY) * (1 - exp(-20 * dt))
        playerY = min(max(playerY, playerH / 2), courtH - playerH / 2)

        let target = botTargetY()
        var move = (target - botY) * (1 - exp(-botEaseRate * dt))
        let cap = botMaxSpeed() * dt
        move = min(max(move, -cap), cap)
        botY = min(max(botY + move, botH / 2), courtH - botH / 2)

        // Serve pause.
        if let s = serveAt {
            ballPos = Vec2(courtW / 2, courtH / 2)
            if time >= s {
                serveAt = nil
                launch()
            }
            return
        }

        // Ball.
        let oldX = ballPos.x
        ballPos += ballVel * dt
        trail.append(ballPos)
        if trail.count > 14 { trail.removeFirst() }

        // Smash shots shed embers as they fly.
        if smashActive, Int(time * 40) != Int((time - dt) * 40) {
            let life = Double.random(in: 0.2...0.4)
            particles.append(Particle(
                pos: ballPos + Vec2(Double.random(in: -2...2), Double.random(in: -2...2)),
                vel: ballVel * -0.08 + Vec2(Double.random(in: -20...20), Double.random(in: -20...20)),
                life: life, maxLife: life,
                size: Double.random(in: 1.2...2.2), hue: .gold))
        }

        if ballPos.y < Self.ballR {
            ballPos.y = Self.ballR
            ballVel.y = abs(ballVel.y)
            wallTouch()
        } else if ballPos.y > courtH - Self.ballR {
            ballPos.y = courtH - Self.ballR
            ballVel.y = -abs(ballVel.y)
            wallTouch()
        }

        // Swept paddle tests so a fast ball can't tunnel through.
        let playerPlane = courtW - Self.paddleInset
        let botPlane = Self.paddleInset
        if ballVel.x > 0, oldX <= playerPlane, ballPos.x >= playerPlane {
            let t = (playerPlane - oldX) / (ballPos.x - oldX)
            let yAt = ballPos.y - ballVel.y * dt * (1 - t)
            if abs(yAt - playerY) < playerH / 2 + Self.ballR {
                ballPos.x = playerPlane
                ballPos.y = yAt
                hit(by: .player)
            }
        } else if ballVel.x < 0, oldX >= botPlane, ballPos.x <= botPlane {
            let t = (botPlane - oldX) / (ballPos.x - oldX)
            let yAt = ballPos.y - ballVel.y * dt * (1 - t)
            if abs(yAt - botY) < botH / 2 + Self.ballR {
                ballPos.x = botPlane
                ballPos.y = yAt
                hit(by: .bot)
            }
        }

        // Goals.
        if ballPos.x > courtW + 10 {
            score(for: .bot)
        } else if ballPos.x < -10 {
            score(for: .player)
        }

        updateOrb()
    }

    // MARK: Bot

    private func botTargetY() -> Double {
        guard ballVel.x < -1, serveAt == nil else { return courtH / 2 }
        // Predict the intercept, folding wall bounces.
        let t = (ballPos.x - Self.paddleInset) / -ballVel.x
        var y = ballPos.y + ballVel.y * t
        let span = courtH - Self.ballR * 2
        y = (y - Self.ballR).truncatingRemainder(dividingBy: span * 2)
        if y < 0 { y += span * 2 }
        if y > span { y = span * 2 - y }
        return y + Self.ballR + botError
    }

    private func botMaxSpeed() -> Double {
        // Scales with the match pace, plus gentle rubber-banding when behind.
        let edge = Double(botScore - playerScore)
        switch difficulty {
        case 0: return min(max(60 + pace * 0.15 - edge * 8, 50), 115)
        case 1: return min(max(75 + pace * 0.20 - edge * 9, 65), 150)
        default: return min(max(95 + pace * 0.25 - edge * 10, 90), 185)
        }
    }

    // MARK: Rally

    private func launch() {
        let angle = Double.random(in: -0.55...0.55)
        let dir: Double = serveToward == .player ? 1 : -1
        ballVel = Vec2(cos(angle) * dir, sin(angle)) * (pace * 0.9)
        smashActive = false
        trail.removeAll()
        Haptics.play(.start, minInterval: 0)
    }

    private func hit(by side: Side) {
        let paddleY = side == .player ? playerY : botY
        let h = side == .player ? playerH : botH
        let off = min(max((ballPos.y - paddleY) / (h / 2), -1), 1)

        // Every return travels at the current match pace — escalation comes
        // from the clock, not from compounding hits. This also means a
        // returned smash automatically cools back down.
        var speed = pace
        var smashed = false
        if side == .player, playerCharge >= Self.playerChargeMax {
            playerCharge = 0
            smashed = true
        } else if side == .bot, botCharge >= botChargeThreshold {
            botCharge = 0
            smashed = true
        } else if side == .player {
            playerCharge += 1
        } else {
            botCharge += 1
        }
        if smashed {
            speed = min(speed * 1.5 + 60, 450)
            shakeAmp = 5
            spawnRing(at: ballPos, hue: .gold)
            Haptics.play(.directionUp, minInterval: 0)
        } else {
            Haptics.play(.click, minInterval: 0.05)
        }
        smashActive = smashed
        lastHitAt = time
        if side == .player { playerHitAt = time } else { botHitAt = time }
        ripples.append(Ripple(pos: ballPos, at: time, gold: smashed))

        let angle = off * 0.85
        let dir: Double = side == .player ? -1 : 1
        ballVel = Vec2(cos(angle) * dir, sin(angle)) * speed
        lastHitter = side
        botError = Double.random(in: -botErrorRange...botErrorRange)
        spawnSparks(at: ballPos, side: side, smashed: smashed)
    }

    private func wallTouch() {
        Haptics.play(.click, minInterval: 0.12)
        spawnPuff(at: ballPos)
        ripples.append(Ripple(pos: ballPos, at: time, gold: false))
    }

    private func score(for side: Side) {
        if side == .player { playerScore += 1 } else { botScore += 1 }
        lastScoreAt = time
        lastScoreSide = side
        shakeAmp = 4
        spawnGoalBurst(at: ballPos, happy: side == .player)

        let winner: Side? = playerScore >= Self.winScore ? .player
            : (botScore >= Self.winScore ? .bot : nil)
        if let winner {
            gameOver = winner
            if winner == .player {
                spawnGoalBurst(at: Vec2(courtW / 2, courtH / 2), happy: true)
                Haptics.celebrate()
            } else {
                Haptics.bigLoss()
            }
            notifyMainAsync(onGameOver, winner)
            return
        }
        Haptics.play(side == .player ? .success : .failure, minInterval: 0)
        serveToward = side == .player ? .bot : .player
        serveAt = time + 0.9
        ballVel = .zero
        trail.removeAll()
        smashActive = false
    }

    func reset() {
        matchStart = time
        playerScore = 0
        botScore = 0
        playerCharge = 0
        botCharge = 0
        playerGrowUntil = -1
        botGrowUntil = -1
        smashActive = false
        gameOver = nil
        orb = nil
        nextOrbAt = time + 3
        serveToward = Bool.random() ? .player : .bot
        serveAt = time + 0.9
        ballVel = .zero
        trail.removeAll()
        particles.removeAll()
        ripples.removeAll()
        botError = 0
        lastHitter = nil
        lastHitAt = -10
        playerHitAt = -10
        botHitAt = -10
        lastScoreAt = -10
        lastScoreSide = nil
        shakeAmp = 0
    }

    // MARK: Orbs

    private func updateOrb() {
        if let o = orb {
            if time - o.born > Self.orbLife {
                orb = nil
                nextOrbAt = time + Double.random(in: 4...7)
            } else if o.pos.distance(to: ballPos) < 9 + Self.ballR {
                apply(o)
                orb = nil
                nextOrbAt = time + Double.random(in: 5...8)
            }
        } else if time > nextOrbAt, serveAt == nil {
            orb = Orb(kind: Orb.Kind.allCases.randomElement()!,
                      pos: Vec2(Double.random(in: courtW * 0.3...courtW * 0.7),
                                Double.random(in: 34...(courtH - 34))),
                      born: time)
        }
    }

    private func apply(_ o: Orb) {
        let side = lastHitter ?? .player
        switch o.kind {
        case .bolt:
            if side == .player { playerCharge = Self.playerChargeMax }
            else { botCharge = botChargeThreshold }
        case .grow:
            if side == .player { playerGrowUntil = time + 7 }
            else { botGrowUntil = time + 7 }
        }
        spawnRing(at: o.pos, hue: o.kind == .bolt ? .gold : .white)
        Haptics.play(.click, minInterval: 0)
    }

    // MARK: Particles

    private func spawnSparks(at p: Vec2, side: Side, smashed: Bool) {
        spawnRadialBurst(into: &particles, at: p, count: smashed ? 16 : 8,
                         speed: 30...(smashed ? 190 : 110), life: 0.25...0.5,
                         size: 1.4...2.6) { _ in smashed ? .gold : .white }
    }

    private func spawnPuff(at p: Vec2) {
        spawnRadialBurst(into: &particles, at: p, count: 4, speed: 15...45,
                         life: 0.2...0.35, size: 1.2...2) { _ in .shard }
    }

    private func spawnRing(at p: Vec2, hue: Particle.ParticleHue) {
        for k in 0..<14 {
            let a = Double(k) / 14 * 2 * .pi
            particles.append(Particle(pos: p, vel: Vec2(cos(a), sin(a)) * 120,
                                      life: 0.4, maxLife: 0.4, size: 2.2, hue: hue))
        }
    }

    private func spawnGoalBurst(at p: Vec2, happy: Bool) {
        let clamped = Vec2(min(max(p.x, 10), courtW - 10), min(max(p.y, 10), courtH - 10))
        spawnRadialBurst(into: &particles, at: clamped, count: 26, speed: 50...200,
                         life: 0.5...1.0, size: 1.8...3.2) { happy ? .confetti($0) : .shard }
    }
}
