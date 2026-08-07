//
//  KeepUpsView.swift
//  Watch Minigames Watch App
//
//  Keep-Ups: tap the ball to kick it back into the air — tap dead center
//  to send it straight up, off-center to steer it. Gravity creeps up with
//  every kick; one drop on the grass ends the run.
//

import SwiftUI

// MARK: - Engine

final class KeepUpsEngine {

    enum State { case ready, playing, dropped }

    static let ballR = 11.0

    var state: State = .ready
    var time = 0.0
    var score = 0

    var ball = Vec2.zero
    var vel = Vec2.zero
    /// Visual roll, driven by horizontal speed.
    var rot = 0.0
    var rotVel = 0.0

    var kickAt = -10.0
    var wallHitAt = -10.0
    var droppedAt = -10.0
    var shakeAmp = 0.0
    var particles: [Particle] = []
    var floaters: [Floater] = []

    var onScore: ((Int) -> Void)?
    var onGameOver: ((Int) -> Void)?

    /// Court size the view feeds in each frame.
    var courtW = 180.0
    var courtH = 220.0

    private var lastDate: Date?
    private var placed = false

    var floorY: Double { courtH - 24 }
    /// Gravity creeps up with the score, shortening every hop.
    private var gravity: Double { 500 + min(340, Double(score) * 6) }

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

        // Rest the ball on the grass once the view reports a real size.
        if !placed, courtH > 100 {
            placed = true
            ball = Vec2(courtW / 2, floorY - Self.ballR)
        }

        guard state != .ready else { return }

        vel.y += gravity * dt
        ball += vel * dt
        rot += rotVel * dt
        rotVel *= exp(-0.4 * dt)

        // Side walls.
        let r = Self.ballR
        if ball.x < r + 4 {
            ball.x = r + 4
            vel.x = abs(vel.x) * 0.7
            wallBounce()
        } else if ball.x > courtW - r - 4 {
            ball.x = courtW - r - 4
            vel.x = -abs(vel.x) * 0.7
            wallBounce()
        }

        // A soft, invisible ceiling under the clock.
        if ball.y < 44, vel.y < 0 { vel.y = 0 }

        // The grass.
        if ball.y > floorY - r {
            ball.y = floorY - r
            if state == .playing {
                // The drop: one sad bounce, then the card.
                state = .dropped
                droppedAt = time
                shakeAmp = 4
                Haptics.play(.failure, minInterval: 0)
                notifyMainAsync(onGameOver, score)
            }
            vel.y = -abs(vel.y) * 0.35
            if abs(vel.y) < 30 { vel.y = 0 }
            vel.x *= exp(-3 * 1.0 / 60)
            rotVel = vel.x * 0.09
        }
    }

    private func wallBounce() {
        wallHitAt = time
        rotVel = vel.x * 0.09
        Haptics.play(.click, minInterval: 0.1)
    }

    // MARK: Input

    func tap(at p: Vec2) {
        switch state {
        case .ready:
            guard p.distance(to: ball) < 42 else { return }
            state = .playing
            kick(from: p)
        case .playing:
            // A generous reach, but you still have to hit the ball.
            guard p.distance(to: ball) < Self.ballR + 20 else { return }
            kick(from: p)
        case .dropped:
            break
        }
    }

    private func kick(from p: Vec2) {
        score += 1
        vel.y = -295
        // Off-center contact steers the ball away from the tap.
        vel.x = min(max((ball.x - p.x) * 9, -150), 150) + vel.x * 0.2
        rotVel = vel.x * 0.06
        kickAt = time
        notifyMainAsync(onScore, score)
        spawnRadialBurst(into: &particles, at: Vec2(ball.x, ball.y + Self.ballR * 0.7),
                         count: 5, speed: 30...80, life: 0.2...0.4,
                         size: 1.2...2.2) { k in
            k.isMultiple(of: 2) ? .gold : .white
        }
        if score > 0, score.isMultiple(of: 10) {
            floaters.append(Floater(pos: ball + Vec2(0, -Self.ballR - 6),
                                    text: "\(score)!", bornAt: time,
                                    color: Palette.goldDeep))
            Haptics.play(.directionUp, minInterval: 0)
        } else {
            Haptics.play(.click, minInterval: 0)
        }
    }

    func reset() {
        state = .ready
        score = 0
        ball = Vec2(courtW / 2, floorY - Self.ballR)
        vel = .zero
        rot = 0
        rotVel = 0
        kickAt = -10
        wallHitAt = -10
        droppedAt = -10
        shakeAmp = 0
        particles.removeAll()
        floaters.removeAll()
    }
}

