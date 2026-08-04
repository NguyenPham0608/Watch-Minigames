//
//  PongView.swift
//  Minigames Watch App
//
//  Super Pong: the golf game's flat ink style with a light futuristic twist —
//  grid floor, glowing smash trails, particle bursts.
//

import SwiftUI

struct PongView: View {
    @Environment(ScoreStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var engine = PongEngine()
    @State private var crown = 0.5
    @State private var winner: PongEngine.Side? = nil
    /// Paddle position when a finger drag began.
    @State private var dragStartY: Double? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation) { timeline in
                    canvasView(size: geo.size, date: timeline.date)
                }
                if let winner { resultOverlay(winner) }
            }
        }
        .ignoresSafeArea()
        .focusable()
        .digitalCrownRotation($crown, from: 0, through: 1, by: 0.001,
                              sensitivity: .low, isContinuous: false,
                              isHapticFeedbackEnabled: false)
        .onChange(of: crown) { _, newValue in
            // Crown up moves the paddle up.
            engine.playerTarget = (1 - newValue) * engine.courtH
        }
        .onAppear {
            engine.difficulty = store.pongDifficulty
            engine.onGameOver = { w in
                if w == .player { store.recordPongWin() }
                withAnimation(.easeOut(duration: 0.3)) { winner = w }
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
    /// swipe can cover the court. Keeps the crown value in sync so the two
    /// controls hand off without a jump.
    private var paddleDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartY == nil { dragStartY = engine.playerTarget }
                let target = (dragStartY ?? 0) + Double(value.translation.height) * 1.2
                engine.playerTarget = min(max(target, 0), engine.courtH)
                crown = 1 - engine.playerTarget / max(engine.courtH, 1)
            }
            .onEnded { _ in dragStartY = nil }
    }

    private func resultOverlay(_ w: PongEngine.Side) -> some View {
        VStack(spacing: 6) {
            Text(w == .player ? "You Win!" : "Bot Wins")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(w == .player ? Palette.goldDeep : Palette.ink)
            Text("\(engine.playerScore) – \(engine.botScore)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink.opacity(0.55))
            HStack(spacing: 10) {
                Button {
                    engine.reset()
                    withAnimation { winner = nil }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Palette.gold))
                        .overlay(Circle().stroke(Palette.ink, lineWidth: 1.6))
                        .foregroundStyle(Palette.ink)
                }
                .buttonStyle(.plain)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white))
                        .overlay(Circle().stroke(Palette.ink, lineWidth: 1.6))
                        .foregroundStyle(Palette.ink)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.ink, lineWidth: 1.8))
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
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

    private func ellipse(at c: CGPoint, rx: Double, ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
    }

    private func ellipse(at c: CGPoint, r: Double) -> Path {
        ellipse(at: c, rx: r, ry: r)
    }

    /// 1 → 0 decay over `dur` seconds since `at`.
    private func decay(_ at: Double, _ dur: Double) -> Double {
        max(0, 1 - (time - at) / dur)
    }

    func draw(into base: GraphicsContext) {
        var ctx = base
        if engine.shakeAmp > 0.15 {
            ctx.translateBy(x: sin(time * 71) * engine.shakeAmp,
                            y: cos(time * 57) * engine.shakeAmp * 0.6)
        }

        drawBackground(ctx)
        drawDivider(ctx)
        drawScore(ctx)
        drawOrb(ctx)
        drawRipples(ctx)
        drawTrail(ctx)
        drawPaddles(ctx)
        drawBall(ctx)
        drawParticles(ctx)
        drawCharge(ctx)
        drawServe(ctx)
    }

    // MARK: Stage

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
            Gradient(colors: [.clear, Palette.ink.opacity(0.10)]),
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            startRadius: size.width * 0.35, endRadius: size.height * 0.85))

        // Goal glow strips, flaring in the scorer's color on a point.
        let flash = decay(engine.lastScoreAt, 0.6)
        let goalW = 20.0
        var leftA = 0.10, rightA = 0.10
        if let side = engine.lastScoreSide, flash > 0 {
            // The ball exited on the conceding side.
            if side == .player { leftA += flash * 0.4 } else { rightA += flash * 0.4 }
        }
        ctx.fill(Path(CGRect(x: 0, y: 0, width: goalW, height: size.height)),
                 with: .linearGradient(
                    Gradient(colors: [Palette.bumperCoral.opacity(leftA), .clear]),
                    startPoint: .zero, endPoint: CGPoint(x: goalW, y: 0)))
        ctx.fill(Path(CGRect(x: size.width - goalW, y: 0, width: goalW, height: size.height)),
                 with: .linearGradient(
                    Gradient(colors: [.clear, Palette.boostBlue.opacity(rightA)]),
                    startPoint: CGPoint(x: size.width - goalW, y: 0),
                    endPoint: CGPoint(x: size.width, y: 0)))

        // Clock scrim.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 42)),
                 with: .linearGradient(
                    Gradient(colors: [Color.black.opacity(0.28), .clear]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: 42)))
    }

    private func drawDivider(_ ctx: GraphicsContext) {
        let cx = size.width / 2
        var divider = Path()
        divider.move(to: CGPoint(x: cx, y: 8))
        divider.addLine(to: CGPoint(x: cx, y: size.height - 8))
        ctx.stroke(divider, with: .color(Palette.ink.opacity(0.16)),
                   style: StrokeStyle(lineWidth: 1.6, dash: [5, 6]))
        let mid = CGPoint(x: cx, y: size.height / 2)
        ctx.stroke(ellipse(at: mid, r: 17), with: .color(Palette.ink.opacity(0.16)),
                   style: StrokeStyle(lineWidth: 1.6))
        ctx.fill(ellipse(at: mid, r: 2.2), with: .color(Palette.ink.opacity(0.2)))
    }

    private func drawScore(_ ctx: GraphicsContext) {
        let y = origin.y + engine.courtH * 0.28
        func number(_ n: Int, side: PongEngine.Side, color: Color, x: Double) {
            let flash = engine.lastScoreSide == side ? decay(engine.lastScoreAt, 0.6) : 0
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
        let color = engine.smashActive ? Palette.gold : Palette.boostBlue
        let pts = engine.trail
        // Tapered ribbon: stacked round-cap segments thinning toward the tail.
        for i in 1..<pts.count {
            let f = Double(i) / Double(pts.count)
            var seg = Path()
            seg.move(to: pt(pts[i - 1]))
            seg.addLine(to: pt(pts[i]))
            ctx.stroke(seg, with: .color(color.opacity(0.04 + 0.30 * f * f)),
                       style: StrokeStyle(lineWidth: PongEngine.ballR * 1.9 * f,
                                          lineCap: .round))
        }
    }

    private func drawBall(_ ctx: GraphicsContext) {
        guard engine.gameOver == nil else { return }
        let c = pt(engine.ballPos)
        let r = PongEngine.ballR

        // Ground shadow.
        ctx.fill(ellipse(at: CGPoint(x: c.x, y: c.y + r * 0.9), rx: r * 0.95, ry: r * 0.4),
                 with: .color(Palette.shadow))

        if engine.smashActive {
            var glow = ctx
            glow.addFilter(.blur(radius: 4))
            glow.fill(ellipse(at: c, r: r * 2.2), with: .color(Palette.gold.opacity(0.7)))
        }

        // Squash on impact, stretch with speed — drawn in a rotated frame
        // aligned to the velocity.
        let speed = engine.ballVel.length
        let stretch = min(speed / 900, 0.28)
        let squash = decay(engine.lastHitAt, 0.13) * 0.3
        let sx = 1 + stretch - squash
        let sy = 1 - (stretch - squash) * 0.7
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        if speed > 1 { g.rotate(by: Angle(radians: atan2(engine.ballVel.y, engine.ballVel.x))) }
        g.scaleBy(x: sx, y: sy)
        let fill = engine.smashActive ? Palette.gold : Palette.wallTop
        g.fill(ellipse(at: .zero, r: r), with: .color(fill))
        g.stroke(ellipse(at: .zero, r: r), with: .color(Palette.ink),
                 style: StrokeStyle(lineWidth: 1.5))
        g.fill(ellipse(at: CGPoint(x: -r * 0.3, y: -r * 0.35), rx: r * 0.24, ry: r * 0.2),
               with: .color(.white.opacity(0.9)))
    }

    private func drawPaddles(_ ctx: GraphicsContext) {
        func paddle(x: Double, y: Double, h: Double, color: Color, core: Color,
                    hitAt: Double, bumpDir: Double, glow: Bool) {
            let bump = decay(hitAt, 0.16)
            let px = origin.x + x + bumpDir * bump * 3
            let rect = CGRect(x: px - PongEngine.paddleW / 2,
                              y: origin.y + y - h / 2,
                              width: PongEngine.paddleW, height: h)
            let shape = Path(roundedRect: rect, cornerRadius: PongEngine.paddleW / 2)

            // Soft shadow, smash aura, body, ink, inner core stripe.
            var sh = ctx
            sh.translateBy(x: 1.2, y: 2)
            sh.addFilter(.blur(radius: 1.6))
            sh.fill(shape, with: .color(Palette.shadow))
            if glow {
                var g = ctx
                g.addFilter(.blur(radius: 3.5))
                g.fill(shape.strokedPath(StrokeStyle(lineWidth: 5)),
                       with: .color(Palette.gold.opacity(0.6 + 0.25 * sin(time * 6))))
            }
            ctx.fill(shape, with: .color(color))
            var stripe = Path()
            stripe.move(to: CGPoint(x: rect.midX, y: rect.minY + 4))
            stripe.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 4))
            ctx.stroke(stripe, with: .color(core),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            ctx.stroke(shape, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.5))
            if bump > 0 {
                ctx.fill(shape, with: .color(.white.opacity(bump * 0.55)))
            }
        }
        paddle(x: PongEngine.paddleInset - PongEngine.paddleW / 2, y: engine.botY,
               h: engine.botH, color: Palette.bumperCoral,
               core: Color(red: 0.96, green: 0.72, blue: 0.65),
               hitAt: engine.botHitAt, bumpDir: -1,
               glow: engine.botCharge >= engine.botChargeThreshold)
        paddle(x: engine.courtW - PongEngine.paddleInset + PongEngine.paddleW / 2,
               y: engine.playerY, h: engine.playerH, color: Palette.boostBlue,
               core: Color(red: 0.76, green: 0.88, blue: 0.95),
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
            ctx.stroke(ellipse(at: pt(ripple.pos), r: 3 + e * 22),
                       with: .color(color.opacity(0.4 * (1 - t))),
                       style: StrokeStyle(lineWidth: 1.6 * (1 - t) + 0.4))
        }
    }

    private func drawOrb(_ ctx: GraphicsContext) {
        guard let o = engine.orb else { return }
        let age = time - o.born
        var fade = min(1, min(age / 0.25, (9 - age) / 0.4))
        guard fade > 0 else { return }
        // Urgency blink in the final seconds.
        if age > 7 { fade *= 0.65 + 0.35 * sin(time * 10) }
        let bob = sin(time * 2.4) * 2
        let c = CGPoint(x: origin.x + o.pos.x, y: origin.y + o.pos.y + bob)
        let r = 8.0 * (0.6 + 0.4 * min(1, age / 0.25))   // pops in
        let (main, deep): (Color, Color) = o.kind == .bolt
            ? (Palette.gold, Palette.goldDeep)
            : (Palette.boostBlue, Palette.boostBlueDeep)

        var g = ctx
        g.opacity = fade

        // Ground shadow.
        g.fill(ellipse(at: CGPoint(x: c.x, y: c.y + 7 - bob), rx: 6.5, ry: 2.4),
               with: .color(Palette.shadow))

        // Soft radial aura.
        g.fill(ellipse(at: c, r: r * 2.3), with: .radialGradient(
            Gradient(colors: [main.opacity(0.32), .clear]),
            center: c, startRadius: r * 0.4, endRadius: r * 2.3))

        // Spinning containment ring with two orbiting sparks.
        let ringR = r + 4.5
        g.stroke(ellipse(at: c, r: ringR), with: .color(main.opacity(0.85)),
                 style: StrokeStyle(lineWidth: 1.4, dash: [4.5, 3.5], dashPhase: time * 14))
        for k in 0..<2 {
            let a = time * 2.6 + Double(k) * .pi
            let sp = CGPoint(x: c.x + cos(a) * ringR, y: c.y + sin(a) * ringR * 0.94)
            g.fill(ellipse(at: sp, r: 3.0), with: .color(.white.opacity(0.3)))
            g.fill(ellipse(at: sp, r: 1.6), with: .color(.white))
        }

        // Gem body: radially lit disc with an ink rim and a glass gleam.
        g.fill(ellipse(at: c, r: r), with: .radialGradient(
            Gradient(colors: [main, deep]),
            center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4),
            startRadius: 0, endRadius: r * 1.9))
        g.stroke(ellipse(at: c, r: r), with: .color(Palette.ink),
                 style: StrokeStyle(lineWidth: 1.5))
        g.fill(ellipse(at: CGPoint(x: c.x - r * 0.32, y: c.y - r * 0.42),
                       rx: r * 0.3, ry: r * 0.2),
               with: .color(.white.opacity(0.55)))

        // Crisp symbol instead of hand-drawn strokes.
        g.draw(Text(Image(systemName: o.kind == .bolt ? "bolt.fill" : "arrow.up.and.down"))
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(.white),
               at: CGPoint(x: c.x, y: c.y + 0.5))
    }

    private func drawParticles(_ ctx: GraphicsContext) {
        for particle in engine.particles {
            let a = max(0, particle.life / particle.maxLife)
            let c = pt(particle.pos)
            let color: Color
            switch particle.hue {
            case .gold: color = Palette.gold
            case .shard: color = Palette.wallSide
            case .grass: color = Palette.fairwayStripe
            case .white: color = .white
            case .confetti(let i):
                color = Palette.confettiColors[i % Palette.confettiColors.count]
            }
            let r = particle.size / 2 + 0.6
            // Soft halo under each spark keeps bursts from feeling flat.
            ctx.fill(ellipse(at: c, r: r * 2), with: .color(color.opacity(a * 0.18)))
            ctx.fill(ellipse(at: c, r: r), with: .color(color.opacity(a)))
        }
    }

    private func drawCharge(_ ctx: GraphicsContext) {
        // Segmented meter above the player's corner; glows when armed.
        let ready = engine.playerSmashReady
        let w = 10.0, gap = 3.0
        let x0 = origin.x + engine.courtW - 46
        let y = origin.y + engine.courtH - 16
        if ready {
            var g = ctx
            g.addFilter(.blur(radius: 3))
            g.fill(Path(roundedRect: CGRect(x: x0 - 3, y: y - 4.4,
                                            width: (w + gap) * 3 + 3, height: 8.8),
                        cornerRadius: 4.4),
                   with: .color(Palette.gold.opacity(0.55)))
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
        ctx.stroke(ellipse(at: c, r: 8 + pulse * 12),
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
        ctx.fill(ellipse(at: c, r: PongEngine.ballR), with: .color(Palette.wallTop))
        ctx.stroke(ellipse(at: c, r: PongEngine.ballR), with: .color(Palette.ink),
                   style: StrokeStyle(lineWidth: 1.5))
    }
}
