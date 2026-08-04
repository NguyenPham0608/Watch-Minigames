//
//  BricksView.swift
//  Minigames Watch App
//
//  Brick Breaker: steer the paddle with a drag or the crown, tap to serve.
//  Endless levels — each clear rebuilds the wall a little meaner.
//

import SwiftUI

// MARK: - Engine

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
        updateParticles(dt)
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
        ballPos += ballVel * dt
        trail.append(ballPos)
        if trail.count > 10 { trail.removeFirst() }

        // Side and top walls.
        if ballPos.x < Self.ballR + 2 {
            ballPos.x = Self.ballR + 2
            ballVel.x = abs(ballVel.x)
            Haptics.play(.click)
        } else if ballPos.x > courtW - Self.ballR - 2 {
            ballPos.x = courtW - Self.ballR - 2
            ballVel.x = -abs(ballVel.x)
            Haptics.play(.click)
        }
        if ballPos.y < Self.ballR + 4 {
            ballPos.y = Self.ballR + 4
            ballVel.y = abs(ballVel.y)
            Haptics.play(.click)
        }

        collidePaddle()
        collideBricks()

        // Dropped past the paddle.
        if ballPos.y > courtH + Self.ballR * 3 {
            lives -= 1
            shakeAmp = 4
            if lives <= 0 {
                state = .done
                Haptics.play(.failure, minInterval: 0)
                let final = score
                let cb = onGameOver
                DispatchQueue.main.async { cb?(final) }
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
        Haptics.play(.directionUp, minInterval: 0)
    }

    private func collideBricks() {
        for i in bricks.indices {
            let r = bricks[i].rect
            let closest = Vec2(min(max(ballPos.x, r.minX), r.maxX),
                               min(max(ballPos.y, r.minY), r.maxY))
            let d = ballPos - closest
            guard d.lengthSquared < Self.ballR * Self.ballR else { continue }
            if abs(d.x) > abs(d.y) {
                ballVel.x = d.x >= 0 ? abs(ballVel.x) : -abs(ballVel.x)
            } else {
                ballVel.y = d.y >= 0 ? abs(ballVel.y) : -abs(ballVel.y)
            }
            lastHitAt = time
            hitBrick(i)
            break
        }
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
            Haptics.play(.directionDown)
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

    private func updateParticles(_ dt: Double) {
        guard !particles.isEmpty else { return }
        for i in particles.indices {
            particles[i].life -= dt
            particles[i].pos += particles[i].vel * dt
            particles[i].vel = particles[i].vel * exp(-3.0 * dt)
        }
        particles.removeAll { $0.life <= 0 }
    }

    private func spawnBurst(at p: Vec2, colorIndex: Int) {
        for _ in 0..<8 {
            let a = Double.random(in: 0..<(2 * .pi))
            let life = Double.random(in: 0.3...0.5)
            particles.append(Particle(
                pos: p, vel: Vec2(cos(a), sin(a)) * Double.random(in: 40...100),
                life: life, maxLife: life,
                size: Double.random(in: 1.6...2.8), hue: .confetti(colorIndex)))
        }
    }

    private func spawnChip(at p: Vec2) {
        for _ in 0..<4 {
            let a = Double.random(in: 0..<(2 * .pi))
            let life = Double.random(in: 0.2...0.35)
            particles.append(Particle(
                pos: p, vel: Vec2(cos(a), sin(a)) * Double.random(in: 30...70),
                life: life, maxLife: life,
                size: Double.random(in: 1.2...2.0), hue: .shard))
        }
    }
}

// MARK: - View

struct BricksView: View {
    @Environment(ScoreStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var engine = BricksEngine()
    @State private var crown = 0.5
    @State private var finalScore: Int? = nil
    @State private var wasBest = false
    @State private var dragStartX: Double? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation) { timeline in
                    canvasView(size: geo.size, date: timeline.date)
                }
                if let score = finalScore {
                    ResultCard(title: "\(score) Bricks",
                               subtitle: wasBest && score > 0
                                   ? "New Best" : "Best \(store.arcadeBest("bricks"))",
                               titleGold: score > 0,
                               subtitleGold: wasBest && score > 0) {
                        engine.reset()
                        withAnimation { finalScore = nil }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .focusable()
        .digitalCrownRotation($crown, from: 0, through: 1, by: 0.001,
                              sensitivity: .low, isContinuous: false,
                              isHapticFeedbackEnabled: false)
        .onChange(of: crown) { _, newValue in
            engine.paddleTarget = newValue * engine.courtW
        }
        .onAppear {
            engine.onGameOver = { score in
                wasBest = store.recordArcadeBest("bricks", score)
                withAnimation(.easeOut(duration: 0.3)) { finalScore = score }
            }
        }
    }

    private func canvasView(size: CGSize, date: Date) -> some View {
        engine.courtW = size.width
        engine.courtH = size.height
        engine.step(to: date)
        let renderer = BricksRenderer(engine: engine, size: size, time: engine.time)
        return Canvas { ctx, _ in
            renderer.draw(into: ctx)
        }
        .gesture(paddleDrag)
    }

    /// Drag steers the paddle; a bare tap serves. Keeps the crown in sync so
    /// the two controls hand off without a jump.
    private var paddleDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartX == nil { dragStartX = engine.paddleTarget }
                let target = (dragStartX ?? 0) + Double(value.translation.width) * 1.3
                engine.paddleTarget = min(max(target, 0), engine.courtW)
                crown = engine.paddleTarget / max(engine.courtW, 1)
            }
            .onEnded { value in
                dragStartX = nil
                if abs(value.translation.width) < 6, abs(value.translation.height) < 6 {
                    engine.launch()
                }
            }
    }
}

