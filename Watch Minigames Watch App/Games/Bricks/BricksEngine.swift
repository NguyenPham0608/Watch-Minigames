//
//  BricksEngine.swift
//  Watch Minigames Watch App
//
//  Brick Breaker simulation: serving, swept ball collisions, endless
//  levels that rebuild a little meaner each clear.
//

import SwiftUI

final class BricksEngine {

    struct Brick {
        var rect: CGRect
        var colorIndex: Int
        var hp: Int
    }

    enum State {
        case serving
        case playing
        case done
    }

    static let ballR = 4.5
    static let paddleW = 42.0
    static let paddleH = 7.0

    var courtW = 180.0
    var courtH = 220.0
    var state: State = .serving
    var ballPos = Vec2.zero
    var ballVel = Vec2.zero
    var paddleX = 90.0
    var paddleTarget = 90.0
    var bricks: [Brick] = []
    var level = 0
    var score = 0
    var lives = 3
    var time = 0.0
    var shakeAmp = 0.0
    var trail: [Vec2] = []
    var particles: [Particle] = []
    var floaters: [Floater] = []
    var lastHitAt = -10.0
    /// Paddle returns only — the paddle squash shouldn't fire on brick hits.
    var paddleHitAt = -10.0
    var lastLevelAt = -10.0
    var onGameOver: ((Int) -> Void)?

    private var lastDate: Date?
    private var serveAt: Double? = nil
    private var speed = 235.0
    private var built = false

    var paddleY: Double { courtH - 20 }

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
        updateParticles(&particles, dt: dt, drag: 3.0)
        floaters.removeAll { time - $0.bornAt > 0.8 }

        if !built {
            built = true
            buildLevel()
        }

        // The paddle chases its target fast enough to feel 1:1.
        paddleX += (paddleTarget - paddleX) * min(1, dt * 22)
        let half = Self.paddleW / 2
        paddleX = min(max(paddleX, half + 2), courtW - half - 2)

