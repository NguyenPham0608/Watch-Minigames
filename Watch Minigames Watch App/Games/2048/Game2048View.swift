//
//  Game2048View.swift
//  Watch Minigames Watch App
//
//  2048 rendering: an inked board of springy flat-color tiles climbing the
//  palette from cream through coral and blue to the gold 2048.
//

import SwiftUI

struct Game2048View: View {
    @Environment(ScoreStore.self) private var store

    @State private var engine = Game2048Engine()
    @State private var finalScore: Int? = nil
    @State private var wasBest = false

    var body: some View {
        ArcadeScreen { size, date in
            canvasView(size: size, date: date)
        } overlay: {
            if let score = finalScore {
                ResultCard(title: "Score \(score)",
                           subtitle: wasBest && score > 0
                               ? "New Best" : "Best \(store.arcadeBest("2048"))",
                           titleGold: score > 0,
                           subtitleGold: wasBest && score > 0) {
                    engine.reset()
                    withAnimation { finalScore = nil }
                }
            }
        }
        .onAppear {
            engine.onGameOver = { score in
                wasBest = store.recordArcadeBest("2048", score)
                withAnimation(.easeOut(duration: 0.3)) { finalScore = score }
            }
        }
    }

    private func canvasView(size: CGSize, date: Date) -> some View {
        engine.courtW = size.width
        engine.courtH = size.height
        engine.step(to: date)
        let renderer = Game2048Renderer(engine: engine, size: size, time: engine.time)
        return Canvas { ctx, _ in
            renderer.draw(into: ctx)
        }
        .gesture(swipe)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                let t = value.translation
                let d: Game2048Engine.Dir = abs(t.width) > abs(t.height)
                    ? (t.width > 0 ? .right : .left)
                    : (t.height > 0 ? .down : .up)
                engine.move(d)
            }
    }
}

// MARK: - Renderer

struct Game2048Renderer {
    let engine: Game2048Engine
    let size: CGSize
    let time: Double

    /// Flat cartoon fills climbing the shared palette; ink text on the light
    /// low tiles, white on the saturated ones.
    static func style(for value: Int) -> (fill: Color, text: Color) {
        switch value {
        case 2: return (Palette.wallTop, Palette.ink)
        case 4: return (Palette.sand, Palette.ink)
        case 8: return (Palette.gold, Palette.ink)
        case 16: return (Palette.goldDeep, .white)
        case 32: return (Palette.bumperCoral, .white)
        case 64: return (Palette.coralDeep, .white)
        case 128: return (Palette.plumPurple, .white)
        case 256: return (Palette.plumDeep, .white)
        case 512: return (Palette.boostBlue, .white)
        case 1024: return (Palette.boostBlueDeep, .white)
        case 2048: return (Palette.deepGreen, .white)
        default: return (Palette.ink, Palette.gold)
        }
    }

