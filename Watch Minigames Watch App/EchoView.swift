//
//  EchoView.swift
//  Minigames Watch App
//
//  Echo: watch the four pads sing a pattern, then tap it back. One more
//  note every round until you slip.
//

import SwiftUI

// MARK: - Engine

final class EchoEngine {

    enum Phase {
        /// Pause before the sequence replays.
        case breathe(until: Double)
        /// Pads light one by one; `step` indexes into the sequence.
        case showing(step: Int, since: Double)
        /// Player's turn; `progress` notes already matched.
        case listening(progress: Int)
        case done
    }

    static let showBeat = 0.52
    static let litFor = 0.34

    var phase: Phase = .breathe(until: 0.8)
    var sequence: [Int] = []
    var score = 0
    var time = 0.0
    var shakeAmp = 0.0
    var particles: [Particle] = []
    /// Player-triggered pad flashes, latest tap per pad.
    var tapFlash: [Double] = [-10, -10, -10, -10]
    /// The pad that broke the run, flashed coral on the way out.
    var wrongPad: Int? = nil
    var lastRoundAt = -10.0
    var onGameOver: ((Int) -> Void)?

    private var lastDate: Date?

    init() {
        sequence = [Int.random(in: 0..<4)]
    }

    /// Pad currently lit by the machine, if any.
    var showingPad: Int? {
        if case .showing(let step, let since) = phase,
           time - since < Self.litFor, step < sequence.count {
            return sequence[step]
        }
        return nil
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
        updateParticles(dt)

        switch phase {
        case .breathe(let until):
            if time >= until {
                phase = .showing(step: 0, since: time)
                if let pad = showingPad { flashHaptic(pad) }
            }
        case .showing(let step, let since):
            if time - since >= Self.showBeat {
                if step + 1 < sequence.count {
                    phase = .showing(step: step + 1, since: time)
                    flashHaptic(sequence[step + 1])
                } else {
                    phase = .listening(progress: 0)
                }
            }
        case .listening, .done:
            break
        }
    }

    private func flashHaptic(_ pad: Int) {
        Haptics.play(.click, minInterval: 0)
    }

    // MARK: Input

    func tap(pad: Int) {
        guard case .listening(let progress) = phase else { return }
        tapFlash[pad] = time
        if sequence[progress] == pad {
            Haptics.play(.click, minInterval: 0)
            if progress + 1 == sequence.count {
                // Round complete: grow the song and replay after a breath.
                score += 1
                lastRoundAt = time
                sequence.append(Int.random(in: 0..<4))
                spawnRoundBurst()
                Haptics.play(.success, minInterval: 0)
                phase = .breathe(until: time + 0.9)
            } else {
                phase = .listening(progress: progress + 1)
            }
        } else {
            wrongPad = pad
            shakeAmp = 5
            phase = .done
            Haptics.play(.failure, minInterval: 0)
            let final = score
            let cb = onGameOver
            DispatchQueue.main.async { cb?(final) }
        }
    }

    func reset() {
        sequence = [Int.random(in: 0..<4)]
        score = 0
        shakeAmp = 0
        wrongPad = nil
        particles.removeAll()
        tapFlash = [-10, -10, -10, -10]
        phase = .breathe(until: time + 0.8)
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

    var burstCenter = Vec2(90, 110)

    private func spawnRoundBurst() {
        for k in 0..<12 {
            let a = Double(k) / 12 * 2 * .pi
            let life = Double.random(in: 0.35...0.6)
            particles.append(Particle(
                pos: burstCenter,
                vel: Vec2(cos(a), sin(a)) * Double.random(in: 40...100),
                life: life, maxLife: life,
                size: Double.random(in: 1.6...2.8), hue: .confetti(k)))
        }
    }
}

// MARK: - View

struct EchoView: View {
    @Environment(ScoreStore.self) private var store

