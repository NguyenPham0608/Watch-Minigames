//
//  StackerView.swift
//  Minigames Watch App
//
//  Stacker's living room: wallpaper, wooden floor, and a tower of cartoon
//  household objects that wobbles, leans and — eventually — tumbles.
//

import SwiftUI

struct StackerView: View {
    @Environment(ScoreStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var engine = StackerEngine()
    @State private var finalScore: Int? = nil
    @State private var wasBest = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation) { timeline in
                    canvasView(size: geo.size, date: timeline.date)
                }
                if let finalScore { resultOverlay(finalScore) }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            engine.onGameOver = { score in
                wasBest = store.recordStackerBest(score)
                withAnimation(.easeOut(duration: 0.3)) { finalScore = score }
            }
        }
    }

    private func canvasView(size: CGSize, date: Date) -> some View {
        engine.courtW = size.width
        engine.courtH = size.height
        engine.step(to: date)
        let renderer = StackerRenderer(engine: engine, size: size, time: engine.time)
        return Canvas { ctx, _ in
            renderer.draw(into: ctx)
        }
        .onTapGesture { engine.drop() }
    }

    private func resultOverlay(_ score: Int) -> some View {
        VStack(spacing: 6) {
            Text("Stacked \(score)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(score > 0 ? Palette.goldDeep : Palette.ink)
            Text(wasBest && score > 0 ? "New Best" : "Best \(store.stackerBest)")
                .font(.system(size: 12, weight: wasBest ? .semibold : .regular,
                              design: .rounded))
                .foregroundStyle(wasBest && score > 0 ? Palette.goldDeep
                                 : Palette.ink.opacity(0.55))
            HStack(spacing: 10) {
                Button {
                    engine.reset()
                    withAnimation { finalScore = nil }
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

struct StackerRenderer {
    let engine: StackerEngine
    let size: CGSize
    let time: Double

    static let objectColors: [(Color, Color)] = [
        (Palette.boostBlue, Palette.boostBlueDeep),
        (Palette.bumperCoral, Color(red: 0.70, green: 0.34, blue: 0.27)),
        (Palette.gold, Palette.goldDeep),
        (Color(red: 0.63, green: 0.53, blue: 0.79), Color(red: 0.48, green: 0.39, blue: 0.63)),
        (Color(red: 0.38, green: 0.70, blue: 0.66), Color(red: 0.27, green: 0.54, blue: 0.50)),
    ]

    private func ellipse(at c: CGPoint, rx: Double, ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
    }

    func draw(into base: GraphicsContext) {
        var ctx = base
        if engine.shakeAmp > 0.15 {
            ctx.translateBy(x: sin(time * 67) * engine.shakeAmp,
                            y: cos(time * 53) * engine.shakeAmp * 0.6)
        }

        let cam = engine.cameraOffset
        drawRoom(ctx, cam: cam)

        // World-space content shifts down as the camera climbs.
        var world = ctx
        world.translateBy(x: 0, y: cam)

        drawStack(world)
        drawFreeBodies(world)
        drawFallingAndSway(world, cam: cam)
        drawParticles(world)

        drawHUD(ctx)
    }

    // MARK: Room

    private func drawRoom(_ ctx: GraphicsContext, cam: Double) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.bg))

        // Wallpaper dots scroll with the world for a sense of height.
        var dots = Path()
        let spacing = 44.0
        let offset = cam.truncatingRemainder(dividingBy: spacing)
        var y = offset - spacing
        var row = Int((cam / spacing).rounded(.down))
        while y < size.height + spacing {
            let shift = (row % 2 == 0) ? 0.0 : spacing / 2
            var x = shift
            while x < size.width {
                dots.addEllipse(in: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8))
                x += spacing
            }
            y += spacing
            row -= 1
        }
        ctx.fill(dots, with: .color(Palette.ink.opacity(0.06)))

        // Wooden floor (scrolls away as the tower climbs).
        let floorTop = engine.floorY + cam
        if floorTop < size.height + 10 {
            let floorRect = CGRect(x: 0, y: floorTop, width: size.width,
                                   height: size.height - floorTop + 10)
            ctx.fill(Path(floorRect), with: .color(Palette.sand))
            var boards = Path()
            boards.move(to: CGPoint(x: 0, y: floorTop))
            boards.addLine(to: CGPoint(x: size.width, y: floorTop))
            var bx = 24.0
            while bx < size.width {
                boards.move(to: CGPoint(x: bx, y: floorTop + 5))
                boards.addLine(to: CGPoint(x: bx + 8, y: floorTop + 5))
                bx += 42
            }
            ctx.stroke(boards, with: .color(Palette.sandDark.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.4))
            ctx.stroke(Path(CGRect(x: -2, y: floorTop, width: size.width + 4, height: 3)),
                       with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.4))
        }

        // Clock scrim.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 42)),
                 with: .linearGradient(
                    Gradient(colors: [Color.black.opacity(0.28), .clear]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: 42)))
    }

    // MARK: Tower

    private func drawStack(_ ctx: GraphicsContext) {
        let count = engine.stack.count
        for (i, p) in engine.stack.enumerated() {
            // Wobble travels up the tower: higher pieces rock harder.
            let heightFactor = count > 1 ? Double(i) / Double(count - 1) : 0
            let rot = engine.wobbleAmp * heightFactor
                * sin(time * 5.2 + Double(i) * 0.55)
            var g = ctx
            let pivot = CGPoint(x: p.x, y: p.bottomY)
            g.translateBy(x: pivot.x, y: pivot.y)
            g.rotate(by: Angle(radians: rot))
            // Fresh landings squash for a beat.
            if i == count - 1 {
                let squash = max(0, 1 - (time - engine.lastLandAt) / 0.16) * 0.12
                g.scaleBy(x: 1 + squash, y: 1 - squash)
            }
            g.translateBy(x: -pivot.x, y: -pivot.y)
            drawObject(g, spec: p.spec, x: p.x, bottomY: p.bottomY)
        }
    }

    private func drawFreeBodies(_ ctx: GraphicsContext) {
        for body in engine.freeBodies {
            var g = ctx
            let pivot = CGPoint(x: body.x, y: body.y - body.spec.h / 2)
            g.translateBy(x: pivot.x, y: pivot.y)
            g.rotate(by: Angle(radians: body.rot))
            g.translateBy(x: -pivot.x, y: -pivot.y)
            drawObject(g, spec: body.spec, x: body.x, bottomY: body.y)
        }
    }

    private func drawFallingAndSway(_ ctx: GraphicsContext, cam: Double) {
        switch engine.phase {
        case .swaying(let spec, let since):
            let x = engine.swayX(spec: spec, since: since)
            let bob = sin(time * 2.4) * 2
            let bottomY = engine.swayScreenY - cam + spec.h + bob
            // Drop guide.
            var guide = Path()
            guide.move(to: CGPoint(x: x, y: bottomY + 4))
            guide.addLine(to: CGPoint(x: x, y: engine.towerTopY - 4))
            ctx.stroke(guide, with: .color(Palette.ink.opacity(0.14)),
                       style: StrokeStyle(lineWidth: 1.3, dash: [3, 5]))
            drawObject(ctx, spec: spec, x: x, bottomY: bottomY)
        case .falling(let spec, let x, let bottomY, _):
            drawObject(ctx, spec: spec, x: x, bottomY: bottomY)
        default:
            break
        }
    }

    // MARK: HUD

    private func drawHUD(_ ctx: GraphicsContext) {
        let flash = max(0, 1 - (time - engine.lastPerfectAt) / 0.5)
        ctx.draw(Text("\(engine.score)")
            .font(.system(size: 40 * (1 + flash * 0.25), weight: .heavy, design: .rounded))
            .foregroundStyle(Palette.boostBlueDeep.opacity(0.4 + flash * 0.4)),
                 at: CGPoint(x: size.width - 34, y: 62))
        if flash > 0 {
            ctx.draw(Text("PERFECT")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.goldDeep.opacity(flash)),
                     at: CGPoint(x: size.width / 2, y: 96 - (1 - flash) * 8))
        }
    }

    // MARK: Objects

    private func drawParticles(_ ctx: GraphicsContext) {
        for particle in engine.particles {
            let a = max(0, particle.life / particle.maxLife)
            let c = CGPoint(x: particle.pos.x, y: particle.pos.y)
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
            ctx.fill(ellipse(at: c, rx: r * 2, ry: r * 2), with: .color(color.opacity(a * 0.18)))
            ctx.fill(ellipse(at: c, rx: r, ry: r), with: .color(color.opacity(a)))
        }
    }

    /// Draws one household object with its bottom-center at (x, bottomY).
    func drawObject(_ ctx: GraphicsContext, spec: StackerEngine.Spec,
                    x: Double, bottomY: Double) {
        let (main, deep) = Self.objectColors[spec.colorIndex % Self.objectColors.count]
        let w = spec.w, h = spec.h
        let rect = CGRect(x: x - w / 2, y: bottomY - h, width: w, height: h)
        let ink = StrokeStyle(lineWidth: 1.4, lineJoin: .round)

        func rr(_ r: CGRect, _ radius: Double) -> Path { Path(roundedRect: r, cornerRadius: radius) }

        switch spec.kind {
        case .box:
            let p = rr(rect, 3)
            ctx.fill(p, with: .color(Palette.sand))
            ctx.stroke(p, with: .color(Palette.ink), style: ink)
            var tape = Path()
            tape.move(to: CGPoint(x: rect.midX, y: rect.minY))
            tape.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            ctx.stroke(tape, with: .color(Palette.sandDark), style: StrokeStyle(lineWidth: 4))
            var flap = Path()
            flap.move(to: CGPoint(x: rect.minX, y: rect.minY + 8))
            flap.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 8))
            ctx.stroke(flap, with: .color(Palette.sandDark.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.2))
        case .book:
            let p = rr(rect, 2.5)
            ctx.fill(p, with: .color(main))
            ctx.stroke(p, with: .color(Palette.ink), style: ink)
            var pages = Path()
            pages.move(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 3))
            pages.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.maxY - 3))
            ctx.stroke(pages, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1.6))
        case .tv:
            let p = rr(rect, 5)
            ctx.fill(p, with: .color(deep))
            ctx.stroke(p, with: .color(Palette.ink), style: ink)
            let screen = rr(rect.insetBy(dx: 5, dy: 5), 3)
            ctx.fill(screen, with: .color(Color(red: 0.72, green: 0.84, blue: 0.86)))
            ctx.stroke(screen, with: .color(Palette.ink.opacity(0.6)), style: StrokeStyle(lineWidth: 1))
            ctx.fill(ellipse(at: CGPoint(x: rect.minX + 11, y: rect.minY + 11), rx: 3.4, ry: 3),
                     with: .color(.white.opacity(0.5)))
        case .radio:
            let p = rr(rect, 5)
            ctx.fill(p, with: .color(main))
            ctx.stroke(p, with: .color(Palette.ink), style: ink)
            var grille = Path()
            for i in 0..<3 {
                let gx = rect.minX + 7 + Double(i) * 5
                grille.move(to: CGPoint(x: gx, y: rect.minY + 6))
                grille.addLine(to: CGPoint(x: gx, y: rect.maxY - 6))
            }
            ctx.stroke(grille, with: .color(Palette.ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1.4))
            ctx.fill(ellipse(at: CGPoint(x: rect.maxX - 9, y: rect.midY), rx: 4.5, ry: 4.5),
                     with: .color(.white.opacity(0.85)))
            ctx.stroke(ellipse(at: CGPoint(x: rect.maxX - 9, y: rect.midY), rx: 4.5, ry: 4.5),
                       with: .color(Palette.ink.opacity(0.7)), style: StrokeStyle(lineWidth: 1))
        case .toaster:
            let p = rr(rect, 7)
            ctx.fill(p, with: .color(Palette.fanGray))
            ctx.stroke(p, with: .color(Palette.ink), style: ink)
            var slots = Path()
            slots.addRoundedRect(in: CGRect(x: rect.minX + 6, y: rect.minY + 3, width: 10, height: 3),
                                 cornerSize: CGSize(width: 1.5, height: 1.5))
            slots.addRoundedRect(in: CGRect(x: rect.maxX - 16, y: rect.minY + 3, width: 10, height: 3),
                                 cornerSize: CGSize(width: 1.5, height: 1.5))
            ctx.fill(slots, with: .color(Palette.ink.opacity(0.65)))
        case .mug:
            let body = rr(CGRect(x: rect.minX + 3, y: rect.minY, width: w - 10, height: h), 4)
            // Handle ring first — the body overlaps it, so the loop reads as
            // fused to the side instead of floating.
            let ring = ellipse(at: CGPoint(x: rect.maxX - 7, y: rect.midY), rx: 5.5, ry: 5.5)
            ctx.stroke(ring, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 5))
            ctx.stroke(ring, with: .color(main), style: StrokeStyle(lineWidth: 2.2))
            ctx.fill(body, with: .color(main))
            ctx.stroke(body, with: .color(Palette.ink), style: ink)
        case .plant:
            let pot = rr(CGRect(x: x - spec.bottomW / 2, y: rect.maxY - 14,
                                width: spec.bottomW, height: 14), 3)
            for (dx, dy, r) in [(-8.0, 20.0, 7.0), (8.0, 20.0, 7.0), (0.0, 26.0, 8.5)] {
                let leaf = ellipse(at: CGPoint(x: x + dx, y: rect.maxY - dy), rx: r, ry: r * 0.85)
                ctx.fill(leaf, with: .color(Palette.treeGreen))
                ctx.stroke(leaf, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.3))
            }
            ctx.fill(pot, with: .color(Palette.bumperCoral))
            ctx.stroke(pot, with: .color(Palette.ink), style: ink)
        case .clock:
            ctx.fill(ellipse(at: CGPoint(x: x, y: rect.midY), rx: w / 2, ry: w / 2),
                     with: .color(main))
            ctx.stroke(ellipse(at: CGPoint(x: x, y: rect.midY), rx: w / 2, ry: w / 2),
                       with: .color(Palette.ink), style: ink)
            ctx.fill(ellipse(at: CGPoint(x: x, y: rect.midY), rx: w / 2 - 4, ry: w / 2 - 4),
                     with: .color(.white))
            var hands = Path()
            hands.move(to: CGPoint(x: x, y: rect.midY))
            hands.addLine(to: CGPoint(x: x, y: rect.midY - 6))
            hands.move(to: CGPoint(x: x, y: rect.midY))
            hands.addLine(to: CGPoint(x: x + 4.5, y: rect.midY + 1))
            ctx.stroke(hands, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            // Bell crown — the risky little perch on top.
            let bell = ellipse(at: CGPoint(x: x, y: rect.minY + 2), rx: 5, ry: 2.6)
            ctx.fill(bell, with: .color(deep))
            ctx.stroke(bell, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.2))
        case .lamp:
            var pole = Path()
            pole.move(to: CGPoint(x: x, y: rect.maxY - 3))
            pole.addLine(to: CGPoint(x: x, y: rect.minY + 13))
            ctx.stroke(pole, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 3))
            let foot = rr(CGRect(x: x - spec.bottomW / 2, y: rect.maxY - 5,
                                 width: spec.bottomW, height: 5), 2.5)
            ctx.fill(foot, with: .color(deep))
            ctx.stroke(foot, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.2))
            var shade = Path()
            shade.move(to: CGPoint(x: x - 12, y: rect.minY + 14))
            shade.addLine(to: CGPoint(x: x - 7.5, y: rect.minY))
            shade.addLine(to: CGPoint(x: x + 7.5, y: rect.minY))
            shade.addLine(to: CGPoint(x: x + 12, y: rect.minY + 14))
            shade.closeSubpath()
            ctx.fill(shade, with: .color(main))
            ctx.stroke(shade, with: .color(Palette.ink), style: ink)
        }
    }
}
