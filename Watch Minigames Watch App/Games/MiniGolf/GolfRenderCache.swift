//
//  GolfRenderCache.swift
//  Watch Minigames Watch App
//
//  Rendering caches for Mini Golf. The projection is non-affine (every point
//  scales with its own world-y), so screen paths can never be reused via a
//  transform — instead the renderer rebuilds them only when the camera, zoom,
//  viewport or wall set actually changed, and reuses the stored Paths
//  verbatim in between. The engine snaps its camera once the ease settles,
//  so a resting scene hits the cache on every frame.
//

import SwiftUI

final class GolfRenderCache {

    // MARK: Per-frame geometry

    /// Everything that shapes the ground/wall paths. Colors are deliberately
    /// absent: flash tints are applied at stroke time, never cached.
    struct FrameKey: Equatable {
        let camX: Double
        let camY: Double
        let zoom: Double
        let width: Double
        let height: Double
        /// Barriers the ball has smashed — their walls vanish from the scene.
        let broken: Set<UUID>
        /// The obstacles as values: editor drags reshape arc walls and
        /// barriers without touching `FairwayGeometry`, so they key the
        /// cache too. In play the hole is immutable and this compares as a
        /// same-storage fast path.
        let obstacles: [Obstacle]
    }

    /// One wall's stroke-ready level paths, ground → top; the last level is
    /// the cap.
    struct Wall {
        let levels: [Path]
        /// Screen-space band width.
        let width: Double
        /// Barriers resolve their live flash tint at stroke time.
        let barrierID: UUID?
    }

    struct FrameGeometry {
        let walls: [Wall]
        let ground: Path
        let shadow: Path
    }

    private var storedKey: FrameKey? = nil
    private var storedGeometry: FrameGeometry? = nil

    /// The stored geometry while `key` still matches; otherwise `build()`,
    /// stored for the frames that follow.
    func frameGeometry(key: FrameKey, build: () -> FrameGeometry) -> FrameGeometry {
        if let storedGeometry, storedKey == key { return storedGeometry }
        let built = build()
        storedKey = key
        storedGeometry = built
        return built
    }

    // MARK: Per-hole world geometry

    private var arcPointsByID: [UUID: (source: Obstacle, pts: [Vec2])] = [:]
    private var barrierWallByID: [UUID: (source: Obstacle, pts: [Vec2])] = [:]
    private var barrierEndsByID: [UUID: (source: Obstacle, pts: [Vec2])] = [:]
    private var portalIDs: [UUID] = []
    private var portalIndexByID: [UUID: Int] = [:]

    init(hole: HoleDesign) {
        for o in hole.obstacles {
            switch o.kind {
            case .arcWall:
                arcPointsByID[o.id] = (o, o.arcPoints)
            case .barrier:
                barrierWallByID[o.id] = (o, Self.subdividedBarrier(o))
                let (a, b) = o.barrierEndpoints
                barrierEndsByID[o.id] = (o, [a, b])
            case .portal:
                if portalIndexByID[o.id] == nil {
                    portalIndexByID[o.id] = portalIDs.count
                }
                portalIDs.append(o.id)
            default:
                break
            }
        }
    }

    /// Sampled polyline for an arc wall, resampled only when the obstacle
    /// itself changed (editor drags reshape it in place).
    func arcPoints(for o: Obstacle) -> [Vec2] {
        if let hit = arcPointsByID[o.id], hit.source == o { return hit.pts }
        let pts = o.arcPoints
        arcPointsByID[o.id] = (o, pts)
        return pts
    }

    /// A barrier subdivided so a sprite's depth line can split it.
    func barrierWallPoints(for o: Obstacle) -> [Vec2] {
        if let hit = barrierWallByID[o.id], hit.source == o { return hit.pts }
        let pts = Self.subdividedBarrier(o)
        barrierWallByID[o.id] = (o, pts)
        return pts
    }

    /// A barrier's exact endpoints — the ball-ghost probe wants the plain
    /// two-point segment, not the subdivided wall.
    func barrierEndpoints(for o: Obstacle) -> [Vec2] {
        if let hit = barrierEndsByID[o.id], hit.source == o { return hit.pts }
        let (a, b) = o.barrierEndpoints
        barrierEndsByID[o.id] = (o, [a, b])
        return [a, b]
    }

    /// id → index among the hole's portals, in obstacle order — the same
    /// index the per-portal filter + firstIndex scan used to produce. The
    /// stored map revalidates against the live obstacle list so editor
    /// additions and deletions renumber the hues exactly as before.
    func portalIndices(for obstacles: [Obstacle]) -> [UUID: Int] {
        var i = 0
        var valid = true
        for o in obstacles where o.kind == .portal {
            if i < portalIDs.count, portalIDs[i] == o.id {
                i += 1
            } else {
                valid = false
                break
            }
        }
        if valid, i == portalIDs.count { return portalIndexByID }
        portalIDs = obstacles.filter { $0.kind == .portal }.map(\.id)
        portalIndexByID = [:]
        for (index, id) in portalIDs.enumerated() where portalIndexByID[id] == nil {
            portalIndexByID[id] = index
        }
        return portalIndexByID
    }

    /// Subdivided so a barrier can be split by a sprite's depth line.
    private static func subdividedBarrier(_ o: Obstacle) -> [Vec2] {
        let (a, b) = o.barrierEndpoints
        return (0...8).map { a.lerp(to: b, Double($0) / 8) }
    }
}
