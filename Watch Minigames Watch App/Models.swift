//
//  Models.swift
//  Minigames Watch App
//
//  Data model for holes and obstacles. Everything is Codable so custom
//  courses persist as plain JSON.
//

import Foundation

enum ObstacleKind: String, Codable, CaseIterable {
    case bumper
    case sand
    case boost
    case arcWall
    case pillar
    case barrier
    case spinner
    case coin
    case hill
    case vortex
    case fan
    case portal
    case tree
    case flowers

    var displayName: String {
        switch self {
        case .bumper: return "Bumper"
        case .sand: return "Sand"
        case .boost: return "Boost Pad"
        case .arcWall: return "Curved Wall"
        case .pillar: return "Pillar"
        case .barrier: return "Barrier"
        case .spinner: return "Spinner"
        case .coin: return "Coin"
        case .hill: return "Hill"
        case .vortex: return "Vortex"
        case .fan: return "Fan"
        case .portal: return "Portal"
        case .tree: return "Tree"
        case .flowers: return "Flowers"
        }
    }

    var symbol: String {
        switch self {
        case .bumper: return "smallcircle.circle"
        case .sand: return "hurricane"
        case .boost: return "chevron.up.2"
        case .arcWall: return "point.bottomleft.forward.to.point.topright.scurvepath"
        case .pillar: return "circle.fill"
        case .barrier: return "rectangle.portrait.fill"
        case .spinner: return "arrow.triangle.2.circlepath"
        case .coin: return "circlebadge.2.fill"
        case .hill: return "smallcircle.filled.circle"
        case .vortex: return "tornado"
        case .fan: return "wind"
        case .portal: return "record.circle"
        case .tree: return "tree.fill"
        case .flowers: return "camera.macro"
        }
    }
}

struct Obstacle: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: ObstacleKind
    var pos: Vec2
    /// Rotation in radians. Boost pads launch along `rotated up`, arcs orient
    /// their covered span, barriers align their long axis.
    var rot: Double = 0
    var scale: Double = 1
    /// Kind-specific extra parameter: arc span in degrees for `arcWall`
    /// (0 → default 160°).
    var extra: Double = 0
}

extension Obstacle {
    var bumperRadius: Double { 11 * scale }
    var sandRadius: Double { 21 * scale }
    var pillarRadius: Double { 14 * scale }
    var coinRadius: Double { 7.0 }
    var arcRadius: Double { 34 * scale }
    var arcSpanDegrees: Double { extra > 1 ? extra : 160 }
    var barrierHalfLength: Double { 23 * scale }
    var spinnerArmLength: Double { 27 * scale }
    var boostHalfWidth: Double { 11 * scale }
    var boostHalfLength: Double { 16 * scale }
    var hillRadius: Double { 26 * scale }
    var vortexRadius: Double { 34 * scale }
    var fanZoneLength: Double { 62 * scale }
    var fanZoneHalfWidth: Double { 17 * scale }
    /// Portal rings stay one size; `scale` sets the reach instead.
    var portalRadius: Double { 10 }
    /// Where a portal drops the ball. In the editor both ends are draggable —
    /// moving either end just re-derives `rot` (aim) and `scale` (reach).
    var portalExit: Vec2 { pos + direction * (74 * scale) }
    var treeRadius: Double { 7.5 * scale }

    /// Unit direction for rot (rot = 0 points "up" the course, toward -y).
    var direction: Vec2 { Vec2(sin(rot), -cos(rot)) }

    /// Stable per-instance seed for decorative jitter.
    var seed: Double {
        var h: UInt64 = 1469598103934665603
        for b in id.uuidString.utf8 {
            h = (h ^ UInt64(b)) &* 1099511628211
        }
        return Double(h % 1000) / 1000.0
    }

    /// Sampled polyline for arc walls (world space).
    var arcPoints: [Vec2] {
        let span = arcSpanDegrees * .pi / 180
        let steps = max(12, Int(span * arcRadius / 5))
        var pts: [Vec2] = []
        for i in 0...steps {
            let a = rot - span / 2 + span * Double(i) / Double(steps) + .pi / 2
            pts.append(pos + Vec2(cos(a), sin(a)) * arcRadius)
        }
        return pts
    }

    /// Endpoints for barriers (world space).
    var barrierEndpoints: (Vec2, Vec2) {
        let d = Vec2(cos(rot), sin(rot))
        return (pos - d * barrierHalfLength, pos + d * barrierHalfLength)
    }
}

struct Waypoint: Codable, Hashable {
    var pos: Vec2
    var width: Double
}

struct HoleDesign: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var par: Int
    var tee: Vec2
    var cup: Vec2
    var waypoints: [Waypoint]
    /// Extra strips of land, each its own waypoint path. They can sit fully
    /// detached from the main fairway — reachable by portal.
    var islands: [[Waypoint]]? = nil
    var obstacles: [Obstacle] = []
    var isCustom: Bool = false
}

extension HoleDesign {
    /// Main fairway first, then every island.
    var allPaths: [[Waypoint]] { [waypoints] + (islands ?? []) }
}

extension HoleDesign {
    /// Fresh template used by the editor's "New Course".
    static func newCustom(number: Int) -> HoleDesign {
        HoleDesign(
            name: "Custom \(number)",
            par: 3,
            tee: Vec2(150, 420),
            cup: Vec2(150, 195),
            waypoints: [
                Waypoint(pos: Vec2(150, 440), width: 72),
                Waypoint(pos: Vec2(150, 320), width: 72),
                Waypoint(pos: Vec2(150, 180), width: 72),
            ],
            obstacles: [],
            isCustom: true
        )
    }
}