    func draw(into base: GraphicsContext) {
        var ctx = base
        if engine.shakeAmp > 0.15 {
            let shake = shakeOffset(time: time, amp: engine.shakeAmp)
            ctx.translateBy(x: shake.width, y: shake.height)
        }

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.bg))
        drawWallpaperDots(ctx, size: size)
        drawClockScrim(ctx, size: size)
        drawScore(ctx)

        let l = engine.layout()

        var g = ctx
        // Fresh boards pop in: a beat of fade with a springy settle.
        let intro = min((time - engine.introAt) / 0.45, 1)
        if intro < 1 {
            let e = easeOutBack(intro, 1.2)
            let cx = l.ox + l.board / 2
            let cy = l.oy + l.board / 2
            g.opacity = min(intro / 0.25, 1)
            g.translateBy(x: cx, y: cy)
            g.scaleBy(x: 0.88 + 0.12 * e, y: 0.88 + 0.12 * e)
            g.translateBy(x: -cx, y: -cy)
        }
        // Whole board (slab + tiles) nudges in the swipe direction on a slam.
        let nt = 1 - decay(engine.nudgeAt, 0.16, now: time)
        let nudge = decay(engine.nudgeAt, 0.16, now: time) * sin(min(nt, 1) * .pi)
        g.translateBy(x: engine.nudgeDir.x * 3 * nudge,
                      y: engine.nudgeDir.y * 3 * nudge)

        drawSlab(g, l)
        // Dying tiles slide beneath their absorbers.
        for tile in engine.tiles where tile.dying { drawTile(g, tile, l) }
        for tile in engine.tiles where !tile.dying { drawTile(g, tile, l) }

        // A nearly full board breathes a soft coral warning at the edges.
        let live = engine.tiles.filter { !$0.dying }.count
        if live >= 15, !engine.done {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                Gradient(colors: [.clear, Palette.bumperCoral.opacity(0.15 + 0.06 * sin(time * 3.2))]),
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                startRadius: size.width * 0.42, endRadius: size.height * 0.72))
        }

        drawArcadeParticles(ctx, engine.particles)
        drawFloaters(ctx, engine.floaters, time: time)

        if engine.done {
            let fade = min((time - engine.doneAt) / 0.35, 1)
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Palette.ink.opacity(0.18 * fade)))
        }
    }

    /// Plain ink score under the clock — pops and warms gold on a merge.
    private func drawScore(_ ctx: GraphicsContext) {
        let flash = decay(engine.lastMergeAt, 0.35, now: time)
        let fontSize: Double = 20 * (1 + flash * 0.12)
        let color: Color = flash > 0
            ? Palette.goldDeep.opacity(0.6 + 0.4 * flash)
            : Palette.ink.opacity(0.6)
        let label = Text("\(engine.score)")
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
        ctx.draw(label, at: CGPoint(x: size.width - 12, y: 52), anchor: .trailing)
    }

    private func drawSlab(_ ctx: GraphicsContext, _ l: Game2048Engine.Layout) {
        let slab = Path(roundedRect: CGRect(x: l.ox, y: l.oy,
                                            width: l.board, height: l.board),
                        cornerRadius: 11)
        var sh = ctx
        sh.translateBy(x: 2, y: 3.5)
        sh.addFilter(.blur(radius: 2.5))
        sh.fill(slab, with: .color(Palette.shadow))
        ctx.fill(slab, with: .color(.white.opacity(0.6)))
        ctx.stroke(slab, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.8))

        for col in 0..<4 {
            for row in 0..<4 {
                let well = Path(roundedRect: l.rect(Double(col), Double(row)),
                                cornerRadius: l.cell * 0.2)
                ctx.fill(well, with: .color(Palette.ink.opacity(0.07)))
            }
        }
    }

    private func drawTile(_ ctx: GraphicsContext, _ tile: Game2048Engine.Tile,
                          _ l: Game2048Engine.Layout) {
        // Animated grid position: eased slide from the previous cell.
        let st = min((time - tile.movedAt) / Game2048Engine.slideDur, 1)
        let e = tile.movedAt < 0 ? 1 : easeOutBack(st)
        let colD = Double(tile.fromCol) + (Double(tile.col) - Double(tile.fromCol)) * e
        let rowD = Double(tile.fromRow) + (Double(tile.row) - Double(tile.fromRow)) * e
        let rect = l.rect(colD, rowD)

        // Spawn pop-in (with a fade so tiny scales never look glitchy) and
        // merge pop.
        var scale = 1.0
        let born = time - tile.spawnedAt
        if born < 0.18 { scale = easeOutBack(born / 0.18, 1.7) }
        let merge = decay(tile.mergedAt, 0.22, now: time)
        if merge > 0 { scale += 0.24 * sin((1 - merge) * .pi) }
        guard scale > 0.02 else { return }

        var g = ctx
        if born < 0.12 { g.opacity *= max(born / 0.12, 0) }
        g.translateBy(x: rect.midX, y: rect.midY)
        g.scaleBy(x: scale, y: scale)
        g.translateBy(x: -rect.midX, y: -rect.midY)

        let (fill, text) = Self.style(for: tile.value)
        let shape = Path(roundedRect: rect, cornerRadius: l.cell * 0.2)

        // Big merges bloom a brief gold aura behind the tile.
        if merge > 0, tile.value >= 128 {
            g.fill(Path(ellipseIn: rect.insetBy(dx: -l.cell * 0.35, dy: -l.cell * 0.35)),
                   with: .radialGradient(
                       Gradient(colors: [Palette.gold.opacity(0.45 * merge), .clear]),
                       center: CGPoint(x: rect.midX, y: rect.midY),
                       startRadius: l.cell * 0.2, endRadius: l.cell * 0.85))
        }

        var sh = g
        sh.translateBy(x: 0.8, y: 1.6)
        sh.fill(shape, with: .color(Palette.shadow))
        g.fill(shape, with: .color(fill))
        // White flash right as a merge lands, fading as the pop settles.
        if merge > 0 { g.fill(shape, with: .color(.white.opacity(0.4 * merge))) }
        // The 2048 tile earns a gold halo.
        if tile.value >= 2048 {
            g.stroke(Path(roundedRect: rect.insetBy(dx: -2.2, dy: -2.2),
                          cornerRadius: l.cell * 0.2 + 2.2),
                     with: .color(Palette.gold.opacity(0.6 + 0.25 * sin(time * 5))),
                     style: StrokeStyle(lineWidth: 2.2))
        }
        g.stroke(shape, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.5))

        let digits = "\(tile.value)".count
        let fontSize = digits <= 2 ? l.cell * 0.44 : (digits == 3 ? l.cell * 0.36 : l.cell * 0.28)
        g.draw(Text("\(tile.value)")
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .foregroundStyle(text),
               at: CGPoint(x: rect.midX, y: rect.midY))
    }
}

