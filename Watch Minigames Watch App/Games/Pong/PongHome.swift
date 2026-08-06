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

            // A real rally: triangle waves give straight-line travel with
            // sharp reflections, so the ball genuinely meets the walls and
            // each paddle face.
            func tri(_ time: Double, _ period: Double) -> Double {
                let ph = (time / period).truncatingRemainder(dividingBy: 1)
                return ph < 0.5 ? ph * 2 : 2 - ph * 2
            }
            let leftX = court.minX + 13.5, rightX = court.maxX - 13.5
            let topY = court.minY + 4.5, botY = court.maxY - 4.5
            func ballAt(_ time: Double) -> CGPoint {
                CGPoint(x: leftX + (rightX - leftX) * tri(time, 3.6),
                        y: topY + (botY - topY) * tri(time + 0.35, 1.6))
            }
            let bp = ballAt(t)

            // Squash against whatever it just hit.
            let tx = tri(t, 3.6), ty = tri(t + 0.35, 1.6)
            let sx = 1 - 0.22 * max(0, 1 - min(tx, 1 - tx) * 12)
            let sy = 1 - 0.22 * max(0, 1 - min(ty, 1 - ty) * 12)
            let ballRect = CGRect(x: bp.x - 4 * sx, y: bp.y - 4 * sy,
                                  width: 8 * sx, height: 8 * sy)
            ctx.fill(Path(ellipseIn: ballRect), with: .color(Palette.wallTop))
            ctx.stroke(Path(ellipseIn: ballRect), with: .color(Palette.ink),
                       style: StrokeStyle(lineWidth: 1.4))

            // Paddles drift lazily when the ball is far and lock on as it
            // arrives; a white flash marks each return.
            func paddle(x: Double, y: Double, color: Color, flash: Double) {
                // Clamped clear of the rounded corners so paddles never
                // poke past the court outline.
                let clamped = min(max(y, court.minY + 16), court.maxY - 16)
                let rect = CGRect(x: x - 2.5, y: clamped - 11, width: 5, height: 22)
                let p = Path(roundedRect: rect, cornerRadius: 2.5)
                ctx.fill(p, with: .color(color))
                if flash > 0 {
                    ctx.fill(p, with: .color(.white.opacity(0.45 * flash)))
                }
                ctx.stroke(p, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.3))
            }
            // Each paddle glides ease-in-out from its last return spot to
            // the next interception, arriving exactly as the ball does.
            func smooth(_ u: Double) -> Double {
                let c = min(max(u, 0), 1)
                return c * c * (3 - 2 * c)
            }
            func paddleY(contactPhase: Double) -> Double {
                let prev = ((t - contactPhase * 3.6) / 3.6).rounded(.down) * 3.6
                    + contactPhase * 3.6
                let u = smooth(((t - prev) / 3.6 - 0.3) / 0.7)
                return ballAt(prev).y + (ballAt(prev + 3.6).y - ballAt(prev).y) * u
            }
            paddle(x: court.minX + 8, y: paddleY(contactPhase: 0),
                   color: Palette.bumperCoral, flash: max(0, 1 - tx * 14))
            paddle(x: court.maxX - 8, y: paddleY(contactPhase: 0.5),
                   color: Palette.boostBlue, flash: max(0, 1 - (1 - tx) * 14))
        }
    }
}
