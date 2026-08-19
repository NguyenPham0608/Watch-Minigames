//
//  PairsView.swift
//  Watch Minigames Watch App
//
//  Pairs: a calm 4×4 memory board. Flip two cards at a time, keep the
//  matches, and clear all eight pairs in as few moves as you can.
//

import SwiftUI

// MARK: - Engine

final class PairsEngine {

    enum Glyph: CaseIterable { case apple, flag, heart, bolt, coin, leaf, star, ball }

    struct Card {
        let glyph: Glyph
        var faceUp = false
        var matched = false
        var flipAt = -10.0
        var matchedAt = -10.0
        var missAt = -10.0
    }

    /// How long a missed pair stays up for studying before flipping back.
    static let studyBeat = 0.75

    var cards: [Card] = []
    var moves = 0
    var time = 0.0
    /// Cards scale in staggered from this moment on every fresh deal.
    var dealAt = 0.0
    var particles: [Particle] = []
    /// Canvas size, fed by the view so match bursts land on card centers.
    var boardSize = CGSize(width: 180, height: 220)
    var onComplete: ((Int) -> Void)?

    private var finished = false
    /// The lone face-up card waiting for its partner, if any.
    private var firstPick: Int? = nil
    private var lastDate: Date?

    init() {
        deal()
    }

    private func deal() {
        var glyphs = Glyph.allCases + Glyph.allCases
        glyphs.shuffle()
        cards = glyphs.map { Card(glyph: $0) }
    }

    private var faceUpUnmatched: Int {
        cards.reduce(0) { $0 + (($1.faceUp && !$1.matched) ? 1 : 0) }
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
        updateParticles(&particles, dt: dt, drag: 3.0)

        // A missed pair flips back on its own once the study beat passes.
        var flippedBack = false
        for i in cards.indices where cards[i].faceUp && !cards[i].matched
            && cards[i].missAt >= 0 && time - cards[i].missAt > Self.studyBeat {
            cards[i].faceUp = false
            cards[i].flipAt = time
            cards[i].missAt = -10
            flippedBack = true
        }
        if flippedBack { Haptics.play(.click, minInterval: 0) }
    }

    // MARK: Input

    func tap(_ i: Int) {
        guard !finished, cards.indices.contains(i) else { return }
        guard !cards[i].matched, !cards[i].faceUp else { return }
        // A missed pair is still up for study — wait for the flip-back.
        guard faceUpUnmatched < 2 else { return }

        cards[i].faceUp = true
        cards[i].flipAt = time
        Haptics.play(.click, minInterval: 0)

        guard let first = firstPick else {
            firstPick = i
            return
        }
        firstPick = nil
        moves += 1
        if cards[first].glyph == cards[i].glyph {
            cards[first].matched = true
            cards[i].matched = true
            cards[first].matchedAt = time
            cards[i].matchedAt = time
            sparkle(at: first)
            sparkle(at: i)
            if cards.allSatisfy(\.matched) {
                finished = true
                Haptics.celebrate()
                notifyMainAsync(onComplete, moves)
            } else {
                Haptics.play(.success, minInterval: 0)
            }
        } else {
            cards[first].missAt = time
            cards[i].missAt = time
        }
    }

    func reset() {
        deal()
        moves = 0
        particles.removeAll()
        firstPick = nil
        finished = false
        dealAt = time
    }

    // MARK: Particles

    private func sparkle(at i: Int) {
        let rect = PairsRenderer.cardRect(i, size: boardSize)
        spawnRadialBurst(into: &particles, at: Vec2(rect.midX, rect.midY),
                         count: 10, speed: 40...100, life: 0.35...0.6,
                         size: 1.6...2.8) { $0 % 3 == 2 ? .white : .gold }
    }
}

// MARK: - View

struct PairsView: View {
    @Environment(ScoreStore.self) private var store

    @State private var engine = PairsEngine()
    @State private var finalMoves: Int? = nil
    @State private var wasBest = false
    /// Board cleared and every send-off effect has played out — freezes the
    /// render clock behind the result card.
    @State private var settled = false

