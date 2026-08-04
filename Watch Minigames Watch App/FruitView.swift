//
//  FruitView.swift
//  Minigames Watch App
//
//  Fruit Drop: slide the basket with a drag or the crown and catch the
//  falling fruit. Bombs go bang, dropped fruit costs a heart.
//

import SwiftUI

// MARK: - Engine

final class FruitEngine {

    enum Kind: Int, CaseIterable { case apple, orange, plum, bomb }

    struct Item {
        var kind: Kind
        var pos: Vec2
        var vy: Double
        var rot: Double
        var spin: Double
        var seed: Double
    }

    static let basketHalf = 21.0
    static let itemR = 8.0

    var courtW = 180.0
    var courtH = 220.0
    var basketX = 90.0
    var basketTarget = 90.0
    var basketVX = 0.0
    var items: [Item] = []
    var score = 0
    var hearts = 3
    var time = 0.0
    var shakeAmp = 0.0
    var done = false
    var particles: [Particle] = []
    var floaters: [Floater] = []
    var lastCatchAt = -10.0
    var lastOuchAt = -10.0
    var onGameOver: ((Int) -> Void)?

    private var lastDate: Date?
    private var nextSpawnAt = 0.7

    var rimY: Double { courtH - 30 }

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
        guard !done else { return }

        // Basket chase; velocity kept for a cartoon tilt in the renderer.
        let before = basketX
        basketX += (basketTarget - basketX) * min(1, dt * 20)
        let half = Self.basketHalf
        basketX = min(max(basketX, half + 4), courtW - half - 4)
        basketVX = dt > 0 ? (basketX - before) / dt : 0

        // Spawn, quickening with the score.
        if time >= nextSpawnAt {
            let pace = min(Double(score) / 40.0, 1)
            nextSpawnAt = time + Double.random(in: 0.55...0.95) * (1 - pace * 0.5)
            let bombChance = 0.14 + pace * 0.14
            let kind: Kind
            if Double.random(in: 0..<1) < bombChance {
                kind = .bomb
            } else {
                kind = [Kind.apple, .orange, .plum].randomElement()!
            }
            items.append(Item(kind: kind,
                              pos: Vec2(Double.random(in: 18...(courtW - 18)), -14),
                              vy: (66 + pace * 74) * Double.random(in: 0.85...1.15),
                              rot: Double.random(in: -0.4...0.4),
                              spin: Double.random(in: -1.6...1.6),
                              seed: Double.random(in: 0..<1)))
        }

        // Fall & resolve.
        var kept: [Item] = []
        for var item in items {
            let wasAbove = item.pos.y < rimY
            item.pos.y += item.vy * dt
            item.rot += item.spin * dt
            if wasAbove, item.pos.y >= rimY {
                if abs(item.pos.x - basketX) <= Self.basketHalf + 3 {
                    caught(item)
                    continue
                }
            }
            if item.pos.y > courtH + 20 {
                missed(item)
                continue
            }
            kept.append(item)
        }
        items = kept
    }

    private func caught(_ item: Item) {
        if item.kind == .bomb {
            loseHeart(at: Vec2(item.pos.x, rimY - 10), boom: true)
            return
        }
        score += 1
        lastCatchAt = time
        spawnJuice(at: Vec2(item.pos.x, rimY - 6), kind: item.kind)
        floaters.append(Floater(pos: Vec2(item.pos.x, rimY - 18), text: "+1",
                                bornAt: time, color: Palette.ink))
        Haptics.play(.click, minInterval: 0)
    }

    private func missed(_ item: Item) {
        // A bomb sailing past is a mercy, not a miss.
        guard item.kind != .bomb else { return }
        loseHeart(at: Vec2(item.pos.x, courtH - 12), boom: false)
    }

    private func loseHeart(at p: Vec2, boom: Bool) {
        hearts -= 1
        lastOuchAt = time
        shakeAmp = boom ? 5 : 3
        if boom { spawnBoom(at: p) }
        Haptics.play(.failure, minInterval: 0)
        if hearts <= 0 {
            done = true
            items.removeAll()
            let final = score
            let cb = onGameOver
            DispatchQueue.main.async { cb?(final) }
        }
    }

    func reset() {
        items.removeAll()
        particles.removeAll()
        floaters.removeAll()
        score = 0
        hearts = 3
        shakeAmp = 0
        done = false
        nextSpawnAt = time + 0.7
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

    private func spawnJuice(at p: Vec2, kind: Kind) {
        // Confetti hues that read as juice for each fruit.
        let hueIndex: Int
        switch kind {
        case .apple: hueIndex = 1
        case .orange: hueIndex = 0
        case .plum: hueIndex = 3
        case .bomb: hueIndex = 5
        }
        for _ in 0..<7 {
            let a = Double.random(in: (-2.6)...(-0.5))
            let life = Double.random(in: 0.3...0.5)
            particles.append(Particle(
                pos: p, vel: Vec2(cos(a), sin(a)) * Double.random(in: 40...90),
                life: life, maxLife: life,
                size: Double.random(in: 1.5...2.6), hue: .confetti(hueIndex)))
        }
    }

    private func spawnBoom(at p: Vec2) {
        for k in 0..<12 {
            let a = Double.random(in: 0..<(2 * .pi))
            let life = Double.random(in: 0.35...0.6)
            particles.append(Particle(
                pos: p, vel: Vec2(cos(a), sin(a)) * Double.random(in: 60...130),
                life: life, maxLife: life,
                size: Double.random(in: 1.8...3.2),
                hue: k % 3 == 0 ? .gold : .shard))
        }
    }
}