    @State private var engine = EchoEngine()
    @State private var finalScore: Int? = nil
    @State private var wasBest = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation) { timeline in
                    canvasView(size: geo.size, date: timeline.date)
                }
                if let score = finalScore {
                    ResultCard(title: "\(score) Rounds",
                               subtitle: wasBest && score > 0
                                   ? "New Best" : "Best \(store.arcadeBest("echo"))",
                               titleGold: score > 0,
                               subtitleGold: wasBest && score > 0) {
                        engine.reset()
                        withAnimation { finalScore = nil }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            engine.onGameOver = { score in
                wasBest = store.recordArcadeBest("echo", score)
                // Let the wrong-pad flash land before the card slides in.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation(.easeOut(duration: 0.3)) { finalScore = score }
                }
            }
        }
    }

    private func canvasView(size: CGSize, date: Date) -> some View {
        engine.step(to: date)
        engine.burstCenter = Vec2(size.width / 2, size.height / 2 + 4)
        let renderer = EchoRenderer(engine: engine, size: size, time: engine.time)
        return Canvas { ctx, _ in
            renderer.draw(into: ctx)
        }
        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
            if let pad = EchoRenderer.padIndex(at: value.location, size: size) {
                engine.tap(pad: pad)
            }
        })
    }
}

// MARK: - Renderer

struct EchoRenderer {
    let engine: EchoEngine
    let size: CGSize
    let time: Double

    static let padColors: [(main: Color, deep: Color)] = [
        (Palette.bumperCoral, Color(red: 0.70, green: 0.34, blue: 0.27)),
        (Palette.boostBlue, Palette.boostBlueDeep),
        (Palette.gold, Palette.goldDeep),
        (Color(red: 0.38, green: 0.70, blue: 0.66), Color(red: 0.27, green: 0.54, blue: 0.50)),
    ]

    static func padRect(_ i: Int, size: CGSize) -> CGRect {
        let pad = min(58.0, (min(size.width, size.height) - 34) / 2)
        let gap = 9.0
        let cx = size.width / 2, cy = size.height / 2 + 4
        let col = Double(i % 2), row = Double(i / 2)
        return CGRect(x: cx - pad - gap / 2 + col * (pad + gap),
                      y: cy - pad - gap / 2 + row * (pad + gap),
                      width: pad, height: pad)
    }

    static func padIndex(at p: CGPoint, size: CGSize) -> Int? {
        for i in 0..<4 where padRect(i, size: size).insetBy(dx: -4, dy: -4).contains(p) {
            return i
        }
        return nil
    }

