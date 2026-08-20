//
//  FairwayGeometry.swift
//  Watch Minigames Watch App
//
//  Spline sampling and fairway boundary construction for Mini Golf.
//

import CoreGraphics
import Foundation

// MARK: - Centripetal Catmull-Rom

/// Centripetal parameterization: unlike the uniform variant it can never form
/// loops or cusps between control points, so bunched-up editor waypoints stay
/// tame instead of curling into knots.
private func crCentripetal(_ p0: Vec2, _ p1: Vec2, _ p2: Vec2, _ p3: Vec2,
                           _ t: Double) -> Vec2 {
    let t0 = 0.0
    let t1 = t0 + max(pow(p0.distance(to: p1), 0.5), 0.12)
    let t2 = t1 + max(pow(p1.distance(to: p2), 0.5), 0.12)
    let t3 = t2 + max(pow(p2.distance(to: p3), 0.5), 0.12)
    let tt = t1 + (t2 - t1) * t

    func mix(_ a: Vec2, _ b: Vec2, _ ta: Double, _ tb: Double) -> Vec2 {
        let d = tb - ta
        guard abs(d) > 1e-9 else { return a }
        let u = (tt - ta) / d
        return a * (1 - u) + b * u
    }

    let a1 = mix(p0, p1, t0, t1)
    let a2 = mix(p1, p2, t1, t2)
    let a3 = mix(p2, p3, t2, t3)
    let b1 = mix(a1, a2, t0, t2)
    let b2 = mix(a2, a3, t1, t3)
    return mix(b1, b2, t1, t2)
}

private func smoothstep(_ t: Double) -> Double { t * t * (3 - 2 * t) }

// MARK: - Fairway geometry

/// The playable surface: one or more smooth centerlines, each swept by a
/// variable-radius disk. Extra paths ("islands") can sit anywhere — even
/// fully detached from the main fairway — and the union field handles them
/// exactly like overlapping bends: physics, boundary tracing and rendering
/// all read the same definition, so detached land simply appears as its own
/// walled loop.
struct FairwayGeometry {
    /// Closed boundary loops: the outer edge of every piece of land, plus any
    /// enclosed pockets.
    let loops: [[Vec2]]
    let bounds: CGRect

    /// Flat list of centerline segments across every path. Physics and
    /// projection query these directly; explicit segments mean detached
    /// islands never grow phantom bridges between path ends.
    private let segA: [Vec2]
    private let segB: [Vec2]
    private let segH0: [Double]
    private let segH1: [Double]
    /// Per-segment values `nearest` would otherwise recompute on every call:
    /// the segment vector, its squared length, and its length.
    private let segAB: [Vec2]
    private let segLen2: [Double]
    private let segLen: [Double]