// MARK: - View

struct FruitView: View {
    @Environment(ScoreStore.self) private var store

    @State private var engine = FruitEngine()
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
                    ResultCard(title: "Caught \(score)",
                               subtitle: wasBest && score > 0
                                   ? "New Best" : "Best \(store.arcadeBest("fruit"))",
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
            engine.basketTarget = newValue * engine.courtW
        }
        .onAppear {
            engine.onGameOver = { score in
                wasBest = store.recordArcadeBest("fruit", score)
                withAnimation(.easeOut(duration: 0.3)) { finalScore = score }
            }
        }
    }

    private func canvasView(size: CGSize, date: Date) -> some View {
        engine.courtW = size.width
        engine.courtH = size.height
        engine.step(to: date)
        let renderer = FruitRenderer(engine: engine, size: size, time: engine.time)
        return Canvas { ctx, _ in
            renderer.draw(into: ctx)
        }
        .gesture(basketDrag)
    }

    private var basketDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartX == nil { dragStartX = engine.basketTarget }
                let target = (dragStartX ?? 0) + Double(value.translation.width) * 1.3
                engine.basketTarget = min(max(target, 0), engine.courtW)
                crown = engine.basketTarget / max(engine.courtW, 1)
            }
            .onEnded { _ in dragStartX = nil }
    }
}

// MARK: - Renderer

struct FruitRenderer {
    let engine: FruitEngine
    let size: CGSize
    let time: Double

    static let plumPurple = Color(red: 0.63, green: 0.53, blue: 0.79)
    static let plumDeep = Color(red: 0.48, green: 0.39, blue: 0.63)

