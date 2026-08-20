//
//  ArcadeDraw.swift
//  Watch Minigames Watch App
//
//  Canvas helpers the arcade renderers share: screen shake, timing curves,
//  the particle hue table, and the ball/trail/paddle trio Pong and Bricks
//  both draw.
//

import SwiftUI

/// Screen-shake offset for the current frame; renderers translate by it
/// while the engine's `shakeAmp` rings down.
func shakeOffset(time: Double, amp: Double) -> CGSize {
    CGSize(width: sin(time * 67) * amp, height: cos(time * 53) * amp * 0.6)
}

/// 1 → 0 decay over `dur` seconds since `since`.
func decay(_ since: Double, _ dur: Double, now: Double) -> Double {
    max(0, 1 - (now - since) / dur)
}

/// Ease with a small overshoot (`s`) so things land with a spring.
func easeOutBack(_ t: Double, _ s: Double = 0.9) -> Double {
    let u = min(max(t, 0), 1) - 1
    return 1 + u * u * ((s + 1) * u + s)
}

/// The shared hue table for particles. `shard` varies by scene — warm gray
/// indoors, wall white on the fairway.
func particleColor(_ hue: Particle.ParticleHue, shard: Color) -> Color {
    switch hue {
    case .gold: return Palette.gold
    case .shard: return shard
    case .grass: return Palette.fairwayStripe
    case .white: return .white
    case .confetti(let i):
        return Palette.confettiColors[i % Palette.confettiColors.count]
    }
}

// MARK: - Ball, trail and paddle (shared by Pong and Bricks)

/// Ground-shadow ellipse under a ball of radius `r`.
func drawBallShadow(_ ctx: GraphicsContext, at c: CGPoint, r: Double) {
    ctx.fill(arcadeEllipse(at: CGPoint(x: c.x, y: c.y + r * 0.9), rx: r * 0.95, ry: r * 0.4),
             with: .color(Palette.shadow))
}

/// The inked arcade ball: squash on impact, stretch with speed, drawn in a
/// frame aligned to the velocity when `rotates`, with a white highlight.
func drawArcadeBall(_ ctx: GraphicsContext, at c: CGPoint, r: Double, vel: Vec2,
                    stretch: Double, squash: Double, fill: Color, rotates: Bool) {
    var g = ctx
    g.translateBy(x: c.x, y: c.y)
    if rotates { g.rotate(by: Angle(radians: atan2(vel.y, vel.x))) }
    g.scaleBy(x: 1 + stretch - squash, y: 1 - (stretch - squash) * 0.7)
    g.fill(arcadeEllipse(at: .zero, rx: r, ry: r), with: .color(fill))
    g.stroke(arcadeEllipse(at: .zero, rx: r, ry: r), with: .color(Palette.ink),
             style: StrokeStyle(lineWidth: 1.5))
    g.fill(arcadeEllipse(at: CGPoint(x: -r * 0.3, y: -r * 0.35), rx: r * 0.24, ry: r * 0.2),
           with: .color(.white.opacity(0.9)))
}

/// Tapered ribbon trail: stacked round-cap segments thinning toward the
/// tail, alpha climbing with f² toward the head.
func drawTaperedTrail(_ ctx: GraphicsContext, points: [Vec2], color: Color,
                      alphaBase: Double, alphaGain: Double, width: Double,
                      origin: CGPoint = .zero) {
    for i in points.indices.dropFirst() {
        let f = Double(i) / Double(points.count)
        var seg = Path()
        seg.move(to: CGPoint(x: origin.x + points[i - 1].x, y: origin.y + points[i - 1].y))
        seg.addLine(to: CGPoint(x: origin.x + points[i].x, y: origin.y + points[i].y))
        ctx.stroke(seg, with: .color(color.opacity(alphaBase + alphaGain * f * f)),
                   style: StrokeStyle(lineWidth: width * f, lineCap: .round))
    }
}

/// A cheap halo around a shape's outline: two flat strokes at falling
/// opacity instead of a blur filter. On watchOS, `addFilter(.blur)` forces
/// Canvas to rasterize to an offscreen buffer and run a real convolution —
/// by far the most expensive thing these renderers can do per frame, and one
/// that stacks badly when several shapes each want a soft edge in the same
/// frame. Two extra flat fills read the same at arcade scale for a fraction
/// of the cost.
func drawGlowStroke(_ ctx: GraphicsContext, shape: Path, color: Color, opacity: Double) {
    guard opacity > 0.01 else { return }
    ctx.fill(shape.strokedPath(StrokeStyle(lineWidth: 7)), with: .color(color.opacity(opacity * 0.3)))
    ctx.fill(shape.strokedPath(StrokeStyle(lineWidth: 3.5)), with: .color(color.opacity(opacity * 0.6)))
}

/// The inked capsule paddle: soft shadow, optional smash aura, body, inner
/// core stripe, ink, and a white flash (`flash` 1 → just hit) at `flashAlpha`.
func drawArcadePaddle(_ ctx: GraphicsContext, rect: CGRect, fill: Color, core: Color,
                      vertical: Bool, flash: Double, flashAlpha: Double,
                      glowOpacity: Double? = nil) {
    let shape = Path(roundedRect: rect,
                     cornerRadius: (vertical ? rect.width : rect.height) / 2)
    var sh = ctx
    sh.translateBy(x: 1.2, y: 2)
    sh.fill(shape, with: .color(Palette.shadow))
    if let glowOpacity {
        drawGlowStroke(ctx, shape: shape, color: Palette.gold, opacity: glowOpacity)
    }
    ctx.fill(shape, with: .color(fill))
    var stripe = Path()
    if vertical {
        stripe.move(to: CGPoint(x: rect.midX, y: rect.minY + 4))
        stripe.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 4))
    } else {
        stripe.move(to: CGPoint(x: rect.minX + 4, y: rect.midY))
        stripe.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.midY))
    }
    ctx.stroke(stripe, with: .color(core), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
    ctx.stroke(shape, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.5))
    if flash > 0 {
        ctx.fill(shape, with: .color(.white.opacity(flash * flashAlpha)))
    }
}
