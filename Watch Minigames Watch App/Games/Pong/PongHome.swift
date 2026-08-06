//
//  PongHome.swift
//  Watch Minigames Watch App
//
//  Super Pong's home page, difficulty slider, and rally vignette.
//

import SwiftUI

struct PongHome: View {
    @Environment(ScoreStore.self) private var store

    var body: some View {
        GameHome(title: "Super Pong") { t in
            PongScene(t: t)
        } destination: {
            PongView()
        } accessory: {
            VStack(spacing: 3) {
                // Bot difficulty.
                DifficultySlider()
                    .padding(.horizontal, 18)
                if store.pongWins > 0 {
                    Text("\(store.pongWins) \(store.pongWins == 1 ? "win" : "wins")")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.55))
                }
            }
        }
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
