//
//  PongView.swift
//  Watch Minigames Watch App
//
//  Super Pong: the golf game's flat ink style with a light futuristic twist —
//  grid floor, glowing smash trails, particle bursts.
//

import SwiftUI

struct PongView: View {
    @Environment(ScoreStore.self) private var store

    @State private var engine = PongEngine()
    @State private var winner: PongEngine.Side? = nil
    /// Paddle position when a finger drag began.
    @State private var dragStartY: Double? = nil

    var body: some View {
        ArcadeScreen { size, date in
            canvasView(size: size, date: date)
        } overlay: {
            if let winner { resultOverlay(winner) }
        }
        .crownDetents { detents in
            // Crown up moves the paddle down.
            engine.playerTarget = min(max(engine.playerTarget + detents * CrownFeel.pointsPerDetent,
                                          0), engine.courtH)
        }
        .onAppear {
            engine.difficulty = store.pongDifficulty
            engine.onGameOver = { w in
                if w == .player { store.recordPongWin() }
                withAnimation(.arcadePop) { winner = w }
            }
        }
    }

    private func canvasView(size: CGSize, date: Date) -> some View {
        engine.courtW = size.width
        engine.courtH = size.height
        engine.step(to: date)
        // `time` makes the Canvas's captured state change every frame —
        // SwiftUI diffs by stored values, and a constant capture would let it
        // skip redraws entirely.
        let renderer = PongRenderer(engine: engine, size: size,
                                    origin: .zero, time: engine.time)
        return Canvas { ctx, _ in
            renderer.draw(into: ctx)
        }
        .gesture(paddleDrag)
    }

    /// Drag anywhere to steer the paddle — slightly faster than 1:1 so one
    /// swipe can cover the court.
    private var paddleDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartY == nil { dragStartY = engine.playerTarget }
                let target = (dragStartY ?? 0) + Double(value.translation.height) * 1.2
                engine.playerTarget = min(max(target, 0), engine.courtH)
            }
            .onEnded { _ in dragStartY = nil }
    }

    private func resultOverlay(_ w: PongEngine.Side) -> some View {
        ResultCard(title: w == .player ? "You Win!" : "Bot Wins",
                   subtitle: "\(engine.playerScore) – \(engine.botScore)",
                   titleGold: w == .player,
                   subtitleSize: 13, subtitleSemibold: true) {
            engine.reset()
            withAnimation { winner = nil }
        }
    }
}

// MARK: - Renderer

struct PongRenderer {
    let engine: PongEngine
    let size: CGSize
    let origin: CGPoint
    let time: Double

    private func pt(_ p: Vec2) -> CGPoint {
        CGPoint(x: origin.x + p.x, y: origin.y + p.y)
    }

    func draw(into base: GraphicsContext) {
        var ctx = base
        if engine.shakeAmp > 0.15 {
            let shake = shakeOffset(time: time, amp: engine.shakeAmp)
            ctx.translateBy(x: shake.width, y: shake.height)
        }

        drawBackground(ctx)
        drawDivider(ctx)
        drawScore(ctx)
        drawOrb(ctx)
        drawRipples(ctx)
        drawTrail(ctx)
        drawPaddles(ctx)
        drawBall(ctx)
        drawArcadeParticles(ctx, engine.particles)
        drawCharge(ctx)
        drawServe(ctx)
    }

    // MARK: Stage

    // The court dressing never changes color at rest — build these once
    // instead of per frame.
    private static let vignetteGradient = Gradient(colors: [.clear, Palette.ink.opacity(0.10)])
    private static let leftGoalResting = Gradient(colors: [Palette.bumperCoral.opacity(0.10), .clear])
    private static let rightGoalResting = Gradient(colors: [.clear, Palette.boostBlue.opacity(0.10)])

    private func drawBackground(_ ctx: GraphicsContext) {
        let all = CGRect(origin: .zero, size: size)
        ctx.fill(Path(all), with: .color(Palette.bg))

        // Each half faintly wears its side's color.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)),
                 with: .color(Palette.bumperCoral.opacity(0.05)))
        ctx.fill(Path(CGRect(x: size.width / 2, y: 0,
                             width: size.width / 2, height: size.height)),
                 with: .color(Palette.boostBlue.opacity(0.05)))