    init(paths rawPaths: [[Waypoint]]) {
        // --- Sample every path's centerline ---
        var sampled: [([Vec2], [Double])] = []
        for waypoints in rawPaths {
            if let s = Self.samplePath(waypoints) { sampled.append(s) }
        }
        if sampled.isEmpty {
            sampled = [([Vec2(150, 340), Vec2(150, 260)], [36, 36])]
        }

        // --- Segment soup + decimated copies for the contour grid ---
        var segA: [Vec2] = [], segB: [Vec2] = []
        var segH0: [Double] = [], segH1: [Double] = []
        var gridA: [Vec2] = [], gridB: [Vec2] = []
        var gridH0: [Double] = [], gridH1: [Double] = []
        for (c, h) in sampled {
            for i in 0..<(c.count - 1) {
                segA.append(c[i]); segB.append(c[i + 1])
                segH0.append(h[i]); segH1.append(h[i + 1])
            }
            var i = 0
            while i < c.count - 1 {
                let j = min(i + 3, c.count - 1)
                gridA.append(c[i]); gridB.append(c[j])
                gridH0.append(h[i]); gridH1.append(h[j])
                i = j
            }
        }
        let nSeg = segA.count

        // --- Signed distance field on a grid ---
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for i in 0..<gridA.count {
            let r = max(gridH0[i], gridH1[i])
            minX = min(minX, min(gridA[i].x, gridB[i].x) - r)
            maxX = max(maxX, max(gridA[i].x, gridB[i].x) + r)
            minY = min(minY, min(gridA[i].y, gridB[i].y) - r)
            maxY = max(maxY, max(gridA[i].y, gridB[i].y) + r)
        }
        // Adaptive resolution: enormous courses trace on a coarser grid so
        // editor drags stay responsive — re-projection below pins the contour
        // to the exact boundary regardless of cell size.
        let dim = max(maxX - minX, maxY - minY)
        let cell = min(12.0, max(4.0, dim / 130))
        let ox = minX - cell * 3, oy = minY - cell * 3
        let nx = Int(ceil((maxX - ox) / cell)) + 4
        let ny = Int(ceil((maxY - oy) / cell)) + 4

        var field = [Double](repeating: 1e6, count: nx * ny)
        for s in 0..<gridA.count {
            let a = gridA[s], b = gridB[s]
            let h0 = gridH0[s], h1 = gridH1[s]
            let reach = max(h0, h1) + cell * 2
            let i0 = max(0, Int((min(a.x, b.x) - reach - ox) / cell))
            let i1 = min(nx - 1, Int((max(a.x, b.x) + reach - ox) / cell) + 1)
            let j0 = max(0, Int((min(a.y, b.y) - reach - oy) / cell))
            let j1 = min(ny - 1, Int((max(a.y, b.y) + reach - oy) / cell) + 1)
            guard i0 <= i1, j0 <= j1 else { continue }
            let ab = b - a
            let len2 = max(ab.lengthSquared, 1e-9)
            for j in j0...j1 {
                let py = oy + Double(j) * cell
                for i in i0...i1 {
                    let p = Vec2(ox + Double(i) * cell, py)
                    let t = max(0, min(1, (p - a).dot(ab) / len2))
                    let c = a + ab * t
                    let h = h0 + (h1 - h0) * t
                    let v = c.distance(to: p) - h
                    let idx = j * nx + i
                    if v < field[idx] { field[idx] = v }
                }
            }
        }
        for k in field.indices where abs(field[k]) < 1e-9 { field[k] = -1e-9 }

        // --- Trace the zero contour ---
        let rawLoops = Self.marchingSquares(field, nx: nx, ny: ny, ox: ox, oy: oy, cell: cell)

        /// Best branch (by the union metric) among `candidates`.
        func bestIn(_ candidates: Range<Int>, _ p: Vec2) -> (score: Double, c: Vec2, h: Double) {
            var bestScore = Double.infinity
            var bestC = p
            var bestH = 0.0
            for i in candidates {
                let c = closestPointOnSegment(p, segA[i], segB[i])
                let d = c.distance(to: p)
                let segLen = segA[i].distance(to: segB[i])
                let t = segLen > 1e-6 ? c.distance(to: segA[i]) / segLen : 0
                let h = segH0[i] + (segH1[i] - segH0[i]) * t
                if d - h < bestScore { bestScore = d - h; bestC = c; bestH = h }
            }
            return (bestScore, bestC, bestH)
        }

        func place(_ p: Vec2, _ found: (score: Double, c: Vec2, h: Double)) -> Vec2 {
            let dir = p - found.c
            let len = dir.length
            guard len > 1e-6 else { return p }
            return found.c + dir * (found.h / len)
        }

        /// Projects every loop point onto the boundary. Full scans run only at
        /// sparse anchors; points in between search windows around their two
        /// neighboring anchors' branches — covering the crease where one
        /// branch hands over to another — so long courses stay fast.
        func projectLoop(_ pts: [Vec2]) -> [Vec2] {
            let stride = 8
            var anchors: [Int] = []
            var a = 0
            while a < pts.count {
                var bestI = 0
                var bestScore = Double.infinity
                for i in 0..<nSeg {
                    let c = closestPointOnSegment(pts[a], segA[i], segB[i])
                    let d = c.distance(to: pts[a])
                    let segLen = segA[i].distance(to: segB[i])
                    let t = segLen > 1e-6 ? c.distance(to: segA[i]) / segLen : 0
                    let h = segH0[i] + (segH1[i] - segH0[i]) * t
                    if d - h < bestScore { bestScore = d - h; bestI = i }
                }
                anchors.append(bestI)
                a += stride
            }
            var out = pts
            for i in 0..<pts.count {
                let left = anchors[i / stride]
                let right = anchors[(i / stride + 1) % anchors.count]
                let w = 12
                let r1 = max(0, left - w)..<min(nSeg, left + w + 1)
                let r2 = max(0, right - w)..<min(nSeg, right + w + 1)
                var found = bestIn(r1, pts[i])
                let alt = bestIn(r2, pts[i])
                if alt.score < found.score { found = alt }
                out[i] = place(pts[i], found)
            }
            return out
        }

        var loops: [[Vec2]] = []
        for raw in rawLoops {
            guard raw.count >= 6 else { continue }
            var pts = Self.resampleClosed(raw, spacing: 3.5)
            guard pts.count >= 10 else { continue }
            // Converge to the true boundary...
            for _ in 0..<3 {
                pts = Self.smoothClosed(pts, strength: 1.0)
                pts = projectLoop(pts)
            }
            // ...then hand the renderer points that are BOTH evenly spaced and
            // exactly on the curve: uneven spacing is what read as wavy walls.
            pts = Self.resampleClosed(pts, spacing: 3.0)
            guard pts.count >= 10 else { continue }
            pts = projectLoop(pts)
            loops.append(pts)
        }
        if loops.isEmpty {
            let c = segA[0], r = segH0[0]
            loops = [(0..<16).map { c + Vec2(cos(Double($0) / 16 * 2 * .pi),
                                             sin(Double($0) / 16 * 2 * .pi)) * r }]
        }

        var bMinX = Double.infinity, bMinY = Double.infinity
        var bMaxX = -Double.infinity, bMaxY = -Double.infinity
        for loop in loops {
            for p in loop {
                bMinX = min(bMinX, p.x); bMaxX = max(bMaxX, p.x)
                bMinY = min(bMinY, p.y); bMaxY = max(bMaxY, p.y)
            }
        }

        var segAB: [Vec2] = [], segLen2: [Double] = [], segLen: [Double] = []
        segAB.reserveCapacity(segA.count)
        segLen2.reserveCapacity(segA.count)
        segLen.reserveCapacity(segA.count)
        for i in 0..<segA.count {
            let ab = segB[i] - segA[i]
            segAB.append(ab)
            segLen2.append(ab.lengthSquared)
            segLen.append(segA[i].distance(to: segB[i]))
        }

        self.loops = loops
        self.segA = segA
        self.segB = segB
        self.segH0 = segH0
        self.segH1 = segH1
        self.segAB = segAB
        self.segLen2 = segLen2
        self.segLen = segLen
        self.bounds = CGRect(x: bMinX, y: bMinY, width: bMaxX - bMinX, height: bMaxY - bMinY)
    }

