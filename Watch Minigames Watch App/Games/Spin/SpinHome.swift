//
//  SpinHome.swift
//  Watch Minigames Watch App
//
//  Spin's home page and its sweeping-lock vignette.
//

import SwiftUI

struct SpinHome: View {
    var body: some View {
        GameHome(title: "Spin") { t in
            SpinScene(t: t)
        } destination: {
            SpinView()
        }
    }
}

/// Little vignette: the ball sweeps the mini lock, pops the wedge with a
/// spark, and the hub turns a notch — alternating direction each lap.
private struct SpinScene: View {
    let t: Double

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2 + 2)
            let ringR = 30.0
            let trackW = 12.0

            func onRing(_ a: Double, _ r: Double) -> CGPoint {
                CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            }

            let ring = Path(ellipseIn: CGRect(x: c.x - ringR, y: c.y - ringR,
                                              width: ringR * 2, height: ringR * 2))
            var sh = ctx
            sh.translateBy(x: 1.5, y: 2.5)
            sh.stroke(ring, with: .color(Palette.shadow),
                      style: StrokeStyle(lineWidth: trackW))
            ctx.stroke(ring, with: .color(.white.opacity(0.72)),
                       style: StrokeStyle(lineWidth: trackW))

            // One sweep per period; direction alternates and stays
            // continuous because each lap ends where the next begins.
            let period = 2.1
            let lap = Int(t / period)
            let f = t / period - Double(lap)
            let sweep = 2 * Double.pi * 0.82
            let dir: Double = lap.isMultiple(of: 2) ? 1 : -1
            let start = lap.isMultiple(of: 2) ? -Double.pi / 2
                                              : -Double.pi / 2 + sweep
            let wedgeA = start + dir * sweep
            let hitF = 0.82
            let ballA = start + dir * sweep * min(f / hitF, 1)

            // Wedge pops in early in the lap, bursts when the ball arrives;
            // it's a flat painted section of the track, under the rims.
            let popIn = easeOutBack(min(f / 0.2, 1))
            let half = 0.34 * popIn
            var arc = Path()
            arc.addArc(center: c, radius: ringR,
                       startAngle: .radians(wedgeA - half),
                       endAngle: .radians(wedgeA + half), clockwise: false)
            ctx.stroke(arc, with: .color(Palette.gold),
                       style: StrokeStyle(lineWidth: trackW))
            for edge in [ringR + trackW / 2, ringR - trackW / 2] {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - edge, y: c.y - edge,
                                                  width: edge * 2, height: edge * 2)),
                           with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.3))
            }

            // Needle tick.
            var needle = Path()
            needle.move(to: onRing(ballA, ringR - trackW / 2 + 1.5))
            needle.addLine(to: onRing(ballA, ringR + trackW / 2 - 1.5))
            ctx.stroke(needle, with: .color(Palette.ink),
                       style: StrokeStyle(lineWidth: 2.6, lineCap: .round))

            // Spark fan while the hit lands.
            if f > hitF {
                let age = (f - hitF) / (1 - hitF)
                let wp = onRing(wedgeA, ringR)
                for k in 0..<7 {
                    let a = Double(k) / 7 * 2 * .pi + 0.4
                    let dist = 4 + age * 13
                    let p = CGPoint(x: wp.x + cos(a) * dist, y: wp.y + sin(a) * dist)
                    let s = 1.8 * (1 - age)
                    ctx.fill(arcadeEllipse(at: p, rx: s, ry: s),
                             with: .color((k.isMultiple(of: 2) ? Palette.gold : .white)
                                 .opacity(0.9 * (1 - age))))
                }
            }

            // Plain hub disc.
            arcadeInkedEllipse(ctx, at: c, rx: 9.5, ry: 9.5, fill: .white, ink: 1.3)
        }
    }
}