// MARK: - View

struct KeepUpsView: View {
    @Environment(ScoreStore.self) private var store

    @State private var engine = KeepUpsEngine()
    @State private var finalScore: Int? = nil
    @State private var wasBest = false
    @State private var settled = false
    @State private var chipFlash = 0.0
    @State private var chipScore = 0
    @State private var tapArmed = true

    var body: some View {
        ArcadeScreen(extraPaused: settled) { size, date in
            canvasView(size: size, date: date)
        } chip: {
            ScoreChip(score: chipScore, flash: chipFlash)
                .padding(.top, 42)
                .padding(.trailing, 8)
                .allowsHitTesting(false)
        } overlay: {
            if let score = finalScore {
                ResultCard(title: "Score \(score)",
                           subtitle: wasBest && score > 0
                               ? "New Best" : "Best \(store.arcadeBest("keepups"))",
                           titleGold: score > 0,
                           subtitleGold: wasBest && score > 0) {
                    settled = false
                    chipScore = 0
                    engine.reset()
                    withAnimation { finalScore = nil }
                }
            }
        }
        .onAppear {
            engine.onScore = { total in
                chipScore = total
                chipFlash = 1
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                    chipFlash = 0
                }
            }
            engine.onGameOver = { score in
                wasBest = store.recordArcadeBest("keepups", score)
                // Let the ball thud into the grass before the card.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation(.arcadePop) { finalScore = score }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if finalScore != nil { settled = true }
                }
            }
        }
    }

    private func canvasView(size: CGSize, date: Date) -> some View {
        engine.courtW = size.width
        engine.courtH = size.height
        engine.step(to: date)
        let renderer = KeepUpsRenderer(engine: engine, size: size, time: engine.time)
        return Canvas { ctx, _ in
            renderer.draw(into: ctx)
        }
        .gesture(
            // Kicks judge on touch-DOWN; a falling ball can't wait for
            // the lift.
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard tapArmed else { return }
                    tapArmed = false
                    engine.tap(at: Vec2(value.location.x, value.location.y))
                }
                .onEnded { _ in tapArmed = true }
        )
    }
}

// MARK: - Renderer

struct KeepUpsRenderer {
    let engine: KeepUpsEngine
    let size: CGSize
    let time: Double