        switch state {
        case .serving:
            ballPos = Vec2(paddleX, paddleY - Self.paddleH / 2 - Self.ballR - 1)
            if let s = serveAt, time >= s {
                serveAt = nil
                launch()
            }
        case .playing:
            integrate(dt)
        case .done:
            break
        }
    }

    func launch() {
        guard state == .serving, serveAt == nil else { return }
        let angle = -Double.pi / 2 + Double.random(in: -0.3...0.3)
        ballVel = Vec2(cos(angle), sin(angle)) * speed
        state = .playing
        trail.removeAll()
        Haptics.play(.click, minInterval: 0)
    }

    private func integrate(_ dt: Double) {
        let oldPos = ballPos
        ballPos += ballVel * dt
        trail.append(ballPos)
        if trail.count > 10 { trail.removeFirst() }

        // Side and top walls.
        if ballPos.x < Self.ballR + 2 {
            ballPos.x = Self.ballR + 2
            ballVel.x = abs(ballVel.x)
            Haptics.play(.click, minInterval: 0.05)
        } else if ballPos.x > courtW - Self.ballR - 2 {
            ballPos.x = courtW - Self.ballR - 2
            ballVel.x = -abs(ballVel.x)
            Haptics.play(.click, minInterval: 0.05)
        }
        if ballPos.y < Self.ballR + 4 {
            ballPos.y = Self.ballR + 4
            ballVel.y = abs(ballVel.y)
            Haptics.play(.click, minInterval: 0.05)
        }

        collidePaddle()
        collideBricks(from: oldPos)

        // Dropped past the paddle.
        if ballPos.y > courtH + Self.ballR * 3 {
            lives -= 1
            shakeAmp = 4
            if lives <= 0 {
                state = .done
                Haptics.play(.failure, minInterval: 0)
                notifyMainAsync(onGameOver, score)
            } else {
                Haptics.play(.directionDown, minInterval: 0)
                state = .serving
                serveAt = nil
            }
        }
    }

    private func collidePaddle() {
        guard ballVel.y > 0 else { return }
        let top = paddleY - Self.paddleH / 2
        guard ballPos.y + Self.ballR >= top, ballPos.y < top + 12 else { return }
        let dx = ballPos.x - paddleX
        guard abs(dx) <= Self.paddleW / 2 + Self.ballR else { return }
        // Outgoing angle steered by where the ball met the paddle.
        let lean = min(max(dx / (Self.paddleW / 2), -1), 1)
        let angle = -Double.pi / 2 + lean * 1.05
        ballVel = Vec2(cos(angle), sin(angle)) * speed
        ballPos.y = top - Self.ballR
        lastHitAt = time
        paddleHitAt = time
        Haptics.play(.directionUp, minInterval: 0)
    }

    /// Swept segment-vs-brick test (slab method against the rect inflated by
    /// the ball radius), mirroring the paddle sweep in Pong: at top speed the
    /// ball covers a full brick height per frame, so an overlap test can
    /// tunnel. Hits the earliest brick along the travel path and reflects on
    /// the face it crossed.
    private func collideBricks(from oldPos: Vec2) {
        let delta = ballPos - oldPos
        var bestT = Double.infinity
        var bestIndex = -1
        var bestAxisX = false
        var bestInside = false
        for i in bricks.indices {
            let r = bricks[i].rect.insetBy(dx: -Self.ballR, dy: -Self.ballR)
            var txEnter = -Double.infinity, txExit = Double.infinity
            if abs(delta.x) > .ulpOfOne {
                let t0 = (r.minX - oldPos.x) / delta.x
                let t1 = (r.maxX - oldPos.x) / delta.x
                txEnter = min(t0, t1)
                txExit = max(t0, t1)
            } else if oldPos.x < r.minX || oldPos.x > r.maxX {
                continue
            }
            var tyEnter = -Double.infinity, tyExit = Double.infinity
            if abs(delta.y) > .ulpOfOne {
                let t0 = (r.minY - oldPos.y) / delta.y
                let t1 = (r.maxY - oldPos.y) / delta.y
                tyEnter = min(t0, t1)
                tyExit = max(t0, t1)
            } else if oldPos.y < r.minY || oldPos.y > r.maxY {
                continue
            }
            let tEnter = max(txEnter, tyEnter)
            let tExit = min(txExit, tyExit)
            guard tEnter <= tExit, tExit >= 0, tEnter <= 1 else { continue }
            let t = max(tEnter, 0)
            guard t < bestT else { continue }
            bestT = t
            bestIndex = i
            bestAxisX = txEnter > tyEnter
            bestInside = tEnter < 0
        }
        guard bestIndex >= 0 else { return }
        let rect = bricks[bestIndex].rect
        ballPos = oldPos + delta * bestT
        if bestInside {
            // Started the frame overlapping: push out toward the nearer face
            // instead of trusting a sweep that never crossed a boundary.
            if bestAxisX {
                ballVel.x = ballPos.x >= rect.midX ? abs(ballVel.x) : -abs(ballVel.x)
            } else {
                ballVel.y = ballPos.y >= rect.midY ? abs(ballVel.y) : -abs(ballVel.y)
            }
        } else if bestAxisX {
            ballVel.x = -ballVel.x
        } else {
            ballVel.y = -ballVel.y
        }
        lastHitAt = time
        hitBrick(bestIndex)
    }

    private func hitBrick(_ i: Int) {
        bricks[i].hp -= 1
        let center = Vec2(bricks[i].rect.midX, bricks[i].rect.midY)
        if bricks[i].hp <= 0 {
            spawnBurst(at: center, colorIndex: bricks[i].colorIndex)
            bricks.remove(at: i)
            score += 1
            shakeAmp = max(shakeAmp, 1.6)
            // Every brick nudges the rally a touch faster.
            speed = min(speed + 1.6, 330)
            ballVel = ballVel.normalized * speed
            Haptics.play(.click, minInterval: 0)
            if bricks.isEmpty { levelCleared() }
        } else {
            spawnChip(at: center)
            Haptics.play(.directionDown, minInterval: 0.08)
        }
    }

    private func levelCleared() {
        level += 1
        lastLevelAt = time
        speed = min(238 + Double(level) * 14, 330)
        floaters.append(Floater(pos: Vec2(courtW / 2, courtH * 0.4),
                                text: "Level \(level + 1)", bornAt: time,
                                color: Palette.goldDeep))
        for k in 0..<16 {
            let a = Double(k) / 16 * 2 * .pi
            let life = Double.random(in: 0.4...0.7)
            particles.append(Particle(
                pos: Vec2(courtW / 2, courtH * 0.35),
                vel: Vec2(cos(a), sin(a)) * Double.random(in: 50...110),
                life: life, maxLife: life,
                size: Double.random(in: 1.8...3.0), hue: .confetti(k)))
        }
        Haptics.play(.success, minInterval: 0)
        state = .serving
        serveAt = time + 0.9
        buildLevel()
    }

    private func buildLevel() {
        bricks.removeAll()
        let rows = min(3 + level, 6)
        let cols = 5
        let inset = 8.0, gap = 3.0
        let w = (courtW - inset * 2 - gap * Double(cols - 1)) / Double(cols)
        let h = 11.0
        for row in 0..<rows {
            for col in 0..<cols {
                // From level 3 on, the top rows take two hits.
                let hp = (level >= 2 && row < 2) ? 2 : 1
                bricks.append(Brick(
                    rect: CGRect(x: inset + Double(col) * (w + gap),
                                 y: 46 + Double(row) * (h + gap),
                                 width: w, height: h),
                    colorIndex: row,
                    hp: hp))
            }
        }
    }

    func reset() {
        level = 0
        score = 0
        lives = 3
        speed = 235
        shakeAmp = 0
        particles.removeAll()
        floaters.removeAll()
        trail.removeAll()
        buildLevel()
        state = .serving
        serveAt = nil
    }

    // MARK: Particles

    private func spawnBurst(at p: Vec2, colorIndex: Int) {
        spawnRadialBurst(into: &particles, at: p, count: 8, speed: 40...100,
                         life: 0.3...0.5, size: 1.6...2.8) { _ in .confetti(colorIndex) }
    }

    private func spawnChip(at p: Vec2) {
        spawnRadialBurst(into: &particles, at: p, count: 4, speed: 30...70,
                         life: 0.2...0.35, size: 1.2...2.0) { _ in .shard }
    }
}