    /// Sampled centerline + half-widths for one waypoint path.
    private static func samplePath(_ waypoints: [Waypoint]) -> ([Vec2], [Double])? {
        guard !waypoints.isEmpty else { return nil }
        let pts = waypoints.map(\.pos)
        let ws = waypoints.map { max(28.0, $0.width) }

        var center: [Vec2] = []
        var widths: [Double] = []
        if pts.count < 2 {
            let p = pts[0]
            center = [p + Vec2(0, 40), p - Vec2(0, 40)]
            widths = [ws[0], ws[0]]
        } else {
            let n = pts.count
            for i in 0..<(n - 1) {
                let p1 = pts[i], p2 = pts[i + 1]
                // Mirrored ghost points give natural, straight run-outs.
                let p0 = i > 0 ? pts[i - 1] : p1 * 2 - p2
                let p3 = i + 2 < n ? pts[i + 2] : p2 * 2 - p1
                // Sample by arc length so stretched sections stay dense —
                // the boundary projects onto this polyline and would pick up
                // scalloping from a sparse target.
                let perSeg = min(64, max(10, Int(p1.distance(to: p2) / 6)))
                for s in 0..<perSeg {
                    let t = Double(s) / Double(perSeg)
                    center.append(crCentripetal(p0, p1, p2, p3, t))
                    widths.append(ws[i] + (ws[i + 1] - ws[i]) * smoothstep(t))
                }
            }
            center.append(pts[n - 1])
            widths.append(ws[n - 1])
        }

        // Drop nearly-duplicate consecutive samples. Both arrays are seeded
        // with a first element, so the `.last!` reads below always succeed.
        var cleanC: [Vec2] = [center[0]]
        var cleanW: [Double] = [widths[0]]
        for i in 1..<center.count where center[i].distance(to: cleanC.last!) > 0.6 {
            cleanC.append(center[i])
            cleanW.append(widths[i])
        }
        if cleanC.count < 2 {
            cleanC.append(center.last! + Vec2(0, -1))
            cleanW.append(widths.last!)
        }
        return (cleanC, cleanW.map { $0 / 2 })
    }

