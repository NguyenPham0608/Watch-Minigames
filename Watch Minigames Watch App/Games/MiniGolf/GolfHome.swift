//
//  GolfHome.swift
//  Watch Minigames Watch App
//
//  Mini Golf's home page (play or build a course) and its putting vignette.
//

import SwiftUI

struct GolfHome: View {
    @Environment(ScoreStore.self) private var store
    @State private var creatingNew = false
    @State private var newNumber = 1

    var body: some View {
        GameHome(title: "Mini Golf", sceneHeight: 72, spacing: 6) { t in
            SplashScene(t: t)
        } destination: {
            LazyView { GolfView(holes: GolfLevels.builtIn, isRound: true) }
        } accessory: {
            HStack(spacing: 6) {
                Button {
                    newNumber = store.peekCustomNumber
                    creatingNew = true
                } label: {
                    CapsuleActionLabel(text: store.customHoles.isEmpty ? "New Course" : "New",
                                       compact: true, whiteFill: true)
                }
                .buttonStyle(BouncyButtonStyle())

                if !store.customHoles.isEmpty {
                    NavigationLink {
                        CustomCourseList()
                    } label: {
                        CapsuleActionLabel(text: "My Courses", compact: true, whiteFill: true)
                    }
                    .buttonStyle(BouncyButtonStyle())
                }
            }
        }
        .sheet(isPresented: $creatingNew) {
            NavigationStack {
                EditorView(hole: nil, newNumber: newNumber)
                    .environment(store)
            }
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
            let halfLen = min(46.0, size.width / 2 - 38)
            let scaleK = halfLen / 52
            let pillW = 44.0
            func pill(_ off: Double) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: cx - halfLen, y: 36))
                p.addLine(to: CGPoint(x: cx + halfLen, y: 36))
                return p.strokedPath(StrokeStyle(lineWidth: pillW + off, lineCap: .round))
            }

            var shadow = ctx
            shadow.translateBy(x: 2, y: 3)
            shadow.fill(pill(15), with: .color(Palette.shadow))
            ctx.fill(pill(15), with: .color(Palette.ink))
            ctx.fill(pill(9.5), with: .color(Palette.wallTop))
            ctx.fill(pill(4.5), with: .color(Palette.ink))
            ctx.fill(pill(0), with: .color(Palette.fairway))
            // Crosswise mow stripes.
            var stripes = ctx
            stripes.clip(to: pill(0))
            for i in 0..<4 {
                stripes.fill(Path(CGRect(x: cx + (-66 + Double(i) * 34) * scaleK, y: 0,
                                         width: 17 * scaleK, height: 72)),
                             with: .color(Palette.fairwayStripe))
            }

            let cup = CGPoint(x: cx - 34 * scaleK, y: 36)
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
            let stops = [CGPoint(x: cx + 42 * scaleK, y: 36),
                         CGPoint(x: cx + 20 * scaleK, y: 52),
                         CGPoint(x: cx - 12 * scaleK, y: 20),
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
