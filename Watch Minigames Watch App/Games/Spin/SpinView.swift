//
//  SpinView.swift
//  Watch Minigames Watch App
//
//  Spin: a ball sweeps the lock ring — tap the instant it crosses the gold
//  wedge. Every hit flips the sweep, shrinks the wedge, and turns the lock
//  a notch; one late tap ends the run.
//

import SwiftUI

// MARK: - Engine

final class SpinEngine {

    enum State { case ready, playing, dead }

    var state: State = .ready
    var time = 0.0
    var score = 0

    /// Unwrapped sweep angle; the renderer wraps it onto the ring.
    var angle = -Double.pi / 2
    var dir = 1.0
    var speed = SpinEngine.startSpeed

    /// Wedge center in the same unwrapped space as `angle`, so hit and
    /// pass tests are simple distances — no modular arithmetic.
    var wedgeCenter = 0.0
    var wedgeHalf = SpinEngine.startHalf
    var wedgeSpawnAt = 0.0

    var hitAt = -10.0
    var hitWasPerfect = false
    /// Consecutive center-third hits; every 4th widens the wedge a little.
    var perfectStreak = 0
    var wedgeBonus = 0.0
    var diedAt = -10.0
    var shakeAmp = 0.0
    var particles: [Particle] = []
    var floaters: [Floater] = []
    /// Expanding hit rings: position + birth time.
    var ripples: [(pos: Vec2, bornAt: Double)] = []

    var onGameOver: ((Int) -> Void)?

    /// Ring geometry the view feeds in each frame, so bursts and floaters
    /// land in screen space.
    var ringCenter = Vec2(90, 110)
    var ringRadius = 70.0

    private var lastDate: Date?

    static let startSpeed = 1.9
    static let speedGain = 0.055
    static let maxSpeed = 4.6
    static let startHalf = 0.44
    static let minHalf = 0.13
    static let tapGrace = 0.05

    init() {
        spawnWedge()
    }

    func pointOnRing(_ a: Double) -> Vec2 {
        ringCenter + Vec2(cos(a), sin(a)) * ringRadius
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
        updateParticles(&particles, dt: dt, drag: 3.0)
        floaters.removeAll { time - $0.bornAt > 0.8 }
        ripples.removeAll { time - $0.bornAt > 0.5 }

        guard state == .playing else { return }
        angle += dir * speed * dt

        // Sailing past the wedge's far edge without a tap ends the run.
        let farEdge = wedgeCenter + dir * (wedgeHalf + 0.02)
        if dir * (angle - farEdge) > 0 {
            die()
        }
    }

    // MARK: Input

    func tap() {
        switch state {
        case .ready:
            state = .playing
            Haptics.play(.start, minInterval: 0)
        case .playing:
            if abs(angle - wedgeCenter) <= wedgeHalf + Self.tapGrace {
                hit()
            } else {
                die()
            }
        case .dead:
            break
        }
    }

    private func hit() {
        score += 1
        hitWasPerfect = abs(angle - wedgeCenter) <= wedgeHalf * 0.33
        hitAt = time
        let p = pointOnRing(angle)
        spawnRadialBurst(into: &particles, at: p, count: hitWasPerfect ? 14 : 8,
                         speed: 40...(hitWasPerfect ? 150 : 110),
                         life: 0.3...0.55, size: 1.6...2.9) { k in
            k.isMultiple(of: 2) ? .gold : .white
        }
        ripples.append((p, time))
        if hitWasPerfect {
            perfectStreak += 1
            let widened = perfectStreak == 4
            if widened {
                perfectStreak = 0
                wedgeBonus += 0.05
                Haptics.play(.success, minInterval: 0)
            } else {
                Haptics.play(.directionUp, minInterval: 0)
            }
            floaters.append(Floater(pos: p.lerp(to: ringCenter, 0.4),
                                    text: widened ? "Wider!" : "Perfect!",
                                    bornAt: time, color: Palette.goldDeep))
        } else {
            perfectStreak = 0
            Haptics.play(.click, minInterval: 0)
        }
        dir = -dir
        speed = min(Self.maxSpeed, Self.startSpeed + Double(score) * Self.speedGain)
        // The earned bonus pushes back against the shrink, never past the
        // starting size.
        wedgeHalf = min(Self.startHalf,
                        max(Self.minHalf, Self.startHalf - Double(score) * 0.008)
                            + wedgeBonus)
        spawnWedge()
    }