    // MARK: Queries

    /// Closest centerline branch by the union field (distance minus local
    /// half-width) — the same rule the drawn boundary is traced from. Always
    /// scans every segment: on looped or multi-island courses the governing
    /// branch can be anywhere.
    func nearest(_ p: Vec2) -> (point: Vec2, dist: Double, half: Double) {
        var bestScore = Double.infinity
        var bestP = segA[0]
        var bestD = Double.infinity
        var bestH = segH0[0]
        for i in 0..<segA.count {
            // closestPointOnSegment with the segment vector and lengths
            // hoisted to init — the formula (and its results) unchanged.
            let a = segA[i]
            let len2 = segLen2[i]
            var c = a
            if len2 > 1e-9 {
                let ab = segAB[i]
                let u = max(0, min(1, (p - a).dot(ab) / len2))
                c = a + ab * u
            }
            let d = c.distance(to: p)
            let len = segLen[i]
            let t = len > 1e-6 ? c.distance(to: a) / len : 0
            let h = segH0[i] + (segH1[i] - segH0[i]) * t
            if d - h < bestScore {
                bestScore = d - h
                bestP = c; bestD = d; bestH = h
            }
        }
        return (bestP, bestD, bestH)
    }

    func contains(_ p: Vec2) -> Bool {
        let n = nearest(p)
        return n.dist <= n.half
    }

    /// Nearest centerline point — used to rescue a ball that escaped or to
    /// clamp editor-placed tees/cups back onto grass.
    func nearestCenterPoint(to p: Vec2) -> Vec2 {
        nearest(p).point
    }

    // MARK: Contour extraction

