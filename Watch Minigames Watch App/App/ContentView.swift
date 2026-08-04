//
//  ContentView.swift
//  Minigames Watch App
//
//  Home: swipe between games. Page one is Mini Golf (play or build a
//  course), page two is Super Pong.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            TabView {
                GolfHome()
                PongHome()
                StackerHome()
                BricksHome()
                EchoHome()
                FruitHome()
            }
        }
    }
}

// MARK: - Mini Golf page

private struct GolfHome: View {
    @Environment(ScoreStore.self) private var store
    @State private var creatingNew = false
    @State private var newNumber = 1

    var body: some View {
            VStack(spacing: 6) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    SplashScene(t: timeline.date.timeIntervalSinceReferenceDate)
                }
                .frame(height: 72)

                Text("Mini Golf")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)

                NavigationLink {
                    GameView(holes: Levels.builtIn, isRound: true)
                } label: {
                    Text("Play")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Palette.gold))
                        .overlay(Capsule().stroke(Palette.ink, lineWidth: 1.6))
                        .foregroundStyle(Palette.ink)
                }
                .buttonStyle(.plain)

                Button {
                    newNumber = store.nextCustomNumber()
                    creatingNew = true
                } label: {
                    Text("New Course")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.white.opacity(0.92)))
                        .overlay(Capsule().stroke(Palette.ink, lineWidth: 1.4))
                        .foregroundStyle(Palette.ink)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bg.ignoresSafeArea())
            .sheet(isPresented: $creatingNew) {
                NavigationStack {
                    EditorView(hole: nil, newNumber: newNumber)
                        .environment(store)
                }
            }
    }
}

// MARK: - Super Pong page

private struct PongHome: View {
    @Environment(ScoreStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                PongScene(t: timeline.date.timeIntervalSinceReferenceDate)
            }
            .frame(height: 88)

            Text("Super Pong")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)

            NavigationLink {
                PongView()
            } label: {
                Text("Play")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Palette.gold))
                    .overlay(Capsule().stroke(Palette.ink, lineWidth: 1.6))
                    .foregroundStyle(Palette.ink)
            }
            .buttonStyle(.plain)

            // Bot difficulty.
            DifficultySlider()
                .padding(.horizontal, 18)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
    }
}

/// Color-coded difficulty slider: drag the knob across the green-to-red
/// track to pick how good the bot is.
private struct DifficultySlider: View {
    @Environment(ScoreStore.self) private var store

    private static let colors: [Color] = [Color(red: 0.66, green: 0.80, blue: 0.64),
                                          Color(red: 0.96, green: 0.85, blue: 0.58),
                                          Color(red: 0.94, green: 0.70, blue: 0.63)]

    var body: some View {
        GeometryReader { geo in
                let w = geo.size.width
                let x = 11 + (w - 22) * Double(store.pongDifficulty) / 2
                ZStack {
                    Capsule()
                        .fill(LinearGradient(colors: Self.colors,
                                             startPoint: .leading, endPoint: .trailing))
                        .overlay(Capsule().stroke(Palette.ink, lineWidth: 1.4))
                        .frame(height: 13)
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(Palette.ink, lineWidth: 1.6))
                        .frame(width: 21, height: 21)
                        .position(x: x, y: geo.size.height / 2)
                        .animation(.spring(duration: 0.25), value: store.pongDifficulty)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let f = min(max((v.location.x - 11) / (w - 22), 0), 1)
                    let level = Int((f * 2).rounded())
                    if level != store.pongDifficulty {
                        store.setPongDifficulty(level)
                        Haptics.play(.click, minInterval: 0)
                    }
                })
        }
        .frame(height: 22)
    }
}

// MARK: - Stacker page

private struct StackerHome: View {
    @Environment(ScoreStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                StackerScene(t: timeline.date.timeIntervalSinceReferenceDate)
            }
            .frame(height: 88)

            Text("Stacker")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)

            NavigationLink {
                StackerView()
            } label: {
                Text("Play")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Palette.gold))
                    .overlay(Capsule().stroke(Palette.ink, lineWidth: 1.6))
                    .foregroundStyle(Palette.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
    }
}

/// Little vignette: a wobbling tower with a mug swaying in overhead.
private struct StackerScene: View {
    let t: Double

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let floorY = size.height - 12
            var floor = Path()
            floor.move(to: CGPoint(x: cx - 58, y: floorY))
            floor.addLine(to: CGPoint(x: cx + 58, y: floorY))
            ctx.stroke(floor, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            let wob = sin(t * 3.1) * 0.045
            let engineDummy = StackerEngine()
            let renderer = StackerRenderer(engine: engineDummy, size: size, time: t)
            func piece(_ kind: StackerEngine.ObjectKind, _ color: Int,
                       _ dx: Double, _ bottomY: Double, _ rotFactor: Double) {
                let spec = StackerEngine.spec(for: kind, colorIndex: color)
                var g = ctx
                g.translateBy(x: cx, y: floorY)
                g.rotate(by: Angle(radians: wob * rotFactor))
                g.translateBy(x: -cx, y: -floorY)
                renderer.drawObject(g, spec: spec, x: cx + dx, bottomY: bottomY)
            }
            piece(.box, 0, 0, floorY, 0.3)
            piece(.book, 1, 3, floorY - 32, 0.7)

            // Swaying mug overhead, clear of the tower and the frame edge.
            let mugSpec = StackerEngine.spec(for: .mug, colorIndex: 2)
            let mx = cx + sin(t * 1.6) * 34
            renderer.drawObject(ctx, spec: mugSpec, x: mx, bottomY: 25)
        }
    }
}