    var body: some View {
        ArcadeScreen(extraPaused: settled) { size, date in
            canvasView(size: size, date: date)
        } overlay: {
            if let moves = finalMoves {
                ResultCard(title: "\(moves) Moves",
                           subtitle: wasBest ? "New Best"
                               : (store.arcadeBest("pairs") > 0
                                   ? "Best \(store.arcadeBest("pairs"))" : " "),
                           titleGold: true,
                           subtitleGold: wasBest) {
                    settled = false
                    engine.reset()
                    withAnimation { finalMoves = nil }
                }
            }
        }
        .onAppear {
            engine.onComplete = { moves in
                wasBest = store.recordArcadeBestLow("pairs", moves)
                // Let the last match pop land before the card slides in.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.arcadePop) { finalMoves = moves }
                }
                // Freeze once every effect has faded; a replay within the
                // window clears the card and voids the stale timer.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if finalMoves != nil { settled = true }
                }
            }
        }
    }

    private func canvasView(size: CGSize, date: Date) -> some View {
        engine.boardSize = size
        engine.step(to: date)
        let renderer = PairsRenderer(engine: engine, size: size, time: engine.time)
        return Canvas { ctx, _ in
            renderer.draw(into: ctx)
        }
        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
            if let i = PairsRenderer.cardIndex(at: value.location, size: size) {
                engine.tap(i)
            }
        })
    }
}

// MARK: - Renderer

struct PairsRenderer {
    let engine: PairsEngine
    let size: CGSize
    let time: Double

    /// 4×4 grid between the clock and the move counter; the row height sets
    /// the pace and the width follows so cards stay a touch taller than wide.
    static func cardRect(_ i: Int, size: CGSize) -> CGRect {
        let gap = 6.0
        let top = 64.0
        let bottom = size.height - 26
        let cardH = (bottom - top - gap * 3) / 4
        let cardW = min((size.width - 20 - gap * 3) / 4, cardH * 0.92)
        let x0 = (size.width - (cardW * 4 + gap * 3)) / 2
        let col = Double(i % 4), row = Double(i / 4)
        return CGRect(x: x0 + col * (cardW + gap), y: top + row * (cardH + gap),
                      width: cardW, height: cardH)
    }

    static func cardIndex(at p: CGPoint, size: CGSize) -> Int? {
        for i in 0..<16 where cardRect(i, size: size).insetBy(dx: -3, dy: -3).contains(p) {
            return i
        }
        return nil
    }