    /// Standard marching squares over the field's sign, with crossings placed
    /// by linear interpolation. Returns closed loops (the padded border keeps
    /// every contour away from the grid edge).
    private static func marchingSquares(_ f: [Double], nx: Int, ny: Int,
                                        ox: Double, oy: Double, cell: Double) -> [[Vec2]] {
        var adjacency: [Int: [Int]] = [:]
        var points: [Int: Vec2] = [:]

        func value(_ i: Int, _ j: Int) -> Double { f[j * nx + i] }

        func crossH(_ i: Int, _ j: Int) -> Int {
            let id = (j * nx + i) * 2
            if points[id] == nil {
                let v0 = value(i, j), v1 = value(i + 1, j)
                let t = v0 / (v0 - v1)
                points[id] = Vec2(ox + (Double(i) + t) * cell, oy + Double(j) * cell)
            }
            return id
        }
        func crossV(_ i: Int, _ j: Int) -> Int {
            let id = (j * nx + i) * 2 + 1
            if points[id] == nil {
                let v0 = value(i, j), v1 = value(i, j + 1)
                let t = v0 / (v0 - v1)
                points[id] = Vec2(ox + Double(i) * cell, oy + (Double(j) + t) * cell)
            }
            return id
        }
        func segment(_ a: Int, _ b: Int) {
            adjacency[a, default: []].append(b)
            adjacency[b, default: []].append(a)
        }

        for j in 0..<(ny - 1) {
            for i in 0..<(nx - 1) {
                let in00 = value(i, j) < 0, in10 = value(i + 1, j) < 0
                let in11 = value(i + 1, j + 1) < 0, in01 = value(i, j + 1) < 0
                let code = (in00 ? 1 : 0) | (in10 ? 2 : 0) | (in11 ? 4 : 0) | (in01 ? 8 : 0)
                switch code {
                case 0, 15: continue
                case 1, 14: segment(crossH(i, j), crossV(i, j))
                case 2, 13: segment(crossH(i, j), crossV(i + 1, j))
                case 3, 12: segment(crossV(i, j), crossV(i + 1, j))
                case 4, 11: segment(crossV(i + 1, j), crossH(i, j + 1))
                case 6, 9: segment(crossH(i, j), crossH(i, j + 1))
                case 8, 7: segment(crossV(i, j), crossH(i, j + 1))
                default:
                    // Saddles: disambiguate with the cell-center sample.
                    let centerInside = value(i, j) + value(i + 1, j)
                        + value(i, j + 1) + value(i + 1, j + 1) < 0
                    if (code == 5) == centerInside {
                        segment(crossH(i, j), crossV(i + 1, j))
                        segment(crossV(i, j), crossH(i, j + 1))
                    } else {
                        segment(crossH(i, j), crossV(i, j))
                        segment(crossV(i + 1, j), crossH(i, j + 1))
                    }
                }
            }
        }

        // Chain crossings into loops. Every adjacency key was inserted
        // together with its `points` entry above, so the lookup can't miss.
        var visited = Set<Int>()
        var loops: [[Vec2]] = []
        for start in adjacency.keys where !visited.contains(start) {
            guard let firstStep = adjacency[start]?.first else { continue }
            var loop: [Vec2] = [points[start]!]
            visited.insert(start)
            var prev = start
            var cur = firstStep
            while cur != start, let nexts = adjacency[cur], let p = points[cur] {
                loop.append(p)
                visited.insert(cur)
                guard let nxt = nexts.first(where: { $0 != prev }) else { break }
                prev = cur
                cur = nxt
                if loop.count > 50_000 { break }
            }
            if loop.count >= 6 { loops.append(loop) }
        }
        return loops
    }

    /// Re-emits a closed loop with evenly spaced points.
    private static func resampleClosed(_ loop: [Vec2], spacing: Double) -> [Vec2] {
        let n = loop.count
        var perimeter = 0.0
        for i in 0..<n { perimeter += loop[i].distance(to: loop[(i + 1) % n]) }
        guard perimeter > spacing * 8 else { return [] }
        let count = max(12, Int(perimeter / spacing))
        let step = perimeter / Double(count)
        var out: [Vec2] = [loop[0]]
        var need = step
        var i = 0
        var cur = loop[0]
        var guardCounter = 0
        while out.count < count && guardCounter < n * 4 {
            guardCounter += 1
            let nxt = loop[(i + 1) % n]
            let d = cur.distance(to: nxt)
            if d < need {
                need -= d
                cur = nxt
                i += 1
            } else {
                cur = cur + (nxt - cur) * (need / d)
                out.append(cur)
                need = step
            }
        }
        // The walk can leave the final point nearly coincident with the
        // first; that one uneven gap would bulge the curved rendering there.
        if let last = out.last, out.count > 3, last.distance(to: out[0]) < step * 0.5 {
            out.removeLast()
        }
        return out
    }

    /// Blends each point toward its neighbors' midpoint. `strength` 1 is the
    /// full 1-2-1 kernel; 0.5 a gentle touch-up.
    private static func smoothClosed(_ loop: [Vec2], strength: Double) -> [Vec2] {
        let n = loop.count
        guard n >= 3 else { return loop }
        let k = strength * 0.5
        var out = loop
        for i in 0..<n {
            let mid = (loop[(i + n - 1) % n] + loop[(i + 1) % n]) / 2
            out[i] = loop[i] * (1 - k) + mid * k
        }
        return out
    }
}