// MARK: - Renderer

struct BricksRenderer {
    let engine: BricksEngine
    let size: CGSize
    let time: Double

    static let brickColors: [(Color, Color)] = [
        (Palette.bumperCoral, Color(red: 0.70, green: 0.34, blue: 0.27)),
        (Palette.gold, Palette.goldDeep),
        (Color(red: 0.38, green: 0.70, blue: 0.66), Color(red: 0.27, green: 0.54, blue: 0.50)),
        (Palette.boostBlue, Palette.boostBlueDeep),
        (Color(red: 0.63, green: 0.53, blue: 0.79), Color(red: 0.48, green: 0.39, blue: 0.63)),
        (Palette.hillLight, Palette.deepGreen),
    ]

    func draw(into base: GraphicsContext) {
        var ctx = base
        if engine.shakeAmp > 0.15 {
            ctx.translateBy(x: sin(time * 67) * engine.shakeAmp,
                            y: cos(time * 53) * engine.shakeAmp * 0.6)
        }

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.bg))
        drawWallpaperDots(ctx, size: size)
        drawClockScrim(ctx, size: size)
        drawHUD(ctx)
        drawBricks(ctx)
        drawTrail(ctx)
        drawPaddle(ctx)
        drawBall(ctx)
        drawArcadeParticles(ctx, engine.particles)
        drawFloaters(ctx, engine.floaters, time: time)
        drawServeHint(ctx)
    }

    private func drawHUD(_ ctx: GraphicsContext) {
        let flash = max(0, 1 - (time - engine.lastLevelAt) / 0.5)
        ctx.draw(Text("\(engine.score)")
            .font(.system(size: 40 * (1 + flash * 0.25), weight: .heavy, design: .rounded))
            .foregroundStyle(Palette.boostBlueDeep.opacity(0.35 + flash * 0.4)),
                 at: CGPoint(x: size.width - 30, y: size.height - 42))
        // Lives, tucked in the bottom-left corner.
        for i in 0..<3 {
            let filled = i < engine.lives
            ctx.draw(Text(Image(systemName: filled ? "heart.fill" : "heart"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(filled ? Palette.bumperCoral : Palette.ink.opacity(0.2)),
                     at: CGPoint(x: 14 + Double(i) * 13, y: size.height - 12))
        }
    }

    private func drawBricks(_ ctx: GraphicsContext) {
        for brick in engine.bricks {
            let (main, deep) = Self.brickColors[brick.colorIndex % Self.brickColors.count]
            let p = Path(roundedRect: brick.rect, cornerRadius: 3)
            var sh = ctx
            sh.translateBy(x: 1, y: 1.8)
            sh.fill(p, with: .color(Palette.shadow))
            ctx.fill(p, with: .color(brick.hp > 1 ? deep : main))
            ctx.stroke(p, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.4))
            // Gloss line along the top edge.
            var gloss = Path()
            gloss.move(to: CGPoint(x: brick.rect.minX + 3, y: brick.rect.minY + 3))
            gloss.addLine(to: CGPoint(x: brick.rect.maxX - 3, y: brick.rect.minY + 3))
            ctx.stroke(gloss, with: .color(.white.opacity(brick.hp > 1 ? 0.25 : 0.45)),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            if brick.hp > 1 {
                // Rivets mark the armored rows.
                for fx in [0.25, 0.75] {
                    ctx.fill(arcadeEllipse(at: CGPoint(x: brick.rect.minX + brick.rect.width * fx,
                                                       y: brick.rect.midY),
                                           rx: 1.4, ry: 1.4),
                             with: .color(.white.opacity(0.55)))
                }
            }
        }
    }

    private func drawTrail(_ ctx: GraphicsContext) {
        guard engine.state == .playing, engine.trail.count > 2 else { return }
        let pts = engine.trail
        for i in 1..<pts.count {
            let f = Double(i) / Double(pts.count)
            var seg = Path()
            seg.move(to: pts[i - 1].cg)
            seg.addLine(to: pts[i].cg)
            ctx.stroke(seg, with: .color(Palette.boostBlue.opacity(0.05 + 0.28 * f * f)),
                       style: StrokeStyle(lineWidth: BricksEngine.ballR * 1.8 * f,
                                          lineCap: .round))
        }
    }

    private func drawPaddle(_ ctx: GraphicsContext) {
        let bump = max(0, 1 - (time - engine.lastHitAt) / 0.16)
        let rect = CGRect(x: engine.paddleX - BricksEngine.paddleW / 2,
                          y: engine.paddleY - BricksEngine.paddleH / 2 + bump * 2,
                          width: BricksEngine.paddleW, height: BricksEngine.paddleH)
        let shape = Path(roundedRect: rect, cornerRadius: BricksEngine.paddleH / 2)
        var sh = ctx
        sh.translateBy(x: 1.2, y: 2)
        sh.addFilter(.blur(radius: 1.6))
        sh.fill(shape, with: .color(Palette.shadow))
        ctx.fill(shape, with: .color(Palette.boostBlue))
        var stripe = Path()
        stripe.move(to: CGPoint(x: rect.minX + 4, y: rect.midY))
        stripe.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.midY))
        ctx.stroke(stripe, with: .color(Color(red: 0.76, green: 0.88, blue: 0.95)),
                   style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        ctx.stroke(shape, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.5))
        if bump > 0 {
            ctx.fill(shape, with: .color(.white.opacity(bump * 0.5)))
        }
    }

    private func drawBall(_ ctx: GraphicsContext) {
        guard engine.state != .done else { return }
        let c = engine.ballPos.cg
        let r = BricksEngine.ballR
        ctx.fill(arcadeEllipse(at: CGPoint(x: c.x, y: c.y + r * 0.9), rx: r * 0.95, ry: r * 0.4),
                 with: .color(Palette.shadow))
        // Squash on impact, stretch with speed, in a velocity-aligned frame.
        let speed = engine.ballVel.length
        let stretch = engine.state == .playing ? min(speed / 900, 0.25) : 0
        let squash = max(0, 1 - (time - engine.lastHitAt) / 0.13) * 0.3
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        if speed > 1, engine.state == .playing {
            g.rotate(by: Angle(radians: atan2(engine.ballVel.y, engine.ballVel.x)))
        }
        g.scaleBy(x: 1 + stretch - squash, y: 1 - (stretch - squash) * 0.7)
        g.fill(arcadeEllipse(at: .zero, rx: r, ry: r), with: .color(Palette.wallTop))
        g.stroke(arcadeEllipse(at: .zero, rx: r, ry: r), with: .color(Palette.ink),
                 style: StrokeStyle(lineWidth: 1.5))
        g.fill(arcadeEllipse(at: CGPoint(x: -r * 0.3, y: -r * 0.35), rx: r * 0.24, ry: r * 0.2),
               with: .color(.white.opacity(0.9)))
    }

    private func drawServeHint(_ ctx: GraphicsContext) {
        guard engine.state == .serving else { return }
        let c = engine.ballPos.cg
        let pulse = (sin(time * 2.4) + 1) / 2
        let r = BricksEngine.ballR + 3.5 + pulse * 2
        ctx.stroke(arcadeEllipse(at: c, rx: r, ry: r),
                   with: .color(Palette.ink.opacity(0.4 - pulse * 0.22)),
                   style: StrokeStyle(lineWidth: 1.4))
    }
}

