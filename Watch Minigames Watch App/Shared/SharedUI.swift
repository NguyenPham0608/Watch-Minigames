//
//  SharedUI.swift
//  Watch Minigames Watch App
//
//  Chrome shared by the arcade games: the home-page layout, the
//  end-of-round card and floating score popups — all in the golf game's
//  inked cartoon style.
//

import SwiftUI

/// Home page: animated vignette, title, gold Play capsule, and an optional
/// accessory row (difficulty slider, extra buttons) below the capsule.
struct GameHome<SceneContent: View, Destination: View, Accessory: View>: View {
    let title: String
    var sceneHeight: Double = 88
    var spacing: Double = 8
    @ViewBuilder var scene: (Double) -> SceneContent
    @ViewBuilder var destination: () -> Destination
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(spacing: spacing) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                scene(timeline.date.timeIntervalSinceReferenceDate)
            }
            // The vignette is the one compressible row: on short screens
            // (40mm) the stack shrinks it toward 64 so the title, Play and
            // accessory never spill off the bottom; larger watches always
            // get the full sceneHeight.
            .frame(minHeight: 64, idealHeight: sceneHeight, maxHeight: sceneHeight)

            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)

            NavigationLink {
                destination()
            } label: {
                CapsuleActionLabel(text: "Play")
            }
            .buttonStyle(BouncyButtonStyle())

            accessory()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // The same dotted paper the games play on, so the whole app
            // reads as one sheet.
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Palette.bg))
                drawWallpaperDots(ctx, size: size)
            }
            .ignoresSafeArea()
        }
    }
}

extension GameHome where Accessory == EmptyView {
    init(title: String, sceneHeight: Double = 88, spacing: Double = 8,
         @ViewBuilder scene: @escaping (Double) -> SceneContent,
         @ViewBuilder destination: @escaping () -> Destination) {
        self.init(title: title, sceneHeight: sceneHeight, spacing: spacing,
                  scene: scene, destination: destination, accessory: { EmptyView() })
    }
}

/// The inked capsule used by home-page action buttons: gold primary by
/// default; `compact` and `whiteFill` cover the secondary variants.
struct CapsuleActionLabel: View {
    let text: String
    var compact = false
    var whiteFill = false

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 13 : 15,
                          weight: compact ? .semibold : .bold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 7 : 8)
            .background(Capsule().fill(whiteFill ? AnyShapeStyle(Color.white.opacity(0.92))
                                                 : AnyShapeStyle(Palette.gold)))
            .overlay(Capsule().stroke(Palette.ink, lineWidth: whiteFill ? 1.4 : 1.6))
            .foregroundStyle(Palette.ink)
    }
}

/// Defers a NavigationLink destination until it is actually pushed — keeps
/// heavyweight inits (GolfView builds full course geometry) out of
/// home-page body evaluations.
struct LazyView<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { content() }
}

/// Press feedback for every arcade button: a quick squash that springs back.
struct BouncyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55),
                       value: configuration.isPressed)
    }
}

extension Animation {
    /// The house pop: cards and chips scale in with a springy overshoot.
    static let arcadePop = Animation.spring(response: 0.38, dampingFraction: 0.62)
}

/// Circular icon button used on the result cards: gold when prominent,
/// white otherwise, inked either way.
struct OverlayCircleButton: View {
    let symbol: String
    var prominent = false
    var fontSize = 15.0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: fontSize, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(prominent ? Palette.gold : Color.white))
                .overlay(Circle().stroke(Palette.ink, lineWidth: 1.6))
                .foregroundStyle(Palette.ink)
        }
        .buttonStyle(BouncyButtonStyle())
    }
}

/// End-of-round card: headline, best line, an optional gold detail line, and
/// a button row — replay + home by default, or a custom row via `buttons`.
struct ResultCard<Buttons: View>: View {
    let title: String
    let subtitle: String
    var titleGold = false
    var subtitleGold = false
    var subtitleSize = 12.0
    var subtitleSemibold = false
    var detail: String? = nil
    var horizontalPadding = 18.0
    @ViewBuilder var buttons: () -> Buttons

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(titleGold ? Palette.goldDeep : Palette.ink)
            Text(subtitle)
                .font(.system(size: subtitleSize,
                              weight: subtitleGold || subtitleSemibold ? .semibold : .regular,
                              design: .rounded))
                .foregroundStyle(subtitleGold ? Palette.goldDeep
                                 : Palette.ink.opacity(0.55))
            if let detail {
                Text(detail)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.goldDeep)
            }
            HStack(spacing: 10) {
                buttons()
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, horizontalPadding)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.ink, lineWidth: 1.8))
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
    }
}

/// The standard replay + home row on `ResultCard`.
struct ResultCardButtons: View {
    @Environment(\.dismiss) private var dismiss
    let onReplay: () -> Void

    var body: some View {
        OverlayCircleButton(symbol: "arrow.counterclockwise", prominent: true,
                            action: onReplay)
        OverlayCircleButton(symbol: "house.fill", fontSize: 14) { dismiss() }
    }
}

extension ResultCard where Buttons == ResultCardButtons {
    init(title: String, subtitle: String, titleGold: Bool = false,
         subtitleGold: Bool = false, subtitleSize: Double = 12,
         subtitleSemibold: Bool = false, onReplay: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, titleGold: titleGold,
                  subtitleGold: subtitleGold, subtitleSize: subtitleSize,
                  subtitleSemibold: subtitleSemibold) {
            ResultCardButtons(onReplay: onReplay)
        }
    }
}

// MARK: - Glass score chip

/// Liquid glass capsule behind HUD chips.
struct GlassChip: ViewModifier {
    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: Capsule())
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
        let color = particleColor(particle.hue, shard: Palette.wallSide)
        let r = particle.size / 2 + 0.6
        ctx.fill(arcadeEllipse(at: c, rx: r * 2, ry: r * 2), with: .color(color.opacity(a * 0.18)))
        ctx.fill(arcadeEllipse(at: c, rx: r, ry: r), with: .color(color.opacity(a)))
    }
}
