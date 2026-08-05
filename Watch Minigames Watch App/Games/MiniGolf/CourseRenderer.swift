//
//  CourseRenderer.swift
//  Minigames Watch App
//
//  Flat cartoon rendering: bright fills, bold ink outlines, and smooth
//  stroked wall bands (white tops over a warm gray side sliver).
//

import SwiftUI

// MARK: - Projection

/// Maps world space to screen space with a gentle "tilt toward the horizon":
/// points lower on screen scale up slightly.
struct Projection {
    var cam: Vec2
    var size: CGSize
    var zoom: Double

    func factor(_ p: Vec2) -> Double {
        let ry = (p.y - cam.y) * zoom
        return min(max(1.0 + ry * 0.0014, 0.78), 1.28)
    }

    func point(_ p: Vec2) -> CGPoint {
        let rx = (p.x - cam.x) * zoom
        let ry = (p.y - cam.y) * zoom
        let f = min(max(1.0 + ry * 0.0014, 0.78), 1.28)
        return CGPoint(x: size.width / 2 + rx * f, y: size.height / 2 + ry * f)
    }

    func length(_ l: Double, at p: Vec2) -> Double { l * zoom * factor(p) }
}

// MARK: - Renderer

struct CourseRenderer {
    let hole: HoleDesign
    let geo: FairwayGeometry
    let proj: Projection
    let time: Double

    /// Half-width of the boundary wall band, in world units.
    static let wallHalf = 5.2
    /// Wall height in world units — extruded with the perspective factor,
    /// so walls lower on screen stand visibly taller.
    static let wallHeight = 12.5
    static let inkLine = 1.6

    private var bandWidth: Double { Self.wallHalf * 2 * proj.zoom }

    // MARK: Full course