// MARK: - Home page

struct BricksHome: View {
    var body: some View {
        GameHome(title: "Bricks") { t in
            BricksScene(t: t)
        } destination: {
            BricksView()
        }
    }
}

/// Little vignette: a real rally — the ball flies paddle → brick → paddle,
/// each hit brick bursts and stays gone until the wall rebuilds.
private struct BricksScene: View {
    let t: Double

    /// Seconds per paddle-to-paddle bounce.
    private static let cycleT = 1.05
    private static let cols = 4

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let brickW = 26.0, brickH = 10.0, gapX = 4.0, gapY = 3.0
            let wallLeft = cx - (Double(Self.cols) * (brickW + gapX) - gapX) / 2
            let topRowY = 6.0
            let paddleH = 6.0
            let paddleTopY = size.height - 4 - paddleH
            let ballR = 3.8

            func brickCenter(_ idx: Int) -> CGPoint {
                let row = idx / Self.cols   // 0 top, 1 bottom
                let col = idx % Self.cols
                return CGPoint(x: wallLeft + Double(col) * (brickW + gapX) + brickW / 2,
                               y: topRowY + Double(row) * (brickH + gapY) + brickH / 2)
            }
            /// Bricks fall bottom row left→right, then the top row.
            func targetBrick(_ cycle: Int) -> Int {
                let k = ((cycle % 8) + 8) % 8
                return k < 4 ? 4 + k : k - 4
            }
            func popOrder(_ brick: Int) -> Int { brick >= 4 ? brick - 4 : brick + 4 }
            func smooth(_ x: Double) -> Double {
                let u = min(max(x, 0), 1)
                return u * u * (3 - 2 * u)
            }