    func draw(into base: GraphicsContext) {
        var ctx = base
        if engine.shakeAmp > 0.15 {
            ctx.translateBy(x: sin(time * 67) * engine.shakeAmp,
                            y: cos(time * 53) * engine.shakeAmp * 0.6)
        }

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.bg))
        drawWallpaperDots(ctx, size: size)

        // Grass shelf the basket slides along.
        let groundY = size.height - 14
        ctx.fill(Path(CGRect(x: 0, y: groundY, width: size.width, height: 16)),
                 with: .color(Palette.fairway))
        ctx.stroke(Path(CGRect(x: -2, y: groundY, width: size.width + 4, height: 3)),
                   with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.4))

        drawClockScrim(ctx, size: size)
        drawHUD(ctx)

        for item in engine.items { drawItem(ctx, item) }
        drawBasket(ctx)
        drawArcadeParticles(ctx, engine.particles)
        drawFloaters(ctx, engine.floaters, time: time)
        drawOuchVignette(ctx)
    }

    // MARK: HUD

    private func drawHUD(_ ctx: GraphicsContext) {
        let flash = max(0, 1 - (time - engine.lastCatchAt) / 0.4)
        ctx.draw(Text("\(engine.score)")
            .font(.system(size: 40 * (1 + flash * 0.2), weight: .heavy, design: .rounded))
            .foregroundStyle(Palette.boostBlueDeep.opacity(0.35 + flash * 0.4)),
                 at: CGPoint(x: size.width - 30, y: 62))
        for i in 0..<3 {
            let filled = i < engine.hearts
            let ouch = max(0, 1 - (time - engine.lastOuchAt) / 0.4)
            let wobble = i == engine.hearts && ouch > 0 ? sin(time * 40) * 2 * ouch : 0
            ctx.draw(Text(Image(systemName: filled ? "heart.fill" : "heart"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(filled ? Palette.bumperCoral : Palette.ink.opacity(0.25)),
                     at: CGPoint(x: 16 + Double(i) * 14 + wobble, y: 58))
        }
    }

    /// Coral flash creeping in from the edges when a heart is lost.
    private func drawOuchVignette(_ ctx: GraphicsContext) {
        let ouch = max(0, 1 - (time - engine.lastOuchAt) / 0.45)
        guard ouch > 0 else { return }
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(colors: [.clear, Palette.bumperCoral.opacity(0.4 * ouch)]),
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            startRadius: size.width * 0.4, endRadius: size.height * 0.75))
    }

    // MARK: Items

    private func drawItem(_ ctx: GraphicsContext, _ item: FruitEngine.Item) {
        let c = item.pos.cg
        let r = FruitEngine.itemR

        // Speed streak behind fast fruit.
        if item.vy > 110 {
            var streak = Path()
            streak.move(to: CGPoint(x: c.x, y: c.y - r - 3))
            streak.addLine(to: CGPoint(x: c.x, y: c.y - r - 3 - (item.vy - 100) * 0.09))
            ctx.stroke(streak, with: .color(.white.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }

        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: Angle(radians: item.rot))
        g.translateBy(x: -c.x, y: -c.y)

        switch item.kind {
        case .apple:
            arcadeInkedEllipse(g, at: c, rx: r, ry: r * 0.94, fill: Palette.bumperCoral)
            stemAndLeaf(g, at: c, r: r)
            g.fill(arcadeEllipse(at: CGPoint(x: c.x - r * 0.32, y: c.y - r * 0.3),
                                 rx: r * 0.26, ry: r * 0.2),
                   with: .color(.white.opacity(0.55)))
        case .orange:
            arcadeInkedEllipse(g, at: c, rx: r, ry: r, fill: Palette.gold)
            // Peel dimples.
            for k in 0..<4 {
                let a = item.seed * 9 + Double(k) * 1.7
                g.fill(arcadeEllipse(at: CGPoint(x: c.x + cos(a) * r * 0.45,
                                                 y: c.y + sin(a) * r * 0.45),
                                     rx: 0.7, ry: 0.7),
                       with: .color(Palette.goldDeep.opacity(0.7)))
            }
            stemAndLeaf(g, at: c, r: r)
            g.fill(arcadeEllipse(at: CGPoint(x: c.x - r * 0.32, y: c.y - r * 0.3),
                                 rx: r * 0.24, ry: r * 0.18),
                   with: .color(.white.opacity(0.5)))
        case .plum:
            arcadeInkedEllipse(g, at: c, rx: r * 0.88, ry: r * 0.95, fill: Self.plumPurple)
            var crease = Path()
            crease.move(to: CGPoint(x: c.x, y: c.y - r * 0.8))
            crease.addQuadCurve(to: CGPoint(x: c.x + r * 0.15, y: c.y + r * 0.5),
                                control: CGPoint(x: c.x + r * 0.4, y: c.y - r * 0.1))
            g.stroke(crease, with: .color(Self.plumDeep), style: StrokeStyle(lineWidth: 1.2))
            stemAndLeaf(g, at: c, r: r * 0.9)
            g.fill(arcadeEllipse(at: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3),
                                 rx: r * 0.22, ry: r * 0.17),
                   with: .color(.white.opacity(0.5)))
        case .bomb:
            arcadeInkedEllipse(g, at: c, rx: r * 0.95, ry: r * 0.95,
                               fill: Color(red: 0.30, green: 0.30, blue: 0.28))
            var fuse = Path()
            fuse.move(to: CGPoint(x: c.x, y: c.y - r * 0.9))
            fuse.addQuadCurve(to: CGPoint(x: c.x + r * 0.7, y: c.y - r * 1.5),
                              control: CGPoint(x: c.x + r * 0.1, y: c.y - r * 1.55))
            g.stroke(fuse, with: .color(Palette.ink),
                     style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let spark = 1 + 0.5 * sin(time * 16 + item.seed * 9)
            g.fill(arcadeEllipse(at: CGPoint(x: c.x + r * 0.75, y: c.y - r * 1.55),
                                 rx: 2.2 * spark, ry: 2.2 * spark),
                   with: .color(Palette.gold))
            g.fill(arcadeEllipse(at: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.32),
                                 rx: r * 0.24, ry: r * 0.18),
                   with: .color(.white.opacity(0.35)))
        }
    }

    private func stemAndLeaf(_ ctx: GraphicsContext, at c: CGPoint, r: Double) {
        var stem = Path()
        stem.move(to: CGPoint(x: c.x, y: c.y - r * 0.85))
        stem.addLine(to: CGPoint(x: c.x + r * 0.12, y: c.y - r * 1.25))
        ctx.stroke(stem, with: .color(Palette.ink),
                   style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        let leaf = arcadeEllipse(at: CGPoint(x: c.x + r * 0.5, y: c.y - r * 1.15),
                                 rx: r * 0.38, ry: r * 0.2)
        ctx.fill(leaf, with: .color(Palette.treeGreen))
        ctx.stroke(leaf, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.1))
    }

    // MARK: Basket

    private func drawBasket(_ ctx: GraphicsContext) {
        let cx = engine.basketX
        let rimY = engine.rimY
        let squash = max(0, 1 - (time - engine.lastCatchAt) / 0.16) * 0.12
        let tilt = min(max(engine.basketVX * 0.0009, -0.12), 0.12)

        var g = ctx
        g.translateBy(x: cx, y: rimY + 9)
        g.rotate(by: Angle(radians: tilt))
        g.scaleBy(x: 1 + squash, y: 1 - squash)
        g.translateBy(x: -cx, y: -(rimY + 9))

        let topHalf = FruitEngine.basketHalf, botHalf = topHalf - 6.0
        let h = 18.0
        var body = Path()
        body.move(to: CGPoint(x: cx - topHalf, y: rimY))
        body.addLine(to: CGPoint(x: cx + topHalf, y: rimY))
        body.addLine(to: CGPoint(x: cx + botHalf, y: rimY + h))
        body.addQuadCurve(to: CGPoint(x: cx - botHalf, y: rimY + h),
                          control: CGPoint(x: cx, y: rimY + h + 4))
        body.closeSubpath()

        var sh = g
        sh.translateBy(x: 1.5, y: 2.5)
        sh.addFilter(.blur(radius: 2))
        sh.fill(body, with: .color(Palette.shadow))

        g.fill(body, with: .color(Palette.sand))
        // Weave: two sagging lines across the body.
        var weave = Path()
        for f in [0.35, 0.68] {
            let y = rimY + h * f
            let inset = 6.0 * f
            weave.move(to: CGPoint(x: cx - topHalf + inset, y: y))
            weave.addQuadCurve(to: CGPoint(x: cx + topHalf - inset, y: y),
                               control: CGPoint(x: cx, y: y + 3))
        }
        g.stroke(weave, with: .color(Palette.sandDark),
                 style: StrokeStyle(lineWidth: 1.3))
        g.stroke(body, with: .color(Palette.ink),
                 style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

        // Rim band on top.
        let rim = Path(roundedRect: CGRect(x: cx - topHalf - 1.5, y: rimY - 3,
                                           width: (topHalf + 1.5) * 2, height: 6),
                       cornerRadius: 3)
        g.fill(rim, with: .color(Palette.sandDark))
        g.stroke(rim, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.4))
    }
}