    func draw(into base: GraphicsContext) {
        var ctx = base
        if engine.shakeAmp > 0.15 {
            let shake = shakeOffset(time: time, amp: engine.shakeAmp)
            ctx.translateBy(x: shake.width, y: shake.height)
        }

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.bg))
        drawWallpaperDots(ctx, size: size)
        drawCloud(ctx)
        drawGrass(ctx)
        drawBall(ctx)
        drawArcadeParticles(ctx, engine.particles)
        drawFloaters(ctx, engine.floaters, time: time)

        if engine.state == .ready {
            let pulse = 0.4 + 0.18 * sin(time * 3.2)
            ctx.draw(Text("Tap")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink.opacity(pulse)),
                     at: CGPoint(x: engine.ball.x, y: engine.ball.y - 30))
        }

        drawClockScrim(ctx, size: size)
    }

    private func drawCloud(_ ctx: GraphicsContext) {
        // One lazy cloud, drifting and wrapping.
        let x = (time * 3.5).truncatingRemainder(dividingBy: Double(size.width) + 70) - 35
        let c = CGPoint(x: x, y: 52)
        var cloud = Path()
        cloud.addEllipse(in: CGRect(x: c.x - 14, y: c.y - 4, width: 16, height: 9))
        cloud.addEllipse(in: CGRect(x: c.x - 6, y: c.y - 8, width: 15, height: 12))
        cloud.addEllipse(in: CGRect(x: c.x + 1, y: c.y - 4, width: 14, height: 9))
        ctx.fill(cloud, with: .color(.white.opacity(0.7)))
        ctx.stroke(cloud, with: .color(Palette.ink.opacity(0.5)),
                   style: StrokeStyle(lineWidth: 1.2))
    }

    private func drawGrass(_ ctx: GraphicsContext) {
        let floorY = engine.floorY
        ctx.fill(Path(CGRect(x: 0, y: floorY, width: size.width,
                             height: size.height - floorY)),
                 with: .color(Palette.fairway))
        var top = Path()
        top.move(to: CGPoint(x: 0, y: floorY))
        top.addLine(to: CGPoint(x: size.width, y: floorY))
        ctx.stroke(top, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2))
    }

    private func drawBall(_ ctx: GraphicsContext) {
        let r = KeepUpsEngine.ballR
        let c = engine.ball.cg

        // Ground shadow stays on the grass, shrinking as the ball climbs.
        let height = min(max((engine.floorY - engine.ball.y) / 160, 0), 1)
        let shadowW = r * (1.05 - height * 0.45)
        ctx.fill(arcadeEllipse(at: CGPoint(x: c.x, y: engine.floorY + 5),
                               rx: shadowW, ry: shadowW * 0.32),
                 with: .color(Palette.shadow.opacity(1 - height * 0.5)))

        // Kick squash, wall squash, then the roll.
        let kick = decay(engine.kickAt, 0.15, now: time)
        let wall = decay(engine.wallHitAt, 0.12, now: time)
        drawSoccerBall(ctx, at: c, r: r, rot: engine.rot,
                       scaleX: (1 + kick * 0.22) * (1 - wall * 0.18),
                       scaleY: (1 - kick * 0.22) * (1 + wall * 0.18))
    }
}

// MARK: - Soccer ball

/// The inked soccer ball: center pentagon, five rim patches and the seams
/// between them — the classic icon — rolling with `rot`. The outline and
/// highlight stay fixed while the panels turn.
func drawSoccerBall(_ ctx: GraphicsContext, at c: CGPoint, r: Double,
                    rot: Double, scaleX: Double = 1, scaleY: Double = 1) {
    var g = ctx
    g.translateBy(x: c.x, y: c.y)
    g.scaleBy(x: scaleX, y: scaleY)

    let body = arcadeEllipse(at: .zero, rx: r, ry: r)
    g.fill(body, with: .color(.white))

    func pentagon(at center: CGPoint, radius: Double, rotation: Double) -> Path {
        var p = Path()
        for k in 0..<5 {
            let a = Double(k) / 5 * 2 * .pi - .pi / 2 + rotation
            let pt = CGPoint(x: center.x + cos(a) * radius,
                             y: center.y + sin(a) * radius)
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    var rolled = g
    rolled.rotate(by: Angle(radians: rot))
    rolled.clip(to: body)
    rolled.fill(pentagon(at: .zero, radius: r * 0.30, rotation: 0),
                with: .color(Palette.ink.opacity(0.72)))
    for k in 0..<5 {
        let a = Double(k) / 5 * 2 * .pi - .pi / 2
        let patchCenter = CGPoint(x: cos(a) * r * 1.05, y: sin(a) * r * 1.05)
        rolled.fill(pentagon(at: patchCenter, radius: r * 0.27, rotation: a + .pi / 2),
                    with: .color(Palette.ink.opacity(0.72)))
        var seam = Path()
        seam.move(to: CGPoint(x: cos(a) * r * 0.30, y: sin(a) * r * 0.30))
        seam.addLine(to: CGPoint(x: cos(a) * r * 0.74, y: sin(a) * r * 0.74))
        rolled.stroke(seam, with: .color(Palette.ink.opacity(0.42)),
                      style: StrokeStyle(lineWidth: 1.1))
    }

    g.stroke(body, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.6))
    g.fill(arcadeEllipse(at: CGPoint(x: -r * 0.35, y: -r * 0.4),
                         rx: r * 0.24, ry: r * 0.18),
           with: .color(.white.opacity(0.9)))
}
