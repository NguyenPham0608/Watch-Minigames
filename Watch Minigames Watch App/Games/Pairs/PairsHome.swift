//
//  PairsHome.swift
//  Watch Minigames Watch App
//
//  Pairs' home page and its two-cards-finding-each-other vignette.
//

import SwiftUI

struct PairsHome: View {
    var body: some View {
        GameHome(title: "Pairs") { t in
            PairsScene(t: t)
        } destination: {
            PairsView()
        }
    }
}

/// Little vignette: two cards flip over one after the other, reveal
/// matching hearts, sparkle, and settle back down to go again.
private struct PairsScene: View {
    let t: Double

    private static let loopT = 3.6

    var body: some View {
        Canvas { ctx, size in
            let cy = size.height / 2 + 3
            let cardW = 30.0, cardH = 38.0
            let xA = size.width / 2 - 20, xB = size.width / 2 + 20
            let u = (t / Self.loopT).truncatingRemainder(dividingBy: 1)
            let flipDur = 0.06

            // One card of the pair: face-down, flipping up at `upAt`, resting
            // face-up, then flipping back with its partner near the loop end.
            func card(x: Double, upAt: Double) {
                let downAt = 0.80
                var sx = 1.0
                var showFace = false
                if u >= upAt, u < downAt {
                    let p = min((u - upAt) / flipDur, 1)
                    sx = abs(cos(p * .pi))
                    showFace = p >= 0.5
                } else if u >= downAt {
                    let p = min((u - downAt) / flipDur, 1)
                    sx = abs(cos(p * .pi))
                    showFace = p < 0.5
                }
                // A small shared pop when the match lands.
                let pop = 1 + 0.08 * max(0, 1 - abs(u - 0.42) / 0.06)

                let rect = CGRect(x: x - cardW / 2, y: cy - cardH / 2,
                                  width: cardW, height: cardH)
                let c = CGPoint(x: rect.midX, y: rect.midY)
                var g = ctx
                g.translateBy(x: c.x, y: c.y)
                g.scaleBy(x: sx * pop, y: pop)
                g.translateBy(x: -c.x, y: -c.y)

                let shape = Path(roundedRect: rect, cornerRadius: 8)
                var sh = g
                sh.translateBy(x: 1.2, y: 2)
                sh.fill(shape, with: .color(Palette.shadow))

                if showFace {
                    g.fill(shape, with: .color(.white.opacity(0.95)))
                    g.stroke(shape, with: .color(Palette.ink),
                             style: StrokeStyle(lineWidth: 1.5))
                    PairsRenderer.drawGlyph(g, .heart, at: c, r: 7)
                } else {
                    g.fill(shape, with: .color(Palette.wallTop))
                    g.stroke(shape, with: .color(Palette.ink),
                             style: StrokeStyle(lineWidth: 1.5))
                    g.stroke(Path(roundedRect: rect.insetBy(dx: 4, dy: 4), cornerRadius: 5),
                             with: .color(Palette.sandDark.opacity(0.5)),
                             style: StrokeStyle(lineWidth: 1.2))
                    var dots = Path()
                    for row in 0..<4 {
                        let shift = row % 2 == 0 ? 0.0 : 0.5
                        for col in 0..<3 {
                            let dx = (Double(col) - 1 + shift * 0.5) * 6.5
                            let dy = (Double(row) - 1.5) * 7
                            dots.addEllipse(in: CGRect(x: c.x + dx - 0.9, y: c.y + dy - 0.9,
                                                       width: 1.8, height: 1.8))
                        }
                    }
                    g.fill(dots, with: .color(Palette.ink.opacity(0.10)))
                }
            }
            card(x: xA, upAt: 0.10)
            card(x: xB, upAt: 0.32)

            // Gold sparkle fanning off both cards once the hearts match.
            let e = (u - 0.40) / 0.14
            if e >= 0, e < 1 {
                for (idx, x) in [xA, xB].enumerated() {
                    for k in 0..<5 {
                        let a = Double(k) / 5 * .pi + 0.3 + Double(idx) * 0.4
                        let sp = CGPoint(x: x + cos(a) * 16 * e,
                                         y: cy - 6 - sin(a) * 14 * e)
                        let sz = 1.8 * (1 - e)
                        ctx.fill(arcadeEllipse(at: sp, rx: sz, ry: sz),
                                 with: .color((k % 2 == 0 ? Palette.gold : .white)
                                     .opacity(1 - e)))
                    }
                }
            }
        }
    }
}