// MARK: - Home page

struct FruitHome: View {
    var body: some View {
        GameHome(title: "Fruit Drop") { t in
            FruitScene(t: t)
        } destination: {
            FruitView()
        }
    }
}

/// Little vignette: fruit drops onto two lanes and the basket glides
/// smoothly from one catch to the next — arriving just in time, every time.
private struct FruitScene: View {
    let t: Double

    private static let loopT = 3.2

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let rimY = size.height - 20
            let xA = cx - 31, xB = cx + 33
            let u = (t / Self.loopT).truncatingRemainder(dividingBy: 1)

            func smooth(_ x: Double) -> Double {
                let v = min(max(x, 0), 1)
                return v * v * (3 - 2 * v)
            }

            // Catches land at u = 0.45 (lane A) and 0.95 (lane B); between
            // them the basket eases across, easing out as it arrives early.
            let basketX: Double
            let glide: Double        // 0…1 progress of the current slide
            if u < 0.45 {
                glide = smooth(u / 0.34)
                basketX = xB + (xA - xB) * glide
            } else {
                glide = smooth((u - 0.5) / 0.34)
                basketX = xA + (xB - xA) * glide
            }
            // Lean into the direction of travel while moving.
            let dir: Double = u < 0.45 ? -1 : 1
            let tilt = dir * sin(glide * .pi) * 0.09

