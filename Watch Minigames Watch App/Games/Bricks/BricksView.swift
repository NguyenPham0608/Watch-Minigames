//
//  BricksView.swift
//  Watch Minigames Watch App
//
//  Brick Breaker: steer the paddle with a drag or the crown, tap to serve.
//  Endless levels — each clear rebuilds the wall a little meaner.
//

import SwiftUI

// MARK: - View

struct BricksView: View {
    @Environment(ScoreStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var engine = BricksEngine()
    @State private var finalScore: Int? = nil
    @State private var wasBest = false
    @State private var dragStartX: Double? = nil

    var body: some View {
        ArcadeScreen { size, date in
            canvasView(size: size, date: date)
        } overlay: {
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
        .crownDetents { detents in
            engine.paddleTarget = min(max(engine.paddleTarget + detents * CrownFeel.pointsPerDetent,
                                          0), engine.courtW)
        }
        .onAppear {
            engine.onGameOver = { score in
                wasBest = store.recordArcadeBest("bricks", score)
                withAnimation(.arcadePop) { finalScore = score }
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

    /// Drag steers the paddle; a bare tap serves.
    private var paddleDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartX == nil { dragStartX = engine.paddleTarget }
                let target = (dragStartX ?? 0) + Double(value.translation.width) * 1.3
                engine.paddleTarget = min(max(target, 0), engine.courtW)
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
        (Palette.bumperCoral, Palette.coralDeep),
        (Palette.gold, Palette.goldDeep),
        (Palette.teal, Palette.tealDeep),
        (Palette.boostBlue, Palette.boostBlueDeep),
        (Palette.plumPurple, Palette.plumDeep),
        (Palette.hillLight, Palette.deepGreen),
    ]

    func draw(into base: GraphicsContext) {
        var ctx = base
        if engine.shakeAmp > 0.15 {
            let shake = shakeOffset(time: time, amp: engine.shakeAmp)
            ctx.translateBy(x: shake.width, y: shake.height)
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
        let flash = decay(engine.lastLevelAt, 0.5, now: time)
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
        drawTaperedTrail(ctx, points: engine.trail, color: Palette.boostBlue,
                         alphaBase: 0.05, alphaGain: 0.28,
                         width: BricksEngine.ballR * 1.8)
    }

    private func drawPaddle(_ ctx: GraphicsContext) {
        let bump = decay(engine.paddleHitAt, 0.16, now: time)
        let rect = CGRect(x: engine.paddleX - BricksEngine.paddleW / 2,
                          y: engine.paddleY - BricksEngine.paddleH / 2 + bump * 2,
                          width: BricksEngine.paddleW, height: BricksEngine.paddleH)
        // Cartoon squash on the return: wider and flatter, springing back.
        var g = ctx
        if bump > 0 {
            g.translateBy(x: rect.midX, y: rect.midY)
            g.scaleBy(x: 1 + bump * 0.10, y: 1 - bump * 0.16)
            g.translateBy(x: -rect.midX, y: -rect.midY)
        }
        drawArcadePaddle(g, rect: rect, fill: Palette.boostBlue, core: Palette.paddleCore,
                         vertical: false, flash: bump, flashAlpha: 0.5)
    }

    private func drawBall(_ ctx: GraphicsContext) {
        guard engine.state != .done else { return }
        let c = engine.ballPos.cg
        let r = BricksEngine.ballR
        drawBallShadow(ctx, at: c, r: r)
        let speed = engine.ballVel.length
        drawArcadeBall(ctx, at: c, r: r, vel: engine.ballVel,
                       stretch: engine.state == .playing ? min(speed / 900, 0.25) : 0,
                       squash: decay(engine.lastHitAt, 0.13, now: time) * 0.3,
                       fill: Palette.wallTop,
                       rotates: speed > 1 && engine.state == .playing)
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
            psh.fill(paddle, with: .color(Palette.shadow))
            ctx.fill(paddle, with: .color(Palette.boostBlue))
            var stripe = Path()
            stripe.move(to: CGPoint(x: rect.minX + 4, y: rect.midY))
            stripe.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.midY))
            ctx.stroke(stripe, with: .color(Palette.paddleCore),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            ctx.stroke(paddle, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.3))
        }
    }
}