// MARK: - Home page

struct Game2048Home: View {
    var body: some View {
        GameHome(title: "2048") { t in
            Game2048Scene(t: t)
        } destination: {
            Game2048View()
        }
    }
}

/// Little vignette: two 2-tiles slide together and pop into a gold 4, over
/// and over — the whole game in one breath.
private struct Game2048Scene: View {
    let t: Double

    var body: some View {
        Canvas { ctx, size in
            let cell = 26.0
            let gap = 5.0
            let cx = size.width / 2
            let cy = size.height / 2 + 4

            func well(_ i: Int) -> CGRect {
                CGRect(x: cx - cell * 1.5 - gap + Double(i) * (cell + gap),
                       y: cy - cell / 2, width: cell, height: cell)
            }
            func rr(_ r: CGRect, _ inset: Double = 0) -> Path {
                Path(roundedRect: r.insetBy(dx: inset, dy: inset), cornerRadius: 6)
            }

            // Mini slab with three wells.
            let slabRect = CGRect(x: well(0).minX - gap, y: cy - cell / 2 - gap,
                                  width: (cell + gap) * 3 + gap, height: cell + gap * 2)
            let slab = Path(roundedRect: slabRect, cornerRadius: 8)
            var sh = ctx
            sh.translateBy(x: 1.5, y: 2.5)
            sh.addFilter(.blur(radius: 2))
            sh.fill(slab, with: .color(Palette.shadow))
            ctx.fill(slab, with: .color(.white.opacity(0.6)))
            ctx.stroke(slab, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.5))
            for i in 0..<3 {
                ctx.fill(rr(well(i)), with: .color(Palette.ink.opacity(0.07)))
            }

            let u = (t / 3.2).truncatingRemainder(dividingBy: 1)

            func tile(_ rect: CGRect, _ value: Int, _ fill: Color,
                      _ text: Color, scale: Double) {
                guard scale > 0.03 else { return }
                var g = ctx
                g.translateBy(x: rect.midX, y: rect.midY)
                g.scaleBy(x: scale, y: scale)
                g.translateBy(x: -rect.midX, y: -rect.midY)
                var s2 = g
                s2.translateBy(x: 0.8, y: 1.4)
                s2.fill(rr(rect), with: .color(Palette.shadow))
                g.fill(rr(rect), with: .color(fill))
                g.stroke(rr(rect), with: .color(Palette.ink),
                         style: StrokeStyle(lineWidth: 1.4))
                g.draw(Text("\(value)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(text),
                       at: CGPoint(x: rect.midX, y: rect.midY))
            }

            if u < 0.3 {
                // Two 2s spring toward the center well.
                let e = easeOutBack(u / 0.3)
                let leftR = well(0).offsetBy(dx: (well(1).minX - well(0).minX) * e, dy: 0)
                let rightR = well(2).offsetBy(dx: (well(1).minX - well(2).minX) * e, dy: 0)
                tile(rightR, 2, Palette.wallTop, Palette.ink, scale: 1)
                tile(leftR, 2, Palette.wallTop, Palette.ink, scale: 1)
            } else if u < 0.85 {
                // Pop! A gold 4, with a sparkle fan.
                let pop = 1 + 0.25 * sin(min((u - 0.3) / 0.16, 1) * .pi)
                tile(well(1), 4, Palette.gold, Palette.ink, scale: pop)
                let q = (u - 0.3) / 0.2
                if q < 1 {
                    for k in 0..<7 {
                        let a = Double(k) / 7 * 2 * .pi + 0.5
                        let r = 14 + q * 12
                        let p = CGPoint(x: well(1).midX + cos(a) * r,
                                        y: well(1).midY + sin(a) * r * 0.8)
                        let sz = 1.9 * (1 - q)
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - sz, y: p.y - sz,
                                                        width: sz * 2, height: sz * 2)),
                                 with: .color((k.isMultiple(of: 2) ? Palette.gold : .white)
                                     .opacity(1 - q)))
                    }
                }
            } else {
                // The 4 fades off; fresh 2s pop back in at the edges.
                let fade = 1 - (u - 0.85) / 0.15
                tile(well(1), 4, Palette.gold.opacity(fade), Palette.ink.opacity(fade),
                     scale: 0.9 + 0.1 * fade)
                let popIn = easeOutBack((u - 0.9) / 0.1)
                tile(well(0), 2, Palette.wallTop, Palette.ink, scale: popIn)
                tile(well(2), 2, Palette.wallTop, Palette.ink, scale: popIn)
            }
        }
    }
}
