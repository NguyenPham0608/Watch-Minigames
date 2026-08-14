//
//  KeepUpsHome.swift
//  Watch Minigames Watch App
//
//  Keep-Ups' home page and its juggling vignette.
//

import SwiftUI

struct KeepUpsHome: View {
    var body: some View {
        GameHome(title: "Keep-Ups") { t in
            KeepUpsScene(t: t)
        } destination: {
            KeepUpsView()
        }
    }
}

/// Little vignette: the ball juggles itself on endless arcs over the grass,
/// squashing at every kick with a spark.
private struct KeepUpsScene: View {
    let t: Double

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let floorY = size.height - 12

            // Grass strip.
            let grass = CGRect(x: cx - 58, y: floorY, width: 116,
                               height: size.height - floorY)
            ctx.fill(Path(grass), with: .color(Palette.fairway))
            var top = Path()
            top.move(to: CGPoint(x: grass.minX, y: floorY))
            top.addLine(to: CGPoint(x: grass.maxX, y: floorY))
            ctx.stroke(top, with: .color(Palette.ink),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

            // Endless juggle: |sin| arcs, drifting side to side.
            let r = 8.0
            let phase = t * 2.2
            let hop = abs(sin(phase))
            let x = cx + sin(t * 0.7) * 20
            let y = floorY - r - 2 - hop * 34
            let nearKick = hop < 0.22

            // Kick squash + spark right at the bounce.
            let squash = nearKick ? (1 - hop / 0.22) * 0.22 : 0
            if nearKick {
                let age = 1 - hop / 0.22
                for k in 0..<4 {
                    let a = Double(k) / 4 * 2 * .pi + 0.6
                    let dist = 3 + age * 8
                    let p = CGPoint(x: x + cos(a) * dist,
                                    y: floorY - 4 + sin(a) * dist * 0.5)
                    ctx.fill(arcadeEllipse(at: p, rx: 1.5 * (1 - age * 0.6),
                                           ry: 1.5 * (1 - age * 0.6)),
                             with: .color((k.isMultiple(of: 2) ? Palette.gold : .white)
                                 .opacity(0.9 * (1 - age * 0.7))))
                }
            }

            // Ground shadow tracks the ball.
            let height = hop
            ctx.fill(arcadeEllipse(at: CGPoint(x: x, y: floorY + 4),
                                   rx: r * (1 - height * 0.4),
                                   ry: r * 0.3 * (1 - height * 0.4)),
                     with: .color(Palette.shadow.opacity(1 - height * 0.4)))

            drawSoccerBall(ctx, at: CGPoint(x: x, y: y), r: r, rot: t * 1.6,
                           scaleX: 1 + squash, scaleY: 1 - squash)
        }
    }
}