        // Soft vignette pulls focus to the middle.
        ctx.fill(Path(all), with: .radialGradient(
            Self.vignetteGradient,
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            startRadius: size.width * 0.35, endRadius: size.height * 0.85))

        // Goal glow strips, flaring in the scorer's color on a point.
        let flash = decay(engine.lastScoreAt, 0.6, now: time)
        let goalW = 20.0
        var leftA = 0.10, rightA = 0.10
        if let side = engine.lastScoreSide, flash > 0 {
            // The ball exited on the conceding side.
            if side == .player { leftA += flash * 0.4 } else { rightA += flash * 0.4 }
        }
        ctx.fill(Path(CGRect(x: 0, y: 0, width: goalW, height: size.height)),
                 with: .linearGradient(
                    leftA == 0.10 ? Self.leftGoalResting
                        : Gradient(colors: [Palette.bumperCoral.opacity(leftA), .clear]),
                    startPoint: .zero, endPoint: CGPoint(x: goalW, y: 0)))
        ctx.fill(Path(CGRect(x: size.width - goalW, y: 0, width: goalW, height: size.height)),
                 with: .linearGradient(
                    rightA == 0.10 ? Self.rightGoalResting
                        : Gradient(colors: [.clear, Palette.boostBlue.opacity(rightA)]),
                    startPoint: CGPoint(x: size.width - goalW, y: 0),
                    endPoint: CGPoint(x: size.width, y: 0)))