    private func die() {
        state = .dead
        diedAt = time
        shakeAmp = 5
        spawnRadialBurst(into: &particles, at: pointOnRing(angle), count: 10,
                         speed: 30...100, life: 0.3...0.5, size: 1.4...2.4) { _ in
            .shard
        }
        Haptics.play(.failure, minInterval: 0)
        notifyMainAsync(onGameOver, score)
    }

    /// Places the next wedge ahead of the sweep — always far enough that
    /// the flip-back never lands on top of it.
    private func spawnWedge() {
        wedgeCenter = angle + dir * Double.random(in: 2.2...4.2)
        wedgeSpawnAt = time
    }

    func reset() {
        state = .ready
        score = 0
        angle = -Double.pi / 2
        dir = 1
        speed = Self.startSpeed
        wedgeHalf = Self.startHalf
        perfectStreak = 0
        wedgeBonus = 0
        hitAt = -10
        hitWasPerfect = false
        diedAt = -10
        shakeAmp = 0
        particles.removeAll()
        floaters.removeAll()
        ripples.removeAll()
        spawnWedge()
    }
}

// MARK: - View

struct SpinView: View {
    @Environment(ScoreStore.self) private var store

    @State private var engine = SpinEngine()
    @State private var finalScore: Int? = nil
    @State private var wasBest = false
    @State private var settled = false
    @State private var tapArmed = true