/// Little vignette: paddles trading a glowing rally.
private struct PongScene: View {
    let t: Double

    var body: some View {
        Canvas { ctx, size in
            let court = CGRect(x: size.width / 2 - 62, y: size.height / 2 - 30,
                               width: 124, height: 60)
            let floor = Path(roundedRect: court, cornerRadius: 9)
            var shadow = ctx
            shadow.translateBy(x: 2, y: 3)
            shadow.addFilter(.blur(radius: 2.5))
            shadow.fill(floor, with: .color(Palette.shadow))
            ctx.fill(floor, with: .color(.white.opacity(0.55)))
            var center = Path()
            center.move(to: CGPoint(x: court.midX, y: court.minY + 5))
            center.addLine(to: CGPoint(x: court.midX, y: court.maxY - 5))
            ctx.stroke(center, with: .color(Palette.ink.opacity(0.2)),
                       style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
            ctx.stroke(floor, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.8))

            // Rallying ball with a small trail.
            let phase = (sin(t * 1.7) + 1) / 2
            let bx = court.minX + 16 + (court.width - 32) * phase
            let by = court.midY + sin(t * 3.4) * 14
            for i in 1...4 {
                let f = Double(i) / 5
                let px = court.minX + 16 + (court.width - 32)
                    * ((sin((t - Double(i) * 0.05) * 1.7) + 1) / 2)
                let py = court.midY + sin((t - Double(i) * 0.05) * 3.4) * 14
                ctx.fill(Path(ellipseIn: CGRect(x: px - 2.5 * (1 - f), y: py - 2.5 * (1 - f),
                                                width: 5 * (1 - f), height: 5 * (1 - f))),
                         with: .color(Palette.boostBlue.opacity(0.4 * (1 - f))))
            }
            let ballRect = CGRect(x: bx - 4, y: by - 4, width: 8, height: 8)
            ctx.fill(Path(ellipseIn: ballRect), with: .color(Palette.wallTop))
            ctx.stroke(Path(ellipseIn: ballRect), with: .color(Palette.ink),
                       style: StrokeStyle(lineWidth: 1.4))

            // Paddles tracking the ball.
            func paddle(x: Double, y: Double, color: Color) {
                let rect = CGRect(x: x - 2.5, y: y - 11, width: 5, height: 22)
                let p = Path(roundedRect: rect, cornerRadius: 2.5)
                ctx.fill(p, with: .color(color))
                ctx.stroke(p, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.3))
            }
            paddle(x: court.minX + 8, y: court.midY + sin((t - 0.25) * 3.4) * 10,
                   color: Palette.bumperCoral)
            paddle(x: court.maxX - 8, y: court.midY + sin((t - 0.1) * 3.4) * 12,
                   color: Palette.boostBlue)
        }
    }
}

/// Little vignette: a pill-shaped hole — the ball ricochets off both walls,
/// drops in the cup with a gold burst, then waits on the tee before going
/// again.
private struct SplashScene: View {
    let t: Double

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2