    func draw(into base: GraphicsContext) {
        var ctx = base
        if engine.shakeAmp > 0.15 {
            ctx.translateBy(x: sin(time * 67) * engine.shakeAmp,
                            y: cos(time * 53) * engine.shakeAmp * 0.6)
        }

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.bg))
        drawWallpaperDots(ctx, size: size)
        drawClockScrim(ctx, size: size)

        for i in 0..<4 { drawPad(ctx, i) }
        drawCenter(ctx)
        drawArcadeParticles(ctx, engine.particles)
    }

    private func drawPad(_ ctx: GraphicsContext, _ i: Int) {
        let rect = Self.padRect(i, size: size)
        let (main, deep) = Self.padColors[i]

        // Lit by the machine, by a recent tap, or stuck coral if it was the
        // wrong note.
        let machineLit = engine.showingPad == i
        let tapLit = max(0, 1 - (time - engine.tapFlash[i]) / 0.28)
        let wrong = engine.wrongPad == i
        let lit = machineLit ? 1.0 : tapLit

        var g = ctx
        if lit > 0 {
            // Pads breathe up slightly while they sing.
            let s = 1 + 0.05 * lit
            g.translateBy(x: rect.midX, y: rect.midY)
            g.scaleBy(x: s, y: s)
            g.translateBy(x: -rect.midX, y: -rect.midY)
        }
        let shape = Path(roundedRect: rect, cornerRadius: 15)

        var sh = g
        sh.translateBy(x: 1.5, y: 2.5)
        sh.addFilter(.blur(radius: 2))
        sh.fill(shape, with: .color(Palette.shadow))

        if lit > 0.02 || wrong {
            var glow = g
            glow.addFilter(.blur(radius: 5))
            glow.fill(shape.strokedPath(StrokeStyle(lineWidth: 6)),
                      with: .color((wrong ? Palette.bumperCoral : main)
                          .opacity(wrong ? 0.85 : 0.7 * lit)))
        }

        g.fill(shape, with: .color(wrong ? Palette.bumperCoral : main))
        if lit > 0.02 {
            g.fill(shape, with: .color(.white.opacity(0.42 * lit)))
        }
        g.stroke(shape, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.6))

        // Inner ring gives each pad a speaker-ish face.
        let ring = Path(roundedRect: rect.insetBy(dx: 7, dy: 7), cornerRadius: 10)
        g.stroke(ring, with: .color(deep.opacity(lit > 0.02 ? 0.35 : 0.55)),
                 style: StrokeStyle(lineWidth: 2))
        g.fill(arcadeEllipse(at: CGPoint(x: rect.midX, y: rect.midY),
                             rx: 3.2 + lit * 1.6, ry: 3.2 + lit * 1.6),
               with: .color(.white.opacity(lit > 0.02 ? 0.9 : 0.5)))
    }

    private func drawCenter(_ ctx: GraphicsContext) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2 + 4)
        let flash = max(0, 1 - (time - engine.lastRoundAt) / 0.5)
        let r = 19.0 + flash * 2

        arcadeInkedEllipse(ctx, at: c, rx: r, ry: r, fill: .white, ink: 1.6)
        ctx.draw(Text("\(engine.sequence.count)")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(Palette.ink.opacity(0.75 + flash * 0.25)),
                 at: c)

        // Progress ring hugging the disc — scales to any sequence length.
        // Gold sweeps with the player's answers; blue with the playback.
        let n = engine.sequence.count
        var frac = 0.0
        var color = Palette.gold
        switch engine.phase {
        case .listening(let progress):
            frac = Double(progress) / Double(n)
        case .showing(let step, let since):
            let noteDone = min((time - since) / Self.showBeatForRing, 1)
            frac = (Double(step) + noteDone) / Double(n)
            color = Palette.boostBlue
        case .breathe:
            // Hold the finished gold ring through the round-complete flash.
            frac = flash > 0 ? 1 : 0
        case .done:
            frac = 0
        }
        // Ring sits just inside the disc rim so it never crosses the pads.
        let ringR = r - 4.5
        ctx.stroke(arcadeEllipse(at: c, rx: ringR, ry: ringR),
                   with: .color(Palette.ink.opacity(0.12)),
                   style: StrokeStyle(lineWidth: 2.6))
        guard frac > 0.001 else { return }
        var arc = Path()
        arc.addArc(center: c, radius: ringR,
                   startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * frac),
                   clockwise: false)
        ctx.stroke(arc, with: .color(color),
                   style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        ctx.stroke(arc, with: .color(Palette.ink.opacity(0.45)),
                   style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
        // Bright tip so each new note reads as a tick forward.
        if frac < 1 {
            let a = -Double.pi / 2 + 2 * .pi * frac
            ctx.fill(arcadeEllipse(at: CGPoint(x: c.x + cos(a) * ringR,
                                               y: c.y + sin(a) * ringR),
                                   rx: 2.4, ry: 2.4),
                     with: .color(.white))
        }
    }

    /// Playback beat length, mirrored from the engine for the ring sweep.
    private static var showBeatForRing: Double { EchoEngine.showBeat }
}

// MARK: - Home page

struct EchoHome: View {
    var body: some View {
        GameHome(title: "Echo") { t in
            EchoScene(t: t)
        } destination: {
            EchoView()
        }
    }
}

/// Little vignette: the four pads running through an endless demo song.
private struct EchoScene: View {
    let t: Double

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2, cy = size.height / 2
            let pad = 30.0, gap = 6.0
            let song = [0, 2, 1, 3, 2, 0, 3, 1]
            let beat = Int(t / 0.5) % song.count
            let phase = (t / 0.5).truncatingRemainder(dividingBy: 1)
            let litPad = song[beat]
            let lit = phase < 0.6 ? 1 - phase / 0.6 : 0

            for i in 0..<4 {
                let col = Double(i % 2), row = Double(i / 2)
                let rect = CGRect(x: cx - pad - gap / 2 + col * (pad + gap),
                                  y: cy - pad - gap / 2 + row * (pad + gap),
                                  width: pad, height: pad)
                let shape = Path(roundedRect: rect, cornerRadius: 9)
                let (main, _) = EchoRenderer.padColors[i]
                let on = i == litPad ? lit : 0
                if on > 0.02 {
                    var glow = ctx
                    glow.addFilter(.blur(radius: 4))
                    glow.fill(shape.strokedPath(StrokeStyle(lineWidth: 5)),
                              with: .color(main.opacity(0.7 * on)))
                }
                ctx.fill(shape, with: .color(main))
                if on > 0.02 {
                    ctx.fill(shape, with: .color(.white.opacity(0.45 * on)))
                }
                ctx.stroke(shape, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.5))
            }
            arcadeInkedEllipse(ctx, at: CGPoint(x: cx, y: cy), rx: 10, ry: 10,
                               fill: .white, ink: 1.5)
        }
    }
}