            // --- Falling fruit ---
            func fruit(_ x: Double, start: Double, catchAt: Double,
                       fill: Color, phase: Double) {
                guard u >= start, u < catchAt else { return }
                let f = (u - start) / (catchAt - start)
                // Slight ease-in: the drop picks up speed like real gravity.
                let y = -10 + (rimY - 6 + 10) * f * f * (2 - f)
                let c = CGPoint(x: x, y: y)
                let rot = sin((t + phase) * 2.6) * 0.14
                var g = ctx
                g.translateBy(x: c.x, y: c.y)
                g.rotate(by: Angle(radians: rot))
                g.translateBy(x: -c.x, y: -c.y)
                arcadeInkedEllipse(g, at: c, rx: 6.5, ry: 6.2, fill: fill, ink: 1.4)
                var stem = Path()
                stem.move(to: CGPoint(x: c.x, y: c.y - 5.5))
                stem.addLine(to: CGPoint(x: c.x + 0.8, y: c.y - 8.5))
                g.stroke(stem, with: .color(Palette.ink),
                         style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                let leaf = arcadeEllipse(at: CGPoint(x: c.x + 3.4, y: c.y - 7.6),
                                         rx: 2.6, ry: 1.5)
                g.fill(leaf, with: .color(Palette.treeGreen))
                g.stroke(leaf, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1))
                g.fill(arcadeEllipse(at: CGPoint(x: c.x - 2, y: c.y - 2), rx: 1.7, ry: 1.3),
                       with: .color(.white.opacity(0.55)))
            }
            fruit(xA, start: 0.03, catchAt: 0.45, fill: Palette.bumperCoral, phase: 0)
            fruit(xB, start: 0.53, catchAt: 0.95, fill: Palette.gold, phase: 1.3)

            // --- Catch sparkles, blooming right out of the rim ---
            func sparkle(_ x: Double, at catchAt: Double) {
                let dt = u - catchAt
                let e = dt >= 0 ? dt / 0.14 : (dt + 1) / 0.14   // wraps for u≈0
                guard e >= 0, e < 1 else { return }
                for k in 0..<6 {
                    let a = Double(k) / 6 * .pi + 0.25   // upper fan only
                    let p = CGPoint(x: x + cos(a) * 13 * e * (k % 2 == 0 ? 1 : 0.7),
                                    y: rimY - 5 - sin(a) * 11 * e)
                    let sz = 1.9 * (1 - e)
                    ctx.fill(arcadeEllipse(at: p, rx: sz, ry: sz),
                             with: .color((k % 2 == 0 ? Palette.gold : .white)
                                 .opacity(1 - e)))
                }
            }
            sparkle(xA, at: 0.45)
            sparkle(xB, at: 0.95)

            // --- Basket, squashing on each catch ---
            let sq1 = max(0, 1 - abs(u - 0.45) / 0.07)
            let sq2 = max(0, 1 - min(abs(u - 0.95), abs(u + 0.05)) / 0.07)
            let squash = max(sq1, sq2) * 0.1

            var g = ctx
            g.translateBy(x: basketX, y: rimY + 7)
            g.rotate(by: Angle(radians: tilt))
            g.scaleBy(x: 1 + squash, y: 1 - squash)
            g.translateBy(x: -basketX, y: -(rimY + 7))

            var body = Path()
            body.move(to: CGPoint(x: basketX - 17, y: rimY))
            body.addLine(to: CGPoint(x: basketX + 17, y: rimY))
            body.addLine(to: CGPoint(x: basketX + 12, y: rimY + 13))
            body.addQuadCurve(to: CGPoint(x: basketX - 12, y: rimY + 13),
                              control: CGPoint(x: basketX, y: rimY + 16))
            body.closeSubpath()
            var sh = g
            sh.translateBy(x: 1.5, y: 2)
            sh.addFilter(.blur(radius: 2))
            sh.fill(body, with: .color(Palette.shadow))
            g.fill(body, with: .color(Palette.sand))
            var weave = Path()
            weave.move(to: CGPoint(x: basketX - 15, y: rimY + 5))
            weave.addQuadCurve(to: CGPoint(x: basketX + 15, y: rimY + 5),
                               control: CGPoint(x: basketX, y: rimY + 7.5))
            g.stroke(weave, with: .color(Palette.sandDark), style: StrokeStyle(lineWidth: 1.2))
            g.stroke(body, with: .color(Palette.ink),
                     style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            let rim = Path(roundedRect: CGRect(x: basketX - 18.5, y: rimY - 2.5,
                                               width: 37, height: 5), cornerRadius: 2.5)
            g.fill(rim, with: .color(Palette.sandDark))
            g.stroke(rim, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.3))
        }
    }
}