        drawClockScrim(ctx, size: size)
    }

    private func drawDivider(_ ctx: GraphicsContext) {
        let cx = size.width / 2
        var divider = Path()
        divider.move(to: CGPoint(x: cx, y: 0))
        divider.addLine(to: CGPoint(x: cx, y: size.height))
        ctx.stroke(divider, with: .color(Palette.ink.opacity(0.18)),
                   style: StrokeStyle(lineWidth: 2))
        let mid = CGPoint(x: cx, y: size.height / 2)
        ctx.stroke(arcadeEllipse(at: mid, rx: 17, ry: 17), with: .color(Palette.ink.opacity(0.18)),
                   style: StrokeStyle(lineWidth: 2))
        ctx.fill(arcadeEllipse(at: mid, rx: 2.2, ry: 2.2), with: .color(Palette.ink.opacity(0.22)))
    }

    private func drawScore(_ ctx: GraphicsContext) {
        let y = origin.y + engine.courtH * 0.28
        func number(_ n: Int, side: PongEngine.Side, color: Color, x: Double) {
            let flash = engine.lastScoreSide == side ? decay(engine.lastScoreAt, 0.6, now: time) : 0
            let scale = 1 + flash * 0.3
            let alpha = 0.32 + flash * 0.5
            ctx.draw(Text("\(n)")
                .font(.system(size: 46 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(color.opacity(alpha)),
                     at: CGPoint(x: x, y: y))
        }
        number(engine.botScore, side: .bot, color: Palette.bumperCoral,
               x: origin.x + engine.courtW * 0.25)
        number(engine.playerScore, side: .player, color: Palette.boostBlueDeep,
               x: origin.x + engine.courtW * 0.75)
    }

    // MARK: Ball & paddles

    private func drawTrail(_ ctx: GraphicsContext) {
        guard engine.serveAt == nil, engine.trail.count > 2 else { return }
        drawTaperedTrail(ctx, points: engine.trail,
                         color: engine.smashActive ? Palette.gold : Palette.boostBlue,
                         alphaBase: 0.04, alphaGain: 0.30,
                         width: PongEngine.ballR * 1.9, origin: origin)
    }

    private func drawBall(_ ctx: GraphicsContext) {
        guard engine.gameOver == nil else { return }
        let c = pt(engine.ballPos)
        let r = PongEngine.ballR
        drawBallShadow(ctx, at: c, r: r)

        if engine.smashActive {
            // Layered fills fake the glow without a blur filter's offscreen
            // rasterize pass — see drawGlowStroke's note in ArcadeDraw.swift.
            ctx.fill(arcadeEllipse(at: c, rx: r * 2.6, ry: r * 2.6),
                     with: .color(Palette.gold.opacity(0.22)))
            ctx.fill(arcadeEllipse(at: c, rx: r * 1.9, ry: r * 1.9),
                     with: .color(Palette.gold.opacity(0.4)))
        }

        let speed = engine.ballVel.length
        drawArcadeBall(ctx, at: c, r: r, vel: engine.ballVel,
                       stretch: min(speed / 900, 0.28),
                       squash: decay(engine.lastHitAt, 0.13, now: time) * 0.3,
                       fill: engine.smashActive ? Palette.gold : Palette.wallTop,
                       rotates: speed > 1)
    }

    private func drawPaddles(_ ctx: GraphicsContext) {
        func paddle(x: Double, y: Double, h: Double, color: Color, core: Color,
                    hitAt: Double, bumpDir: Double, glow: Bool) {
            let bump = decay(hitAt, 0.16, now: time)
            let px = origin.x + x + bumpDir * bump * 3
            let rect = CGRect(x: px - PongEngine.paddleW / 2,
                              y: origin.y + y - h / 2,
                              width: PongEngine.paddleW, height: h)
            drawArcadePaddle(ctx, rect: rect, fill: color, core: core, vertical: true,
                             flash: bump, flashAlpha: 0.55,
                             glowOpacity: glow ? 0.6 + 0.25 * sin(time * 6) : nil)
        }
        paddle(x: PongEngine.paddleInset - PongEngine.paddleW / 2, y: engine.botY,
               h: engine.botH, color: Palette.bumperCoral,
               core: Color(red: 0.96, green: 0.72, blue: 0.65),
               hitAt: engine.botHitAt, bumpDir: -1,
               glow: engine.botCharge >= engine.botChargeThreshold)
        paddle(x: engine.courtW - PongEngine.paddleInset + PongEngine.paddleW / 2,
               y: engine.playerY, h: engine.playerH, color: Palette.boostBlue,
               core: Palette.paddleCore,
               hitAt: engine.playerHitAt, bumpDir: 1,
               glow: engine.playerSmashReady)
    }

    // MARK: Effects

    private func drawRipples(_ ctx: GraphicsContext) {
        for ripple in engine.ripples {
            let t = (time - ripple.at) / 0.5
            guard t >= 0, t < 1 else { continue }
            let e = 1 - pow(1 - t, 2)
            let color = ripple.gold ? Palette.gold : Palette.ink
            ctx.stroke(arcadeEllipse(at: pt(ripple.pos), rx: 3 + e * 22, ry: 3 + e * 22),
                       with: .color(color.opacity(0.4 * (1 - t))),
                       style: StrokeStyle(lineWidth: 1.6 * (1 - t) + 0.4))
        }
    }

    private func drawOrb(_ ctx: GraphicsContext) {
        guard let o = engine.orb else { return }
        let age = time - o.born
        let life = PongEngine.orbLife
        let fade = min(1, min(age / 0.2, (life - age) / 0.3))
        guard fade > 0 else { return }
        // Pop-in overshoots slightly, then settles.
        let pop = min(1, age / 0.25)
        let r = 8.0 * (0.6 + 0.4 * pop + 0.12 * sin(pop * .pi))
        let bob = sin(time * 2.2) * 1.8
        let rest = CGPoint(x: origin.x + o.pos.x, y: origin.y + o.pos.y)
        let c = CGPoint(x: rest.x, y: rest.y + bob)
        let (main, deep): (Color, Color) = o.kind == .bolt
            ? (Palette.gold, Palette.goldDeep)
            : (Palette.boostBlue, Palette.boostBlueDeep)

        var g = ctx
        g.opacity = fade

        // Ground shadow, tightening as the token bobs up.
        g.fill(arcadeEllipse(at: CGPoint(x: rest.x, y: rest.y + 8), rx: 5.5 - bob * 0.5, ry: 2.1),
               with: .color(Palette.shadow))

        // Countdown arc drains around the token; a soft pulse near expiry
        // stands in for the old blink.
        let remain = 1 - age / life
        if remain > 0.02 {
            let urgency = age > life - 2.5 ? 0.15 * sin(time * 7) : 0
            var arc = Path()
            arc.addArc(center: c, radius: r + 3.4,
                       startAngle: .degrees(-90),
                       endAngle: .degrees(-90 + 360 * remain),
                       clockwise: false)
            g.stroke(arc, with: .color(deep.opacity(0.55 + urgency)),
                     style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }

        // Flat token: deep under-disc peeks out as a bottom-right crescent,
        // like the golf coin's two-tone shading.
        g.fill(arcadeEllipse(at: c, rx: r, ry: r), with: .color(deep))
        g.fill(arcadeEllipse(at: CGPoint(x: c.x - r * 0.09, y: c.y - r * 0.13),
                             rx: r * 0.93, ry: r * 0.93),
               with: .color(main))
        g.stroke(arcadeEllipse(at: c, rx: r, ry: r), with: .color(Palette.ink),
                 style: StrokeStyle(lineWidth: 1.5))
        g.fill(arcadeEllipse(at: CGPoint(x: c.x - r * 0.34, y: c.y - r * 0.44),
                             rx: r * 0.26, ry: r * 0.17),
               with: .color(.white.opacity(0.5)))

        // Symbol with a hairline drop for legibility on the bright fill.
        let symbol = Text(Image(systemName: o.kind == .bolt ? "bolt.fill" : "arrow.up.and.down"))
            .font(.system(size: 9.5, weight: .bold))
        g.draw(symbol.foregroundStyle(Palette.ink.opacity(0.35)),
               at: CGPoint(x: c.x, y: c.y + 1.2))
        g.draw(symbol.foregroundStyle(.white), at: CGPoint(x: c.x, y: c.y + 0.5))
    }

    private func drawCharge(_ ctx: GraphicsContext) {
        // Segmented meter above the player's corner; glows when armed.
        let ready = engine.playerSmashReady
        let w = 10.0, gap = 3.0
        let x0 = origin.x + engine.courtW - 46
        let y = origin.y + engine.courtH - 16
        if ready {
            // Two nested fills fake the glow without a blur filter.
            let outer = Path(roundedRect: CGRect(x: x0 - 5, y: y - 6.4,
                                                 width: (w + gap) * 3 + 7, height: 12.8),
                             cornerRadius: 6.4)
            let inner = Path(roundedRect: CGRect(x: x0 - 3, y: y - 4.4,
                                                 width: (w + gap) * 3 + 3, height: 8.8),
                             cornerRadius: 4.4)
            ctx.fill(outer, with: .color(Palette.gold.opacity(0.28)))
            ctx.fill(inner, with: .color(Palette.gold.opacity(0.45)))
        }
        for i in 0..<PongEngine.playerChargeMax {
            let filled = engine.playerCharge > i || ready
            let rect = CGRect(x: x0 + Double(i) * (w + gap), y: y - 2.2, width: w, height: 4.4)
            let seg = Path(roundedRect: rect, cornerRadius: 2.2)
            ctx.fill(seg, with: .color(filled ? Palette.gold : Palette.ink.opacity(0.14)))
            ctx.stroke(seg, with: .color(Palette.ink.opacity(filled ? 0.55 : 0.2)),
                       style: StrokeStyle(lineWidth: 0.8))
        }
    }

    private func drawServe(_ ctx: GraphicsContext) {
        guard let s = engine.serveAt, engine.gameOver == nil else { return }
        let remain = max(0, s - time)
        let pulse = 1 - (remain.truncatingRemainder(dividingBy: 0.45)) / 0.45
        let c = CGPoint(x: origin.x + engine.courtW / 2, y: origin.y + engine.courtH / 2)
        ctx.stroke(arcadeEllipse(at: c, rx: 8 + pulse * 12, ry: 8 + pulse * 12),
                   with: .color(Palette.ink.opacity(0.4 * (1 - pulse))),
                   style: StrokeStyle(lineWidth: 1.6))
        // Chevrons hint at the serve direction.
        let dir: Double = engine.serveToward == .player ? 1 : -1
        let drift = pulse * 6
        for k in 0..<2 {
            let x = c.x + dir * (16 + Double(k) * 8 + drift)
            var chev = Path()
            chev.move(to: CGPoint(x: x - dir * 3.4, y: c.y - 4.4))
            chev.addLine(to: CGPoint(x: x, y: c.y))
            chev.addLine(to: CGPoint(x: x - dir * 3.4, y: c.y + 4.4))
            ctx.stroke(chev, with: .color(Palette.ink.opacity(0.45 * (1 - pulse * 0.6))),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        // The waiting ball.
        ctx.fill(arcadeEllipse(at: c, rx: PongEngine.ballR, ry: PongEngine.ballR),
                 with: .color(Palette.wallTop))
        ctx.stroke(arcadeEllipse(at: c, rx: PongEngine.ballR, ry: PongEngine.ballR),
                   with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.5))
    }
}
