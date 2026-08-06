//
//  StackerHome.swift
//  Watch Minigames Watch App
//
//  Stacker's home page and its wobbling-tower vignette.
//

import SwiftUI

struct StackerHome: View {
    var body: some View {
        GameHome(title: "Stacker") { t in
            StackerScene(t: t)
        } destination: {
            StackerView()
        }
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
            func piece(_ kind: StackerEngine.ObjectKind, _ color: Int,
                       _ dx: Double, _ bottomY: Double, _ rotFactor: Double) {
                let spec = StackerEngine.spec(for: kind, colorIndex: color)
                var g = ctx
                g.translateBy(x: cx, y: floorY)
                g.rotate(by: Angle(radians: wob * rotFactor))
                g.translateBy(x: -cx, y: -floorY)
                StackerRenderer.drawObject(g, spec: spec, x: cx + dx, bottomY: bottomY,
                                           time: t)
            }
            piece(.box, 0, 0, floorY, 0.3)
            piece(.book, 1, 3, floorY - 32, 0.7)

            // Swaying mug overhead, clear of the tower and the frame edge.
            let mugSpec = StackerEngine.spec(for: .mug, colorIndex: 2)
            let mx = cx + sin(t * 1.6) * 34
            StackerRenderer.drawObject(ctx, spec: mugSpec, x: mx, bottomY: 25, time: t)
        }
    }
}