            func ellipse(_ c: CGPoint, _ rx: Double, _ ry: Double) -> Path {
                Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry,
                                       width: rx * 2, height: ry * 2))
            }

            // One clean horizontal pill, banded like the game's walls.
            // Sized to the screen so the caps never clip.
            let L = min(46.0, size.width / 2 - 38)
            let k = L / 52
            let pillW = 44.0
            func pill(_ off: Double) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: cx - L, y: 36))
                p.addLine(to: CGPoint(x: cx + L, y: 36))
                return p.strokedPath(StrokeStyle(lineWidth: pillW + off, lineCap: .round))
            }

            var shadow = ctx
            shadow.translateBy(x: 2, y: 3)
            shadow.addFilter(.blur(radius: 2.5))
            shadow.fill(pill(15), with: .color(Palette.shadow))
            ctx.fill(pill(15), with: .color(Palette.ink))
            ctx.fill(pill(9.5), with: .color(Palette.wallTop))
            ctx.fill(pill(4.5), with: .color(Palette.ink))
            ctx.fill(pill(0), with: .color(Palette.fairway))
            // Crosswise mow stripes.
            var stripes = ctx
            stripes.clip(to: pill(0))
            for i in 0..<4 {
                stripes.fill(Path(CGRect(x: cx + (-66 + Double(i) * 34) * k, y: 0,
                                         width: 17 * k, height: 72)),
                             with: .color(Palette.fairwayStripe))
            }

            let cup = CGPoint(x: cx - 34 * k, y: 36)
            let cupHole = ellipse(cup, 5.5, 3.9)
            ctx.fill(cupHole, with: .color(Palette.cup))

            let u = (t / 3.4).truncatingRemainder(dividingBy: 1)

            // Pole + flag behind the ball; the wave deepens (same rhythm)
            // when the putt drops.
            var pole = Path()
            pole.move(to: cup)
            pole.addLine(to: CGPoint(x: cup.x, y: cup.y - 23))
            ctx.stroke(pole, with: .color(Palette.ink),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            let kick = max(0, 1 - abs((u - 0.66) / 0.22))
            let wave = sin(t * 2.6) * (2.0 + kick * 2.6)
            var flag = Path()
            flag.move(to: CGPoint(x: cup.x, y: cup.y - 23))
            flag.addQuadCurve(to: CGPoint(x: cup.x + 15, y: cup.y - 17.5 + wave * 0.4),
                              control: CGPoint(x: cup.x + 7.5, y: cup.y - 22 + wave))
            flag.addLine(to: CGPoint(x: cup.x, y: cup.y - 14))
            flag.closeSubpath()
            ctx.fill(flag, with: .color(Palette.gold))
            ctx.stroke(flag, with: .color(Palette.ink),
                       style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

            // The putt ricochets: bottom wall, top wall, then the cup —
            // equal angles in and out.
            let stops = [CGPoint(x: cx + 42 * k, y: 36),
                         CGPoint(x: cx + 20 * k, y: 52),
                         CGPoint(x: cx - 12 * k, y: 20),
                         cup]
            var lens: [Double] = []
            for i in 0..<3 {
                lens.append(hypot(stops[i + 1].x - stops[i].x,
                                  stops[i + 1].y - stops[i].y))
            }
            let total = lens.reduce(0, +)
            func onPutt(_ e: Double) -> CGPoint {
                var s = e * total
                for i in 0..<3 {
                    if s <= lens[i] || i == 2 {
                        let f = min(s / lens[i], 1)
                        return CGPoint(x: stops[i].x + (stops[i + 1].x - stops[i].x) * f,
                                       y: stops[i].y + (stops[i + 1].y - stops[i].y) * f)
                    }
                    s -= lens[i]
                }
                return cup
            }
            func drawBall(_ g: GraphicsContext, at c: CGPoint, scale: Double) {
                guard scale > 0.02 else { return }
                let br = 4.8 * scale
                let bc = CGPoint(x: c.x, y: c.y - 3.4 * scale)
                g.fill(ellipse(bc, br, br), with: .color(Palette.wallTop))
                g.stroke(ellipse(bc, br, br), with: .color(Palette.ink),
                         style: StrokeStyle(lineWidth: 1.5 * scale))
            }

            if u < 0.5 {
                // Rolling, easing off the putter; the ball covers the hole
                // as it arrives.
                let e = 1 - pow(1 - u / 0.5, 2.2)
                for i in 1...4 {
                    let ei = e - Double(i) * 0.07
                    guard ei > 0 else { continue }
                    let f = Double(i) / 5
                    let d = onPutt(ei)
                    ctx.fill(ellipse(CGPoint(x: d.x, y: d.y - 3.4),
                                     2.2 * (1 - f), 2.2 * (1 - f)),
                             with: .color(Palette.gold.opacity(0.5 * (1 - f))))
                }
                drawBall(ctx, at: onPutt(e), scale: 1)
            } else if u < 0.58 {
                // Dropping in: the ball shrinks away inside the hole.
                let s = (u - 0.5) / 0.08
                var inside = ctx
                inside.clip(to: cupHole)
                var c = onPutt(1)
                c.y += s * 5
                drawBall(inside, at: c, scale: 1 - s * 0.75)
            } else if u > 0.72 {
                // Back on the tee, waiting out a breather before the next
                // putt (rest of the cycle ≈ 0.8s).
                drawBall(ctx, at: stops[0], scale: min((u - 0.72) / 0.04, 1))
            }

            // Gold burst when it drops.
            if u > 0.56, u < 0.9 {
                let q = (u - 0.56) / 0.34
                for k in 0..<9 {
                    let a = Double(k) / 9 * 2 * .pi + 0.35
                    let r = 5 + q * 15
                    let p = CGPoint(x: cup.x + cos(a) * r,
                                    y: cup.y - 4 + sin(a) * r * 0.6 - q * 8)
                    let sz = 2.1 * (1 - q * 0.65)
                    ctx.fill(ellipse(p, sz, sz),
                             with: .color((k.isMultiple(of: 2) ? Palette.gold : Palette.wallTop)
                                 .opacity(0.9 * (1 - q))))
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(ScoreStore())
}
