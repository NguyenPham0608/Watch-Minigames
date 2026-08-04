//
//  SharedUI.swift
//  Minigames Watch App
//
//  Chrome shared by the arcade games: the home-page layout, the
//  end-of-round card and floating score popups — all in the golf game's
//  inked cartoon style.
//

import SwiftUI

/// Home page: animated vignette, title, gold Play capsule.
struct GameHome<Scene: View, Destination: View>: View {
    let title: String
    @ViewBuilder var scene: (Double) -> Scene
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                scene(timeline.date.timeIntervalSinceReferenceDate)
            }
            .frame(height: 88)

            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)

            NavigationLink {
                destination()
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

/// End-of-round card: headline, best line, replay + home buttons.
struct ResultCard: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    var titleGold = false
    var subtitleGold = false
    let onReplay: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(titleGold ? Palette.goldDeep : Palette.ink)
            Text(subtitle)
                .font(.system(size: 12, weight: subtitleGold ? .semibold : .regular,
                              design: .rounded))
                .foregroundStyle(subtitleGold ? Palette.goldDeep
                                 : Palette.ink.opacity(0.55))
            HStack(spacing: 10) {
                Button(action: onReplay) {
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

// MARK: - Glass score chip

/// Liquid glass where the OS provides it, frosted capsule where it doesn't.
struct GlassChip: ViewModifier {
    func body(content: Content) -> some View {
        if #available(watchOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Palette.ink.opacity(0.22), lineWidth: 1))
        }
    }
}

/// Score number in a glass chip; `flash` (1 → just scored) pops the scale.
/// Game objects pass behind it and blur instead of colliding with digits.
struct ScoreChip: View {
    let score: Int
    var flash: Double = 0

    var body: some View {
        Text("\(score)")
            .font(.system(size: 19, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Palette.ink.opacity(0.9))
            .padding(.horizontal, 11)
            .padding(.vertical, 3)
            .modifier(GlassChip())
            .scaleEffect(1 + flash * 0.12)
    }
}

// MARK: - Floating score popups

struct Floater {
    var pos: Vec2
    var text: String
    var bornAt: Double
    var color: Color
}

/// Draws popups rising and fading over 0.8s. Engines prune expired ones.
func drawFloaters(_ ctx: GraphicsContext, _ floaters: [Floater], time: Double) {
    for f in floaters {
        let t = (time - f.bornAt) / 0.8
        guard t >= 0, t < 1 else { continue }
        let rise = 14 * (1 - pow(1 - t, 2))
        ctx.draw(Text(f.text)
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(f.color.opacity(1 - t * t)),
                 at: CGPoint(x: f.pos.x, y: f.pos.y - rise))
    }
}

// MARK: - Small canvas helpers shared by the arcade renderers

func arcadeEllipse(at c: CGPoint, rx: Double, ry: Double) -> Path {
    Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
}

func arcadeInkedEllipse(_ ctx: GraphicsContext, at c: CGPoint, rx: Double, ry: Double,
                        fill: Color, ink: Double = 1.5) {
    let path = arcadeEllipse(at: c, rx: rx, ry: ry)
    ctx.fill(path, with: .color(fill))
    ctx.stroke(path, with: .color(Palette.ink), style: StrokeStyle(lineWidth: ink))
}

/// Wallpaper dots (the stacker's living-room texture) — quiet depth for
/// indoor-feeling games.
func drawWallpaperDots(_ ctx: GraphicsContext, size: CGSize) {
    var dots = Path()
    let spacing = 44.0
    var y = 0.0
    var row = 0
    while y < size.height + spacing {
        let shift = (row % 2 == 0) ? 0.0 : spacing / 2
        var x = shift
        while x < size.width {
            dots.addEllipse(in: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8))
            x += spacing
        }
        y += spacing
        row += 1
    }
    ctx.fill(dots, with: .color(Palette.ink.opacity(0.06)))
}

/// Soft scrim so the system clock stays legible over any scene.
func drawClockScrim(_ ctx: GraphicsContext, size: CGSize) {
    ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 42)),
             with: .linearGradient(
                Gradient(colors: [Color.black.opacity(0.28), .clear]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: 42)))
}

/// Shared particle pass: soft halo under each spark so bursts don't feel flat.
func drawArcadeParticles(_ ctx: GraphicsContext, _ particles: [Particle]) {
    for particle in particles {
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
        ctx.fill(arcadeEllipse(at: c, rx: r * 2, ry: r * 2), with: .color(color.opacity(a * 0.18)))
        ctx.fill(arcadeEllipse(at: c, rx: r, ry: r), with: .color(color.opacity(a)))
    }
}