            /// Ball center at an absolute time; bounces are straight lines
            /// with clean direction flips at each contact.
            func ballPos(at time: Double) -> CGPoint {
                let cycle = Int(floor(time / Self.cycleT))
                let p = time / Self.cycleT - floor(time / Self.cycleT)
                let prev = brickCenter(targetBrick(cycle - 1))
                let cur = brickCenter(targetBrick(cycle))
                let next = brickCenter(targetBrick(cycle + 1))
                // Paddle contacts happen midway between successive targets.
                let startX = (prev.x + cur.x) / 2
                let endX = (cur.x + next.x) / 2
                let x = p < 0.5 ? startX + (cur.x - startX) * (p / 0.5)
                                : cur.x + (endX - cur.x) * ((p - 0.5) / 0.5)
                let impactY = cur.y + brickH / 2 + ballR
                let bottomY = paddleTopY - ballR
                let tri = 1 - abs(1 - 2 * p)
                return CGPoint(x: x, y: bottomY - (bottomY - impactY) * tri)
            }

            let cycle = Int(floor(t / Self.cycleT))
            let p = t / Self.cycleT - floor(t / Self.cycleT)
            let s = ((cycle % 8) + 8) % 8
            let curTarget = targetBrick(cycle)

            // --- Wall ---
            for i in 0..<8 {
                let ord = popOrder(i)
                // Already gone this rebuild round, or mid-pop.
                if ord < s { continue }
                if ord == s, p >= 0.5 { continue }
                var scale = 1.0
                if s == 0, p < 0.5 {
                    // Fresh wall pops back in, brick by brick.
                    scale = smooth((p * 4 - Double(ord) * 0.12) / 0.3)
                    if scale <= 0.01 { continue }
                }
                let c = brickCenter(i)
                let (main, _) = BricksRenderer.brickColors[i < 4 ? 0 : 1]
                let w = brickW * scale, h = brickH * scale
                let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
                let path = Path(roundedRect: rect, cornerRadius: 2.5 * scale)
                var sh = ctx
                sh.translateBy(x: 1, y: 1.5)
                sh.fill(path, with: .color(Palette.shadow))
                ctx.fill(path, with: .color(main))
                ctx.stroke(path, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.3))
                var gloss = Path()
                gloss.move(to: CGPoint(x: rect.minX + 2.5, y: rect.minY + 2.5))
                gloss.addLine(to: CGPoint(x: rect.maxX - 2.5, y: rect.minY + 2.5))
                ctx.stroke(gloss, with: .color(.white.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }

            // --- Pop burst on the brick just hit ---
            if p >= 0.5 {
                let tp = (p - 0.5) * Self.cycleT   // seconds since impact
                if tp < 0.4 {
                    let c = brickCenter(curTarget)
                    let (main, _) = BricksRenderer.brickColors[curTarget < 4 ? 0 : 1]
                    let q = tp / 0.4
                    for k in 0..<7 {
                        let a = Double(k) / 7 * 2 * .pi + Double(curTarget)
                        let r = 4 + q * 15
                        let pt = CGPoint(x: c.x + cos(a) * r * 1.25, y: c.y + sin(a) * r)
                        let sz = 2.0 * (1 - q)
                        ctx.fill(arcadeEllipse(at: pt, rx: sz, ry: sz),
                                 with: .color((k % 2 == 0 ? main : Palette.wallTop)
                                     .opacity(1 - q)))
                    }
                    // Quick white flash ring right at the impact.
                    if q < 0.4 {
                        ctx.stroke(arcadeEllipse(at: c, rx: 5 + q * 18, ry: 4 + q * 13),
                                   with: .color(.white.opacity(0.7 * (1 - q / 0.4))),
                                   style: StrokeStyle(lineWidth: 1.5))
                    }
                }
            }

            // --- Trail (true past positions of the same path) ---
            for i in 1...5 {
                let f = Double(i) / 6
                let past = ballPos(at: t - Double(i) * 0.04)
                ctx.fill(arcadeEllipse(at: past, rx: 2.6 * (1 - f), ry: 2.6 * (1 - f)),
                         with: .color(Palette.boostBlue.opacity(0.35 * (1 - f))))
            }

            // --- Ball, squashing at both contacts ---
            let ball = ballPos(at: t)
            let contact = max(0, 1 - min(p, 1 - p) / 0.08) + max(0, 1 - abs(p - 0.5) / 0.06)
            let squash = min(contact, 1) * 0.25
            var g = ctx
            g.translateBy(x: ball.x, y: ball.y)
            g.scaleBy(x: 1 + squash, y: 1 - squash)
            g.fill(arcadeEllipse(at: .zero, rx: ballR, ry: ballR), with: .color(Palette.wallTop))
            g.stroke(arcadeEllipse(at: .zero, rx: ballR, ry: ballR), with: .color(Palette.ink),
                     style: StrokeStyle(lineWidth: 1.4))
            g.fill(arcadeEllipse(at: CGPoint(x: -1.2, y: -1.3), rx: 1, ry: 0.8),
                   with: .color(.white.opacity(0.9)))

            // --- Paddle gliding between contact points, bumping on catch ---
            let prev = brickCenter(targetBrick(cycle - 1))
            let cur = brickCenter(curTarget)
            let next = brickCenter(targetBrick(cycle + 1))
            let padX = (prev.x + cur.x) / 2
                + ((cur.x + next.x) / 2 - (prev.x + cur.x) / 2) * smooth(p)
            let bump = max(0, 1 - min(p, 1 - p) / 0.08) * 1.8
            let rect = CGRect(x: padX - 14, y: paddleTopY + bump, width: 28, height: paddleH)
            let paddle = Path(roundedRect: rect, cornerRadius: 3)
            var psh = ctx
            psh.translateBy(x: 1, y: 1.8)
            psh.addFilter(.blur(radius: 1.4))
            psh.fill(paddle, with: .color(Palette.shadow))
            ctx.fill(paddle, with: .color(Palette.boostBlue))
            var stripe = Path()
            stripe.move(to: CGPoint(x: rect.minX + 4, y: rect.midY))
            stripe.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.midY))
            ctx.stroke(stripe, with: .color(Color(red: 0.76, green: 0.88, blue: 0.95)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            ctx.stroke(paddle, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.3))
        }
    }
}