    func draw(into ctx: GraphicsContext) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.bg))
        drawWallpaperDots(ctx, size: size)
        drawMoves(ctx)
        for i in engine.cards.indices { drawCard(ctx, i) }
        drawArcadeParticles(ctx, engine.particles)
        drawClockScrim(ctx, size: size)
    }

    /// Ghost move counter tucked in the bottom-right corner.
    private func drawMoves(_ ctx: GraphicsContext) {
        guard engine.moves > 0 else { return }
        ctx.draw(Text("\(engine.moves)")
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .foregroundStyle(Palette.ink.opacity(0.16)),
                 at: CGPoint(x: size.width - 24, y: size.height - 13))
    }

    // MARK: Cards

    private func drawCard(_ base: GraphicsContext, _ i: Int) {
        let card = engine.cards[i]
        let rect = Self.cardRect(i, size: size)
        let c = CGPoint(x: rect.midX, y: rect.midY)

        // Deal-in: each card springs up from nothing, staggered across the
        // board.
        let dealT = (time - engine.dealAt - Double(i) * 0.03) / 0.3
        guard dealT > 0 else { return }
        var scale = dealT < 1 ? easeOutBack(dealT) : 1.0

        // Matched cards pop once, then rest slightly small so the live
        // board stays the loud part.
        if card.matched {
            let pop = decay(card.matchedAt, 0.35, now: time)
            scale *= 0.96 + 0.2 * (1 - easeOutBack(1 - pop))
        }

        // Flip: a horizontal squash through zero — old side shrinks away,
        // new side springs back out with a pop.
        let progress = min((time - card.flipAt) / 0.22, 1)
        let firstHalf = progress < 0.5
        let sx: Double
        if progress >= 1 {
            sx = 1
        } else if firstHalf {
            sx = abs(cos(progress * .pi))
        } else {
            sx = abs(cos((0.5 + 0.5 * easeOutBack((progress - 0.5) * 2)) * .pi))
        }
        let showFace = card.faceUp != firstHalf

        var g = base
        g.translateBy(x: c.x, y: c.y)
        let wig = decay(card.missAt, 0.4, now: time)
        if wig > 0 {
            g.rotate(by: Angle(radians: sin(time * 40) * 0.06 * wig))
        }
        g.scaleBy(x: sx * scale, y: scale)
        g.translateBy(x: -c.x, y: -c.y)

        let shape = Path(roundedRect: rect, cornerRadius: 9)
        var sh = g
        sh.translateBy(x: 1.2, y: 2)
        sh.addFilter(.blur(radius: 2))
        sh.fill(shape, with: .color(Palette.shadow))

        if showFace {
            g.fill(shape, with: .color(.white.opacity(0.95)))
            g.stroke(shape,
                     with: .color(card.matched ? Palette.ink.opacity(0.55) : Palette.ink),
                     style: StrokeStyle(lineWidth: 1.5))
            Self.drawGlyph(g, card.glyph, at: c, r: rect.width * 0.22)
        } else {
            g.fill(shape, with: .color(Palette.wallTop))
            g.stroke(shape, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.5))
            // The app's wallpaper dots in miniature, inside a darker ring.
            g.stroke(Path(roundedRect: rect.insetBy(dx: 4, dy: 4), cornerRadius: 6),
                     with: .color(Palette.sandDark.opacity(0.5)),
                     style: StrokeStyle(lineWidth: 1.2))
            var dots = Path()
            for row in 0..<4 {
                let shift = row % 2 == 0 ? 0.0 : 0.5
                for col in 0..<3 {
                    let x = rect.midX + (Double(col) - 1 + shift * 0.5) * rect.width * 0.2
                    let y = rect.midY + (Double(row) - 1.5) * rect.height * 0.18
                    dots.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9,
                                               width: 1.8, height: 1.8))
                }
            }
            g.fill(dots, with: .color(Palette.ink.opacity(0.10)))
        }
    }

    // MARK: Glyphs

    /// Chunky inked mini-icons, one per pair. Shared with the home vignette.
    static func drawGlyph(_ g: GraphicsContext, _ glyph: PairsEngine.Glyph,
                          at p: CGPoint, r: Double) {
        switch glyph {
        case .apple:
            arcadeInkedEllipse(g, at: p, rx: r, ry: r * 0.94,
                               fill: Palette.bumperCoral, ink: 1.4)
            var stem = Path()
            stem.move(to: CGPoint(x: p.x, y: p.y - r * 0.85))
            stem.addLine(to: CGPoint(x: p.x + r * 0.12, y: p.y - r * 1.25))
            g.stroke(stem, with: .color(Palette.ink),
                     style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            let leaf = arcadeEllipse(at: CGPoint(x: p.x + r * 0.5, y: p.y - r * 1.15),
                                     rx: r * 0.38, ry: r * 0.2)
            g.fill(leaf, with: .color(Palette.treeGreen))
            g.stroke(leaf, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.1))
            g.fill(arcadeEllipse(at: CGPoint(x: p.x - r * 0.32, y: p.y - r * 0.3),
                                 rx: r * 0.26, ry: r * 0.2),
                   with: .color(.white.opacity(0.55)))
        case .flag:
            var pole = Path()
            pole.move(to: CGPoint(x: p.x - r * 0.5, y: p.y + r * 1.1))
            pole.addLine(to: CGPoint(x: p.x - r * 0.5, y: p.y - r * 1.1))
            g.stroke(pole, with: .color(Palette.ink),
                     style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            var pennant = Path()
            pennant.move(to: CGPoint(x: p.x - r * 0.5, y: p.y - r * 1.1))
            pennant.addLine(to: CGPoint(x: p.x + r, y: p.y - r * 0.6))
            pennant.addLine(to: CGPoint(x: p.x - r * 0.5, y: p.y - r * 0.1))
            pennant.closeSubpath()
            g.fill(pennant, with: .color(Palette.gold))
            g.stroke(pennant, with: .color(Palette.ink),
                     style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        case .heart:
            let s = r * 1.05
            let heart = heartPath(at: p, s: s)
            g.fill(heart, with: .color(Palette.bumperCoral))
            g.stroke(heart, with: .color(Palette.ink),
                     style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            g.fill(arcadeEllipse(at: CGPoint(x: p.x - s * 0.33, y: p.y - s * 0.3),
                                 rx: s * 0.16, ry: s * 0.16),
                   with: .color(.white.opacity(0.7)))
        case .bolt:
            var bolt = Path()
            bolt.move(to: CGPoint(x: p.x + r * 0.45, y: p.y - r * 1.1))
            bolt.addLine(to: CGPoint(x: p.x - r * 0.55, y: p.y + r * 0.25))
            bolt.addLine(to: CGPoint(x: p.x - r * 0.05, y: p.y + r * 0.25))
            bolt.addLine(to: CGPoint(x: p.x - r * 0.45, y: p.y + r * 1.1))
            bolt.addLine(to: CGPoint(x: p.x + r * 0.55, y: p.y - r * 0.25))
            bolt.addLine(to: CGPoint(x: p.x + r * 0.05, y: p.y - r * 0.25))
            bolt.closeSubpath()
            g.fill(bolt, with: .color(Palette.gold))
            g.stroke(bolt, with: .color(Palette.ink),
                     style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        case .coin:
            arcadeInkedEllipse(g, at: p, rx: r, ry: r, fill: Palette.gold, ink: 1.4)
            g.stroke(arcadeEllipse(at: p, rx: r * 0.62, ry: r * 0.62),
                     with: .color(Palette.goldDeep),
                     style: StrokeStyle(lineWidth: 1.4))
            g.fill(arcadeEllipse(at: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.38),
                                 rx: r * 0.22, ry: r * 0.15),
                   with: .color(.white.opacity(0.8)))
        case .leaf:
            var lg = g
            lg.translateBy(x: p.x, y: p.y)
            lg.rotate(by: Angle(radians: -0.5))
            lg.translateBy(x: -p.x, y: -p.y)
            arcadeInkedEllipse(lg, at: p, rx: r * 1.05, ry: r * 0.6,
                               fill: Palette.treeGreen, ink: 1.4)
            var vein = Path()
            vein.move(to: CGPoint(x: p.x - r * 0.8, y: p.y))
            vein.addLine(to: CGPoint(x: p.x + r * 0.8, y: p.y))
            lg.stroke(vein, with: .color(Palette.ink),
                      style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        case .star:
            var star = Path()
            for k in 0..<10 {
                let a = -Double.pi / 2 + Double(k) * .pi / 5
                let rad = k % 2 == 0 ? r * 1.15 : r * 0.55
                let pt = CGPoint(x: p.x + cos(a) * rad, y: p.y + sin(a) * rad)
                if k == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
            }
            star.closeSubpath()
            g.fill(star, with: .color(Palette.gold))
            g.stroke(star, with: .color(Palette.ink),
                     style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        case .ball:
            arcadeInkedEllipse(g, at: p, rx: r, ry: r, fill: .white, ink: 1.4)
            for (dx, dy) in [(-0.35, -0.12), (0.28, -0.3), (0.0, 0.32)] {
                var dimple = Path()
                dimple.addArc(center: CGPoint(x: p.x + dx * r, y: p.y + dy * r),
                              radius: r * 0.18, startAngle: .degrees(20),
                              endAngle: .degrees(160), clockwise: false)
                g.stroke(dimple, with: .color(Palette.shadow),
                         style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
        }
    }

    /// Fat cartoon heart centered on `c`; `s` is its half-width.
    static func heartPath(at c: CGPoint, s: Double) -> Path {
        var heart = Path()
        heart.move(to: CGPoint(x: c.x, y: c.y + s))
        heart.addCurve(to: CGPoint(x: c.x - s, y: c.y - s * 0.25),
                       control1: CGPoint(x: c.x - s * 0.6, y: c.y + s * 0.5),
                       control2: CGPoint(x: c.x - s, y: c.y + s * 0.15))
        heart.addCurve(to: CGPoint(x: c.x, y: c.y - s * 0.45),
                       control1: CGPoint(x: c.x - s, y: c.y - s * 0.85),
                       control2: CGPoint(x: c.x - s * 0.35, y: c.y - s * 0.9))
        heart.addCurve(to: CGPoint(x: c.x + s, y: c.y - s * 0.25),
                       control1: CGPoint(x: c.x + s * 0.35, y: c.y - s * 0.9),
                       control2: CGPoint(x: c.x + s, y: c.y - s * 0.85))
        heart.addCurve(to: CGPoint(x: c.x, y: c.y + s),
                       control1: CGPoint(x: c.x + s, y: c.y + s * 0.15),
                       control2: CGPoint(x: c.x + s * 0.6, y: c.y + s * 0.5))
        heart.closeSubpath()
        return heart
    }
}