    var body: some View {
        ArcadeScreen(extraPaused: settled) { size, date in
            canvasView(size: size, date: date)
        } overlay: {
            if let score = finalScore {
                ResultCard(title: "Score \(score)",
                           subtitle: wasBest && score > 0
                               ? "New Best" : "Best \(store.arcadeBest("spin"))",
                           titleGold: score > 0,
                           subtitleGold: wasBest && score > 0) {
                    settled = false
                    engine.reset()
                    withAnimation { finalScore = nil }
                }
            }
        }
        .onAppear {
            engine.onGameOver = { score in
                wasBest = store.recordArcadeBest("spin", score)
                // Let the fail flash land before the card slides in.
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
        engine.step(to: date)
        let renderer = SpinRenderer(engine: engine, size: size, time: engine.time)
        engine.ringCenter = Vec2(renderer.center.x, renderer.center.y)
        engine.ringRadius = renderer.ringR
        return Canvas { ctx, _ in
            renderer.draw(into: ctx)
        }
        .gesture(
            // Judged on touch-DOWN — a timing game can't wait for the lift.
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard tapArmed else { return }
                    tapArmed = false
                    engine.tap()
                }
                .onEnded { _ in tapArmed = true }
        )
    }
}

// MARK: - Renderer

struct SpinRenderer {
    let engine: SpinEngine
    let size: CGSize
    let time: Double

    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2 + 6) }
    var ringR: Double { min(size.width, size.height) / 2 - 30 }
    private var trackW: Double { max(22, ringR * 0.35) }

    private func onRing(_ a: Double, radius: Double? = nil) -> CGPoint {
        let r = radius ?? ringR
        return CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
    }

    func draw(into base: GraphicsContext) {
        var ctx = base
        if engine.shakeAmp > 0.15 {
            let shake = shakeOffset(time: time, amp: engine.shakeAmp)
            ctx.translateBy(x: shake.width, y: shake.height)
        }

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.bg))
        drawWallpaperDots(ctx, size: size)

        drawPlateBase(ctx)
        drawWedge(ctx)
        drawPlateRims(ctx)
        drawMarker(ctx)
        drawRipples(ctx)
        drawHub(ctx)
        drawArcadeParticles(ctx, engine.particles)
        drawFloaters(ctx, engine.floaters, time: time)

        drawClockScrim(ctx, size: size)
    }

    // MARK: Ring plate

    private func drawPlateBase(_ ctx: GraphicsContext) {
        let ring = Path(ellipseIn: CGRect(x: center.x - ringR, y: center.y - ringR,
                                          width: ringR * 2, height: ringR * 2))
        var sh = ctx
        sh.translateBy(x: 2, y: 3)
        sh.addFilter(.blur(radius: 2.5))
        sh.stroke(ring, with: .color(Palette.shadow),
                  style: StrokeStyle(lineWidth: trackW))

        ctx.stroke(ring, with: .color(.white.opacity(0.72)),
                   style: StrokeStyle(lineWidth: trackW))
    }

    /// Rims draw over the wedge, so the gold reads as a painted section of
    /// the dial rather than an object sitting on it.
    private func drawPlateRims(_ ctx: GraphicsContext) {
        for edge in [ringR + trackW / 2, ringR - trackW / 2] {
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - edge, y: center.y - edge,
                                              width: edge * 2, height: edge * 2)),
                       with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.6))
        }
    }

    // MARK: Wedge

    private func drawWedge(_ ctx: GraphicsContext) {
        let pop = easeOutBack(min((time - engine.wedgeSpawnAt) / 0.28, 1))
        let breathe = 1 + 0.04 * sin((time - engine.wedgeSpawnAt) * 3.4)
        let half = max(0.001, engine.wedgeHalf * pop * breathe)
        let c = engine.wedgeCenter
        let dead = engine.state == .dead
        let flash = decay(engine.diedAt, 0.5, now: time)

        // A flat colored section of the track, flush with the band.
        var arc = Path()
        arc.addArc(center: center, radius: ringR,
                   startAngle: .radians(c - half), endAngle: .radians(c + half),
                   clockwise: false)
        ctx.stroke(arc, with: .color(dead ? Palette.bumperCoral : Palette.gold),
                   style: StrokeStyle(lineWidth: trackW))
        if dead, flash > 0 {
            ctx.stroke(arc, with: .color(.white.opacity(0.5 * flash)),
                       style: StrokeStyle(lineWidth: trackW))
        }
    }

    // MARK: Marker

    /// The sweep marker: a bold dial tick spanning the track, widening for
    /// a beat on each hit.
    private func drawMarker(_ ctx: GraphicsContext) {
        let dead = engine.state == .dead
        let hitPop = decay(engine.hitAt, 0.18, now: time)
        let breathe = engine.state == .ready ? 0.4 * sin(time * 2.6) : 0
        var tick = Path()
        tick.move(to: onRing(engine.angle, radius: ringR - trackW / 2 + 2.5 - breathe))
        tick.addLine(to: onRing(engine.angle, radius: ringR + trackW / 2 - 2.5 + breathe))
        ctx.stroke(tick, with: .color(dead ? Palette.bumperCoral : Palette.ink),
                   style: StrokeStyle(lineWidth: 3.6 + hitPop * 2.2, lineCap: .round))
    }

    private func drawRipples(_ ctx: GraphicsContext) {
        for ripple in engine.ripples {
            let age = (time - ripple.bornAt) / 0.5
            guard age < 1 else { continue }
            let r = 6 + age * 26
            ctx.stroke(arcadeEllipse(at: ripple.pos.cg, rx: r, ry: r),
                       with: .color(Palette.gold.opacity(0.55 * (1 - age))),
                       style: StrokeStyle(lineWidth: 2))
        }
    }

    // MARK: Hub

    private func drawHub(_ ctx: GraphicsContext) {
        let r = ringR * 0.42
        let c = center
        let pop = 1 + 0.12 * (1 - easeOutBack(1 - decay(engine.hitAt, 0.3, now: time)))
        let breathe = 1 + 0.015 * sin(time * 1.3)

        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.scaleBy(x: pop * breathe, y: pop * breathe)
        g.translateBy(x: -c.x, y: -c.y)

        var sh = g
        sh.translateBy(x: 1.5, y: 2.5)
        sh.addFilter(.blur(radius: 2))
        sh.fill(arcadeEllipse(at: c, rx: r, ry: r), with: .color(Palette.shadow))

        arcadeInkedEllipse(g, at: c, rx: r, ry: r, fill: .white, ink: 1.8)

        if engine.state == .ready {
            let pulse = 0.45 + 0.18 * sin(time * 3.2)
            g.draw(Text("Tap")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink.opacity(pulse)), at: c)
        } else {
            g.draw(Text("\(engine.score)")
                .font(.system(size: 27, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink.opacity(0.9)), at: c)
        }
    }
}