    func draw(into base: GraphicsContext, engine: GameEngine?) {
        // Hard impacts rattle the whole view for a beat.
        var ctx = base
        if let engine, engine.shakeAmp > 0.15 {
            ctx.translateBy(x: sin(time * 67) * engine.shakeAmp,
                            y: cos(time * 53) * engine.shakeAmp * 0.6)
        }

        // Flat background + a soft scrim up top so the system clock stays legible.
        ctx.fill(Path(CGRect(origin: .zero, size: proj.size)), with: .color(Palette.bg))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: proj.size.width, height: 42)),
                 with: .linearGradient(
                    Gradient(colors: [Color.black.opacity(0.28), .clear]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: 42)))

        // Boundary loops (outer edge + any enclosed pockets): even-odd fill
        // keeps pockets as background. Built with the same curve smoothing as
        // the wall bands so fill and stroke trace the identical edge.
        var ground = Path()
        for loop in geo.loops {
            ground.addPath(levelPath(loop, closed: true, t: 0, height: 0))
        }
        let evenOdd = FillStyle(eoFill: true)
        drawCourseShadow(ctx, ground)

        // Grass.
        ctx.fill(ground, with: .color(Palette.fairway), style: evenOdd)
        drawStripes(ctx, clip: ground)

        // Flat ground decals.
        for o in hole.obstacles {
            switch o.kind {
            case .sand: drawSand(ctx, o)
            case .boost: drawBoost(ctx, o)
            case .hill: drawHill(ctx, o)
            case .vortex: drawVortex(ctx, o)
            case .portal: drawPortal(ctx, o, engine: engine)
            case .flowers: drawFlowers(ctx, o)
            default: break
            }
        }

        drawCup(ctx)
        // A pulsing golden welcome while a rolling ball closes in on the cup.
        if let engine, engine.state == .rolling,
           engine.ballPos.distance(to: hole.cup) < 32 {
            let c = proj.point(hole.cup)
            let pulse = (sin(time * 6) + 1) / 2
            let r = proj.length(GameEngine.cupRadius, at: hole.cup) + 3 + pulse * 3
            ctx.stroke(ellipse(at: c, rx: r, ry: r * 0.84),
                       with: .color(Palette.gold.opacity(0.7 - pulse * 0.35)),
                       style: StrokeStyle(lineWidth: 1.8))
        }

        // --- Depth layering ---
        // A wall is a shaded flank standing at ground level with a white cap
        // on top of it. The ball rolls along the ground, so it passes in front
        // of the flank and behind the cap. Drawing those as two passes with
        // the sprites in between gives exactly that, and since each pass is
        // one continuous painting the walls can never show a seam.
        let walls = wallLines(engine: engine)
        for w in walls {
            drawExtrudedWall(ctx, worldPoints: w.pts, closed: w.closed, width: w.width,
                             height: w.height, topColor: w.topColor, phase: .flank)
        }

        var sprites: [(y: Double, draw: (GraphicsContext) -> Void)] = []
        for o in hole.obstacles {
            switch o.kind {
            case .coin:
                if engine?.collectedCoins.contains(o.id) != true {
                    sprites.append((o.pos.y, { self.drawCoin($0, o) }))
                }
            case .pillar:
                sprites.append((o.pos.y, { self.drawPillar($0, o) }))
            case .bumper:
                let flash = engine?.bumperFlash[o.id]
                sprites.append((o.pos.y, { self.drawBumper($0, o, flashTime: flash) }))
            case .spinner:
                sprites.append((o.pos.y, { self.drawSpinner($0, o) }))
            case .fan:
                sprites.append((o.pos.y, { self.drawFan($0, o) }))
            case .tree:
                sprites.append((o.pos.y, { self.drawTree($0, o) }))
            case .sand, .boost, .arcWall, .barrier, .hill, .vortex, .portal, .flowers:
                break
            }
        }
        let ballNear = engine.map { $0.ballPos.distance(to: hole.cup) < 26 } ?? false
        sprites.append((hole.cup.y + 0.1, { self.drawFlag($0, ballNear: ballNear) }))
        sprites.sort { $0.y < $1.y }

        func capPass(_ ctx: GraphicsContext) {
            for w in walls {
                drawExtrudedWall(ctx, worldPoints: w.pts, closed: w.closed, width: w.width,
                                 height: w.height, topColor: w.topColor, phase: .cap)
            }
        }

        // Split the cap layer at the ball's depth only when the ball is close
        // enough to a wall for a cap to touch it. Everywhere else a single
        // continuous cap pass runs — no split line on screen at all.
        var nearWall = false
        if let engine, engine.ballDrawScale > 0.01 {
            let near = geo.nearest(engine.ballPos)
            nearWall = near.dist > near.half - GameEngine.ballRadius - 30
        }

        if let engine, engine.ballDrawScale > 0.01, nearWall {
            let ballY = engine.ballPos.y
            for sprite in sprites where sprite.y <= ballY { sprite.draw(ctx) }

            // A cap should hide the ball only when its wall stands *in front*
            // of it. Caps are ground geometry lifted straight up, so the caps
            // of walls behind the ball all land above the screen line
            // (ball − lift): draw those first, then the ball, then the rest.
            // Complementary hard clips on identical geometry tile the screen
            // exactly, so the split can't produce seams.
            let bp = proj.point(engine.ballPos)
            let lift = proj.length(Self.wallHeight, at: engine.ballPos)
            let splitY = max(0, bp.y - lift + 2)
            // Two direct rect clips overlapping by a hair: rasterization can
            // never leave an unpainted row between the passes, and the
            // double-painted strip repeats identical opaque pixels.
            let hard = FillStyle(eoFill: false, antialiased: false)
            var behind = ctx
            behind.clip(to: Path(CGRect(x: 0, y: 0, width: proj.size.width,
                                        height: splitY)), style: hard)
            capPass(behind)

            // The ball clips to the grass so it can never spill outside the
            // course; the flank leans into the fairway, so it stays in front
            // of the shaded face.
            var ballCtx = ctx
            ballCtx.clip(to: ground, style: evenOdd)
            drawBall(ballCtx, engine: engine)

            for sprite in sprites where sprite.y > ballY { sprite.draw(ctx) }

            var front = ctx
            front.clip(to: Path(CGRect(x: 0, y: splitY - 1.5, width: proj.size.width,
                                       height: proj.size.height - splitY + 1.5)),
                       style: hard)
            capPass(front)
        } else {
            if let engine, engine.ballDrawScale > 0.01 {
                sprites.append((engine.ballPos.y, { ctx in
                    var c = ctx
                    c.clip(to: ground, style: evenOdd)
                    self.drawBall(c, engine: engine)
                }))
                sprites.sort { $0.y < $1.y }
            }
            for sprite in sprites { sprite.draw(ctx) }
            capPass(ctx)
        }

        for o in hole.obstacles where o.kind == .barrier {
            if engine?.brokenBarriers.contains(o.id) != true { drawBarrierMarks(ctx, o) }
        }

        if let engine {
            drawBallGhost(ctx, engine: engine)
            drawParticles(ctx, engine.particles)
            drawFloaters(ctx, engine.floaters)
            drawAim(ctx, engine: engine)
        }
    }

    /// Walls are taller than the ball, so a ball pressed against a wall in
    /// front of it disappears behind the cap. Show a faint silhouette through
    /// the wall so the player never loses track of it.
    private func drawBallGhost(_ ctx: GraphicsContext, engine: GameEngine) {
        guard engine.ballDrawScale > 0.9,
              engine.state == .ready || engine.state == .rolling else { return }
        let bp = engine.ballPos
        var covered = false

        let near = geo.nearest(bp)
        if near.dist > near.half - GameEngine.ballRadius - 3 {
            let outward = near.dist > 1e-6 ? (bp - near.point) / near.dist : Vec2(0, 1)
            // Contact point below the ball's center = the wall is in front.
            if (bp + outward * GameEngine.ballRadius).y >= bp.y - 1 { covered = true }
        }
        if !covered {
            outer: for o in hole.obstacles where o.kind == .arcWall || o.kind == .barrier {
                if o.kind == .barrier, engine.brokenBarriers.contains(o.id) { continue }
                let pts: [Vec2]
                if o.kind == .arcWall {
                    pts = o.arcPoints
                } else {
                    let (a, b) = o.barrierEndpoints
                    pts = [a, b]
                }
                for i in 0..<(pts.count - 1) {
                    let c = closestPointOnSegment(bp, pts[i], pts[i + 1])
                    if c.distance(to: bp) < GameEngine.ballRadius + 9, c.y >= bp.y - 1 {
                        covered = true
                        break outer
                    }
                }
            }
        }
        guard covered else { return }

        let p = proj.point(bp)
        let r = proj.length(GameEngine.ballRadius, at: bp)
        let ghost = ellipse(at: CGPoint(x: p.x, y: p.y - 1), rx: r, ry: r)
        ctx.fill(ghost, with: .color(Palette.wallTop.opacity(0.3)))
        ctx.stroke(ghost, with: .color(Palette.ink.opacity(0.4)),
                   style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
    }

    // MARK: Walls

    /// A wall the ball and other sprites can be occluded by.
    private struct WallLine {
        var pts: [Vec2]
        var closed: Bool
        var width: Double
        var height: Double
        var topColor: Color
    }

    private func wallLines(engine: GameEngine?) -> [WallLine] {
        var out = geo.loops.map {
            WallLine(pts: $0, closed: true, width: bandWidth,
                     height: Self.wallHeight, topColor: Palette.wallTop)
        }
        for o in hole.obstacles {
            switch o.kind {
            case .arcWall:
                out.append(WallLine(pts: o.arcPoints, closed: false,
                                    width: 6.5 * proj.zoom,
                                    height: Self.wallHeight * 0.85,
                                    topColor: Palette.wallTop))
            case .barrier:
                guard engine?.brokenBarriers.contains(o.id) != true else { break }
                // Subdivided so a barrier can be split by a sprite's depth line.
                let (a, b) = o.barrierEndpoints
                let pts = (0...8).map { a.lerp(to: b, Double($0) / 8) }
                var top = Palette.wallTop
                if let flash = engine?.barrierFlash[o.id], time - flash < 0.3 {
                    top = Palette.bumperCoral
                }
                out.append(WallLine(pts: pts, closed: false, width: 7.5 * proj.zoom,
                                    height: Self.wallHeight * 0.8, topColor: top))
            default:
                break
            }
        }
        return out
    }

    /// Builds the path for a wall level: each point lifted by `t` (0 = ground,
    /// 1 = full height) of its own perspective-scaled wall height.
    ///
    /// Rendered as quadratic curves through segment midpoints instead of
    /// straight lines, so the path stays perfectly smooth no matter how far
    /// the camera zooms in.
    private func levelPath(_ worldPoints: [Vec2], closed: Bool, t: Double,
                           height: Double) -> Path {
        var path = Path()
        let n = worldPoints.count
        guard n >= 2 else { return path }
        func at(_ i: Int) -> CGPoint {
            let p = worldPoints[i % n]
            let s = proj.point(p)
            return CGPoint(x: s.x, y: s.y - proj.length(height, at: p) * t)
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        if closed {
            var cur = at(0)
            path.move(to: mid(at(n - 1), cur))
            for i in 0..<n {
                let nxt = at(i + 1)
                path.addQuadCurve(to: mid(cur, nxt), control: cur)
                cur = nxt
            }
            path.closeSubpath()
        } else if n == 2 {
            path.move(to: at(0))
            path.addLine(to: at(1))
        } else {
            var cur = at(1)
            path.move(to: at(0))
            path.addLine(to: mid(at(0), cur))
            for i in 1..<(n - 1) {
                let nxt = at(i + 1)
                path.addQuadCurve(to: mid(cur, nxt), control: cur)
                cur = nxt
            }
            path.addLine(to: cur)
        }
        return path
    }

    /// Which half of a wall's extrusion to paint. `flank` is the shaded body
    /// standing on the ground (sprites are drawn over it); `cap` is the white
    /// top face (drawn over sprites).
    private enum WallPhase { case flank, cap }

    /// True 2.5D extrusion: an ink silhouette wrapping the whole solid, a
    /// stacked warm-gray flank filling ground → top, and a white top face.
    /// Round joins keep every corner smooth.
    private func drawExtrudedWall(_ ctx: GraphicsContext, worldPoints: [Vec2],
                                  closed: Bool, width: Double, height: Double,
                                  topColor: Color = Palette.wallTop,
                                  phase: WallPhase) {
        let inkStyle = StrokeStyle(lineWidth: width + Self.inkLine * 2,
                                   lineCap: .round, lineJoin: .round)
        let bandStyle = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)

        func level(_ t: Double) -> Path {
            levelPath(worldPoints, closed: closed, t: t, height: height)
        }

        switch phase {
        case .flank:
            // Solid extruded side. Every ink level is drawn first and every
            // gray level after — including the top level — so the interior is
            // a single solid gray mass and no intermediate ink margin can
            // peek through on sloped sections. Levels are packed a few pixels
            // apart so the union silhouette stays smooth instead of
            // scalloping.
            let liftPx = max(1.0, height * proj.zoom * 1.28)
            let dense = min(10, max(3, Int(liftPx / 3)))
            for i in 0...dense {
                ctx.stroke(level(Double(i) / Double(dense)),
                           with: .color(Palette.ink), style: inkStyle)
            }
            for i in 0...dense {
                ctx.stroke(level(Double(i) / Double(dense)),
                           with: .color(Palette.wallSide), style: bandStyle)
            }
        case .cap:
            // Re-ink the top outline so it stays crisp over any sprite.
            ctx.stroke(level(1), with: .color(Palette.ink), style: inkStyle)
            ctx.stroke(level(1), with: .color(topColor), style: bandStyle)
        }
    }

    private func drawCourseShadow(_ ctx: GraphicsContext, _ ground: Path) {
        var shadowPath = ground.strokedPath(StrokeStyle(lineWidth: bandWidth + 7,
                                                        lineCap: .round, lineJoin: .round))
        shadowPath.addPath(ground)
        var c = ctx
        c.translateBy(x: 3, y: 6)
        c.addFilter(.blur(radius: 3.5))
        c.fill(shadowPath, with: .color(Palette.shadow))
    }

    // MARK: Fairway stripes (horizontal cartoon bands)

    private func drawStripes(_ ctx: GraphicsContext, clip: Path) {
        var c = ctx
        c.clip(to: clip, style: FillStyle(eoFill: true))
        let bandH = 36.0
        let x0 = geo.bounds.minX - 40, x1 = geo.bounds.maxX + 40
        var k = Int(floor(geo.bounds.minY / bandH))
        var path = Path()
        while Double(k) * bandH < geo.bounds.maxY + bandH {
            defer { k += 1 }
            guard k % 2 == 0 else { continue }
            let y0 = Double(k) * bandH, y1 = y0 + bandH
            let quad = [Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)]
            path.move(to: proj.point(quad[0]))
            for p in quad.dropFirst() { path.addLine(to: proj.point(p)) }
            path.closeSubpath()
        }
        c.fill(path, with: .color(Palette.fairwayStripe))
    }

    // MARK: Obstacles

    /// Slat marks on a barrier's top face, signalling breakability. The
    /// barrier's body is drawn with the other walls.
    func drawBarrierMarks(_ ctx: GraphicsContext, _ o: Obstacle) {
        let d = Vec2(cos(o.rot), sin(o.rot))
        var marks = Path()
        for f in [-0.55, 0.0, 0.55] {
            let c = o.pos + d * (o.barrierHalfLength * f * 1.2)
            let s = proj.point(c)
            let lift = proj.length(Self.wallHeight * 0.8, at: c)
            marks.move(to: CGPoint(x: s.x - 1.6, y: s.y - lift - 1.6))
            marks.addLine(to: CGPoint(x: s.x + 1.6, y: s.y - lift + 1.6))
        }
        ctx.stroke(marks, with: .color(Palette.ink.opacity(0.55)),
                   style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }

    func drawPillar(_ ctx: GraphicsContext, _ o: Obstacle) {
        let c = proj.point(o.pos)
        let r = proj.length(o.pillarRadius, at: o.pos)
        let lift = proj.length(Self.wallHeight * 1.15, at: o.pos)
        ctx.fill(ellipse(at: CGPoint(x: c.x + 2, y: c.y + 3), rx: r * 1.12, ry: r * 0.85),
                 with: .color(Palette.shadow))
        // Column: capsule side (ground circle swept up to the top circle).
        var side = Path()
        side.addArc(center: c, radius: r,
                    startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        side.addArc(center: CGPoint(x: c.x, y: c.y - lift), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        side.closeSubpath()
        ctx.fill(side, with: .color(Palette.wallSide))
        ctx.stroke(side, with: .color(Palette.ink),
                   style: StrokeStyle(lineWidth: Self.inkLine, lineJoin: .round))
        // White top face.
        inkedEllipse(ctx, at: CGPoint(x: c.x, y: c.y - lift), rx: r, ry: r,
                     fill: Palette.wallTop)
    }

    func drawBumper(_ ctx: GraphicsContext, _ o: Obstacle, flashTime: Double?) {
        let c = proj.point(o.pos)
        var r = proj.length(o.bumperRadius, at: o.pos)
        var glow = 0.0
        if let flashTime {
            let dt = time - flashTime
            if dt < 0.3 {
                let pulse = 1 - dt / 0.3
                r *= 1 + pulse * 0.2
                glow = pulse
            }
        }
        // Life-saver ring: coral body, white band, coral center.
        ctx.fill(ellipse(at: CGPoint(x: c.x, y: c.y + 2), rx: r * 1.05, ry: r * 0.55),
                 with: .color(Palette.shadow))
        inkedEllipse(ctx, at: c, rx: r, ry: r, fill: Palette.bumperCoral)
        ctx.stroke(ellipse(at: c, rx: r * 0.58, ry: r * 0.58),
                   with: .color(Palette.wallTop),
                   style: StrokeStyle(lineWidth: r * 0.34))
        ctx.fill(ellipse(at: c, rx: r * 0.18, ry: r * 0.18),
                 with: .color(Palette.wallTop))
        if glow > 0 {
            ctx.stroke(ellipse(at: c, rx: r + 3, ry: r + 3),
                       with: .color(Color.white.opacity(glow * 0.8)),
                       style: StrokeStyle(lineWidth: 1.8))
        }
    }

    func drawSand(_ ctx: GraphicsContext, _ o: Obstacle) {
        // Smooth wobbled blob: curves through midpoints, like the walls.
        let r = o.sandRadius
        var rim: [CGPoint] = []
        for i in 0..<18 {
            let a = Double(i) / 18 * 2 * .pi
            let wobble = 1 + 0.11 * sin(a * 3 + o.seed * 12.5) + 0.04 * sin(a * 5 + o.seed * 40)
            rim.append(proj.point(o.pos + Vec2(cos(a), sin(a)) * (r * wobble)))
        }
        var blob = Path()
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        blob.move(to: mid(rim[17], rim[0]))
        for i in 0..<18 {
            blob.addQuadCurve(to: mid(rim[i], rim[(i + 1) % 18]), control: rim[i])
        }
        blob.closeSubpath()
        ctx.fill(blob, with: .color(Palette.sand))
        ctx.stroke(blob, with: .color(Palette.sandDark.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        var dots = Path()
        for i in 0..<4 {
            let a = o.seed * 71 + Double(i) * 2.9
            let rad = r * (0.2 + 0.45 * abs(sin(a * 1.7)))
            let p = proj.point(o.pos + Vec2(cos(a), sin(a)) * rad)
            dots.addEllipse(in: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4))
        }
        ctx.fill(dots, with: .color(Palette.sandDark.opacity(0.55)))
    }

    func drawBoost(_ ctx: GraphicsContext, _ o: Obstacle) {
        // Drawn in the pad's local space (origin at its center, -y = launch
        // direction) so the rounded corners and clipped chevrons stay clean
        // at any rotation.
        let s = proj.zoom * proj.factor(o.pos)
        let c = proj.point(o.pos)
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: Angle(radians: o.rot))
        g.scaleBy(x: s, y: s)

        let hw = o.boostHalfWidth, hl = o.boostHalfLength
        let rect = CGRect(x: -hw, y: -hl, width: hw * 2, height: hl * 2)
        let outer = Path(roundedRect: rect, cornerRadius: 4.5)
        g.fill(outer, with: .color(Palette.boostBlueDeep))
        g.stroke(outer, with: .color(Palette.ink),
                 style: StrokeStyle(lineWidth: Self.inkLine / s, lineJoin: .round))
        let innerRect = rect.insetBy(dx: 2.4, dy: 2.4)
        let inner = Path(roundedRect: innerRect, cornerRadius: 2.8)
        g.fill(inner, with: .color(Palette.boostBlue))

        // Chevrons flow toward the launch direction, clipped to the pad and
        // fading in at the back edge and out at the front.
        var cc = g
        cc.clip(to: inner)
        let phase = (time * 0.9).truncatingRemainder(dividingBy: 1)
        for k in 0..<3 {
            let t = (Double(k) / 3 + phase).truncatingRemainder(dividingBy: 1)
            let y = hl - t * hl * 2
            let alpha = 0.25 + 0.75 * sin(t * .pi)
            var chevron = Path()
            chevron.move(to: CGPoint(x: -hw * 0.5, y: y + 4.5))
            chevron.addLine(to: CGPoint(x: 0, y: y - 2.5))
            chevron.addLine(to: CGPoint(x: hw * 0.5, y: y + 4.5))
            cc.stroke(chevron, with: .color(.white.opacity(alpha)),
                      style: StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round))
        }
    }

    /// Grassy mound the ball rolls off — contour rings like a tiny map.
    func drawHill(_ ctx: GraphicsContext, _ o: Obstacle) {
        let c = proj.point(o.pos)
        let r = proj.length(o.hillRadius, at: o.pos)
        ctx.fill(ellipse(at: c, rx: r, ry: r * 0.9), with: .color(Palette.hillLight))
        ctx.fill(ellipse(at: c, rx: r * 0.62, ry: r * 0.56), with: .color(Palette.hillLighter))
        for f in [1.0, 0.62] {
            ctx.stroke(ellipse(at: c, rx: r * f, ry: r * f * 0.9),
                       with: .color(.white.opacity(0.45)),
                       style: StrokeStyle(lineWidth: 1.2))
        }
        ctx.fill(ellipse(at: CGPoint(x: c.x - r * 0.14, y: c.y - r * 0.2),
                         rx: r * 0.16, ry: r * 0.12),
                 with: .color(.white.opacity(0.4)))
    }

    /// Swirling depression that drags the ball toward its center.
    func drawVortex(_ ctx: GraphicsContext, _ o: Obstacle) {
        let c = proj.point(o.pos)
        let r = proj.length(o.vortexRadius, at: o.pos)
        ctx.fill(ellipse(at: c, rx: r, ry: r * 0.92), with: .color(Palette.deepGreen))
        // Spiraling arcs winding inward.
        for k in 0..<3 {
            let rr = r * (0.3 + 0.24 * Double(k))
            var arc = Path()
            let start = Angle(radians: -time * 1.8 + Double(k) * 2.1)
            arc.addArc(center: c, radius: rr, startAngle: start,
                       endAngle: start + .radians(3.6), clockwise: false)
            ctx.stroke(arc, with: .color(.white.opacity(0.42)),
                       style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
        }
        ctx.fill(ellipse(at: c, rx: r * 0.13, ry: r * 0.11),
                 with: .color(Palette.cup))
    }

    /// One-way teleport pair, hue-coded so multiple pairs stay tellable
    /// apart: the mouth is a solid disc with a spinning swirl (in), the pad a
    /// light disc with a ring and rotating dash target (out). A ridden pair
    /// is spent: it fades out and never comes back.
    func drawPortal(_ ctx: GraphicsContext, _ o: Obstacle, engine: GameEngine?) {
        var alpha = 1.0
        if let engine {
            if let fadeStart = engine.portalFadeStart[o.id] {
                alpha = max(0, 1 - (engine.time - fadeStart) / 0.45)
            }
            guard alpha > 0 else { return }
        }
        var c = ctx
        if alpha < 1 { c.opacity = alpha }
        let index = hole.obstacles.filter { $0.kind == .portal }
            .firstIndex { $0.id == o.id } ?? 0
        let hue = Palette.portalHue(index)
        drawPortalMouth(c, at: o.pos, hue: hue)
        drawPortalPad(c, at: o.portalExit, hue: hue)
    }

    private func squashed(_ ctx: GraphicsContext, around c: CGPoint,
                          by factor: Double) -> GraphicsContext {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.scaleBy(x: 1, y: factor)
        g.translateBy(x: -c.x, y: -c.y)
        return g
    }

    private func drawPortalMouth(_ ctx: GraphicsContext, at world: Vec2,
                                 hue: (main: Color, deep: Color, light: Color)) {
        let c = proj.point(world)
        let r = proj.length(10, at: world)
        let sq = 0.9
        func disc(_ rx: Double) -> Path { ellipse(at: c, rx: rx, ry: rx * sq) }

        ctx.fill(disc(r), with: .color(hue.main))
        ctx.stroke(disc(r), with: .color(Palette.ink),
                   style: StrokeStyle(lineWidth: Self.inkLine))
        ctx.fill(disc(r * 0.62), with: .color(hue.deep))
        // Spinning swirl drawing the eye inward.
        let g = squashed(ctx, around: c, by: sq)
        for k in 0..<2 {
            let rr = r * (0.32 + 0.28 * Double(k))
            let start = Angle(radians: time * 2.4 + Double(k) * 2.4)
            var arc = Path()
            arc.addArc(center: c, radius: rr, startAngle: start,
                       endAngle: start + .radians(3.2), clockwise: false)
            g.stroke(arc, with: .color(.white.opacity(0.8)),
                     style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
        ctx.fill(disc(r * 0.12), with: .color(.white))
    }

    private func drawPortalPad(_ ctx: GraphicsContext, at world: Vec2,
                               hue: (main: Color, deep: Color, light: Color)) {
        let c = proj.point(world)
        let r = proj.length(10, at: world)
        let sq = 0.9
        func disc(_ rx: Double) -> Path { ellipse(at: c, rx: rx, ry: rx * sq) }

        ctx.fill(disc(r), with: .color(hue.light))
        ctx.stroke(disc(r), with: .color(Palette.ink),
                   style: StrokeStyle(lineWidth: Self.inkLine))
        ctx.stroke(disc(r * 0.76), with: .color(hue.main),
                   style: StrokeStyle(lineWidth: 2.2))
        // Rotating dash target: "land here".
        let g = squashed(ctx, around: c, by: sq)
        var target = Path()
        target.addEllipse(in: CGRect(x: c.x - r * 0.45, y: c.y - r * 0.45,
                                     width: r * 0.9, height: r * 0.9))
        g.stroke(target, with: .color(hue.deep),
                 style: StrokeStyle(lineWidth: 1.5, dash: [3.2, 3.2],
                                    dashPhase: -time * 9))
        ctx.fill(disc(r * 0.12), with: .color(hue.deep))
    }

    /// Cheerful little flower patch. Purely decorative.
    func drawFlowers(_ ctx: GraphicsContext, _ o: Obstacle) {
        let seed = o.seed
        for i in 0..<3 {
            let a = seed * 40 + Double(i) * 2.3
            let offset = Vec2(cos(a), sin(a)) * (5.5 + 4 * Double(i % 2))
            let c = proj.point(o.pos + offset * o.scale)
            let petal = 1.6 * o.scale
            for p in 0..<5 {
                let pa = Double(p) / 5 * 2 * .pi + a
                ctx.fill(ellipse(at: CGPoint(x: c.x + cos(pa) * petal * 1.5,
                                             y: c.y + sin(pa) * petal * 1.5),
                                 rx: petal, ry: petal),
                         with: .color(.white.opacity(0.92)))
            }
            ctx.fill(ellipse(at: c, rx: petal * 0.8, ry: petal * 0.8),
                     with: .color(Palette.gold))
        }
    }

    /// Little fan unit with a spinning rotor and a drifting breeze.
    func drawFan(_ ctx: GraphicsContext, _ o: Obstacle) {
        let c = proj.point(o.pos)
        let r = proj.length(7.5 * o.scale, at: o.pos)
        let dir = o.direction

        // Breeze streaks drifting down the push zone.
        for k in 0..<3 {
            let t = (time * 0.7 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            let along = 12 * o.scale + t * (o.fanZoneLength - 20 * o.scale)
            let side = sin(Double(k) * 2.4 + time) * o.fanZoneHalfWidth * 0.45
            let p0 = o.pos + dir * along + dir.perp * side
            let p1 = p0 + dir * (9 * o.scale)
            var streak = Path()
            streak.move(to: proj.point(p0))
            streak.addLine(to: proj.point(p1))
            ctx.stroke(streak, with: .color(.white.opacity(0.55 * sin(t * .pi))),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }

        // Housing + rotor.
        ctx.fill(ellipse(at: CGPoint(x: c.x, y: c.y + 2), rx: r, ry: r * 0.5),
                 with: .color(Palette.shadow))
        inkedEllipse(ctx, at: c, rx: r, ry: r, fill: Palette.fanGray, ink: 1.4)
        var blades = Path()
        for b in 0..<3 {
            let a = time * 7 + Double(b) * (.pi * 2 / 3)
            blades.move(to: c)
            blades.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.82,
                                       y: c.y + sin(a) * r * 0.82))
        }
        ctx.stroke(blades, with: .color(.white),
                   style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        ctx.fill(ellipse(at: c, rx: r * 0.22, ry: r * 0.22), with: .color(Palette.ink))
    }

    /// Round cartoon tree; the trunk is a small solid collider.
    func drawTree(_ ctx: GraphicsContext, _ o: Obstacle) {
        let c = proj.point(o.pos)
        let s = proj.zoom * proj.factor(o.pos) * o.scale
        ctx.fill(ellipse(at: CGPoint(x: c.x + 2, y: c.y + 2.5), rx: 9 * s, ry: 4.5 * s),
                 with: .color(Palette.shadow))
        // Trunk.
        var trunk = Path()
        trunk.move(to: CGPoint(x: c.x, y: c.y))
        trunk.addLine(to: CGPoint(x: c.x, y: c.y - 13 * s))
        ctx.stroke(trunk, with: .color(Palette.ink),
                   style: StrokeStyle(lineWidth: 5.6 * s, lineCap: .round))
        ctx.stroke(trunk, with: .color(Palette.trunkBrown),
                   style: StrokeStyle(lineWidth: 3.4 * s, lineCap: .round))
        // Foliage cluster.
        let blobs: [(Double, Double, Double)] = [(-6, -14, 6.5), (6, -14, 6.5), (0, -20, 8)]
        for (dx, dy, br) in blobs {
            inkedEllipse(ctx, at: CGPoint(x: c.x + dx * s, y: c.y + dy * s),
                         rx: br * s, ry: br * s, fill: Palette.treeGreen, ink: 1.4)
        }
        ctx.fill(ellipse(at: CGPoint(x: c.x - 3 * s, y: c.y - 20 * s), rx: 2.4 * s, ry: 2 * s),
                 with: .color(.white.opacity(0.25)))
    }

    func drawSpinner(_ ctx: GraphicsContext, _ o: Obstacle) {
        let omega = 1.7
        let base = time * omega + o.seed * .pi * 2
        let c = proj.point(o.pos)
        var arms = Path()
        for arm in 0..<3 {
            let ang = base + Double(arm) * (.pi * 2 / 3)
            let tip = o.pos + Vec2(cos(ang), sin(ang)) * o.spinnerArmLength
            arms.move(to: c)
            arms.addLine(to: proj.point(tip))
        }
        var shadow = ctx
        shadow.translateBy(x: 0.5, y: 1.8)
        shadow.stroke(arms, with: .color(Palette.shadow),
                      style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
        ctx.stroke(arms, with: .color(Palette.ink),
                   style: StrokeStyle(lineWidth: 6.4, lineCap: .round))
        ctx.stroke(arms, with: .color(Palette.wallTop),
                   style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
        let hubR = proj.length(4.5, at: o.pos)
        inkedEllipse(ctx, at: c, rx: hubR, ry: hubR, fill: Palette.gold)
    }

    func drawCoin(_ ctx: GraphicsContext, _ o: Obstacle) {
        let c = proj.point(o.pos)
        let r = proj.length(o.coinRadius, at: o.pos)
        let squash = abs(sin(time * 2.4 + o.seed * 6.28))
        let rx = r * (0.3 + 0.7 * squash)
        let bob = sin(time * 2.4 + o.seed * 6.28 + 1.2) * 1.2
        ctx.fill(ellipse(at: CGPoint(x: c.x, y: c.y + 2), rx: r * 0.8, ry: r * 0.35),
                 with: .color(Palette.shadow))
        let center = CGPoint(x: c.x, y: c.y - 4 - bob)
        inkedEllipse(ctx, at: center, rx: rx, ry: r, fill: Palette.gold, ink: 1.3)
        ctx.stroke(ellipse(at: center, rx: rx * 0.6, ry: r * 0.6),
                   with: .color(Palette.goldDeep), style: StrokeStyle(lineWidth: 1.2))
    }

    // MARK: Cup, flag, ball

    func drawCup(_ ctx: GraphicsContext) {
        let c = proj.point(hole.cup)
        let r = proj.length(GameEngine.cupRadius, at: hole.cup)
        inkedEllipse(ctx, at: c, rx: r, ry: r * 0.84, fill: Palette.cup, ink: Self.inkLine)
        ctx.fill(ellipse(at: CGPoint(x: c.x, y: c.y - r * 0.1), rx: r * 0.72, ry: r * 0.55),
                 with: .color(Color.black.opacity(0.8)))
    }

    func drawFlag(_ ctx: GraphicsContext, ballNear: Bool) {
        let base = proj.point(hole.cup)
        let h = proj.length(30, at: hole.cup)
        let alpha = ballNear ? 0.35 : 1.0
        var pole = Path()
        pole.move(to: CGPoint(x: base.x, y: base.y - 1))
        pole.addLine(to: CGPoint(x: base.x, y: base.y - h))
        ctx.stroke(pole, with: .color(Palette.ink.opacity(alpha)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round))
        let wave = sin(time * 2.2) * 2.2
        var flag = Path()
        let top = CGPoint(x: base.x, y: base.y - h)
        flag.move(to: top)
        flag.addQuadCurve(
            to: CGPoint(x: base.x + 13, y: base.y - h + 4.5 + wave * 0.4),
            control: CGPoint(x: base.x + 7, y: base.y - h + 1 + wave))
        flag.addLine(to: CGPoint(x: base.x, y: base.y + 8 - h))
        flag.closeSubpath()
        ctx.fill(flag, with: .color(Palette.gold.opacity(alpha)))
        ctx.stroke(flag, with: .color(Palette.ink.opacity(alpha)),
                   style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
    }

    func drawBall(_ ctx: GraphicsContext, engine: GameEngine) {
        let p = proj.point(engine.ballPos)
        let r = proj.length(GameEngine.ballRadius, at: engine.ballPos) * engine.ballDrawScale
        guard r > 0.3 else { return }
        ctx.fill(ellipse(at: CGPoint(x: p.x, y: p.y + r * 0.55), rx: r * 1.0, ry: r * 0.45),
                 with: .color(Palette.shadow))

        // Squash against whatever it just hit; stretch along its motion.
        let speed = engine.ballVel.length
        let hit = max(0, 1 - (time - engine.lastHitAt) / 0.14)
        var g = ctx
        g.translateBy(x: p.x, y: p.y - 1)
        if hit > 0.01 {
            let n = engine.lastHitNormal
            g.rotate(by: Angle(radians: atan2(n.y, n.x)))
            let s = hit * 0.3
            g.scaleBy(x: 1 - s, y: 1 + s * 0.65)
        } else if speed > 60, engine.state == .rolling {
            g.rotate(by: Angle(radians: atan2(engine.ballVel.y, engine.ballVel.x)))
            let s = min(speed / 1500, 0.18)
            g.scaleBy(x: 1 + s, y: 1 - s * 0.7)
        }
        inkedEllipse(g, at: .zero, rx: r, ry: r, fill: Palette.wallTop, ink: Self.inkLine)
        g.fill(ellipse(at: CGPoint(x: -r * 0.3, y: -r * 0.35), rx: r * 0.26, ry: r * 0.2),
               with: .color(.white.opacity(0.9)))
    }

    /// World-anchored score popups (coin pickups, the hole's scoreline).
    func drawFloaters(_ ctx: GraphicsContext, _ floaters: [Floater]) {
        for f in floaters {
            let t = (time - f.bornAt) / 0.9
            guard t >= 0, t < 1 else { continue }
            let p = proj.point(f.pos)
            let rise = 16 * (1 - pow(1 - t, 2))
            let popIn = min(1, t * 7)
            ctx.draw(Text(f.text)
                .font(.system(size: 14 * (0.7 + 0.3 * popIn), weight: .heavy,
                              design: .rounded))
                .foregroundStyle(f.color.opacity((1 - t * t) * popIn)),
                     at: CGPoint(x: p.x, y: p.y - rise))
        }
    }

    // MARK: Aim preview & particles

    func drawAim(_ ctx: GraphicsContext, engine: GameEngine) {
        guard engine.canAim, let shot = engine.aimShot else {
            if engine.state == .ready {
                let p = proj.point(engine.ballPos)
                let pulse = (sin(time * 2.4) + 1) / 2
                let r = proj.length(GameEngine.ballRadius, at: engine.ballPos) + 3.5 + pulse * 2
                ctx.stroke(ellipse(at: CGPoint(x: p.x, y: p.y - 1), rx: r, ry: r),
                           with: .color(Palette.ink.opacity(0.4 - pulse * 0.22)),
                           style: StrokeStyle(lineWidth: 1.4))
            }
            return
        }
        let power = shot.power
        let fill: Color
        if power < 0.45 {
            fill = Palette.wallTop
        } else if power < 0.8 {
            fill = Palette.gold
        } else {
            fill = Palette.bumperCoral
        }

        // Flowing outlined dots that stream toward the target.
        let len = 34.0 + power * 58
        let spacing = 13.0
        let flow = (time * 2.0).truncatingRemainder(dividingBy: 1)
        var d = (flow - 1) * spacing + 14
        while d < len {
            defer { d += spacing }
            guard d > 6 else { continue }
            let t = d / len
            // Ease in at the ball, ease out near the arrowhead.
            let fade = min(1, min((d - 4) / 12, (len - d) / 10 + 0.4))
            guard fade > 0.05 else { continue }
            let world = engine.ballPos + shot.dir * d
            let p = proj.point(world)
            let size = (2.1 + t * 1.5) * (0.6 + 0.4 * fade)
            let dot = ellipse(at: CGPoint(x: p.x, y: p.y - 1), rx: size, ry: size)
            ctx.fill(dot, with: .color(fill.opacity(fade)))
            ctx.stroke(dot, with: .color(Palette.ink.opacity(fade)),
                       style: StrokeStyle(lineWidth: 1.1))
        }

        // Bold arrowhead at the tip.
        let tipW = engine.ballPos + shot.dir * (len + 9)
        let backW = engine.ballPos + shot.dir * (len - 3)
        let side = shot.dir.perp
        var arrow = Path()
        arrow.move(to: proj.point(tipW))
        arrow.addLine(to: proj.point(backW + side * 5.5))
        arrow.addLine(to: proj.point(backW + shot.dir * 2.5))
        arrow.addLine(to: proj.point(backW - side * 5.5))
        arrow.closeSubpath()
        ctx.fill(arrow, with: .color(fill))
        ctx.stroke(arrow, with: .color(Palette.ink),
                   style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))

        // Power ring around the ball.
        let p = proj.point(engine.ballPos)
        let r = proj.length(GameEngine.ballRadius, at: engine.ballPos) + 4.5
        var track = Path()
        track.addEllipse(in: CGRect(x: p.x - r, y: p.y - 1 - r, width: r * 2, height: r * 2))
        ctx.stroke(track, with: .color(Palette.ink.opacity(0.25)),
                   style: StrokeStyle(lineWidth: 2.4))
        var arc = Path()
        arc.addArc(center: CGPoint(x: p.x, y: p.y - 1), radius: r,
                   startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * power),
                   clockwise: false)
        ctx.stroke(arc, with: .color(fill), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        ctx.stroke(arc, with: .color(Palette.ink.opacity(0.5)),
                   style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
    }

    func drawParticles(_ ctx: GraphicsContext, _ particles: [Particle]) {
        guard !particles.isEmpty else { return }
        for particle in particles {
            let a = max(0, particle.life / particle.maxLife)
            let p = proj.point(particle.pos)
            let s = particle.size
            let color: Color
            switch particle.hue {
            case .gold: color = Palette.gold
            case .shard: color = Palette.wallTop
            case .grass: color = Palette.fairwayStripe
            case .white: color = .white
            case .confetti(let i):
                color = Palette.confettiColors[i % Palette.confettiColors.count]
            }
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)),
                     with: .color(color.opacity(a)))
        }
    }

    // MARK: Path helpers

    private func ellipse(at c: CGPoint, rx: Double, ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
    }

    private func inkedEllipse(_ ctx: GraphicsContext, at c: CGPoint, rx: Double, ry: Double,
                              fill: Color, ink: Double = 1.6) {
        let path = ellipse(at: c, rx: rx, ry: ry)
        ctx.fill(path, with: .color(fill))
        ctx.stroke(path, with: .color(Palette.ink), style: StrokeStyle(lineWidth: ink))
    }
}
