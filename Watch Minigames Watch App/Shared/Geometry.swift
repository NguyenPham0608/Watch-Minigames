//
//  Geometry.swift
//  Watch Minigames Watch App
//
//  Shared 2D vector math.
//

import Foundation
import CoreGraphics

// MARK: - Vec2

struct Vec2: Codable, Hashable {
    var x: Double
    var y: Double

    static let zero = Vec2(0, 0)

    init(x: Double, y: Double) { self.x = x; self.y = y }
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    static func / (a: Vec2, s: Double) -> Vec2 { Vec2(a.x / s, a.y / s) }
    static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }
    static func += (a: inout Vec2, b: Vec2) { a = a + b }
    static func -= (a: inout Vec2, b: Vec2) { a = a - b }

    var length: Double { (x * x + y * y).squareRoot() }
    var lengthSquared: Double { x * x + y * y }

    var normalized: Vec2 {
        let l = length
        return l > 1e-9 ? Vec2(x / l, y / l) : Vec2(0, -1)
    }

    /// Perpendicular (rotated 90°).
    var perp: Vec2 { Vec2(-y, x) }

    func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    func cross(_ o: Vec2) -> Double { x * o.y - y * o.x }
    func distance(to o: Vec2) -> Double { (self - o).length }

    func lerp(to o: Vec2, _ t: Double) -> Vec2 {
        Vec2(x + (o.x - x) * t, y + (o.y - y) * t)
    }

    func rotated(by a: Double) -> Vec2 {
        let c = cos(a), s = sin(a)
        return Vec2(x * c - y * s, x * s + y * c)
    }

    var cg: CGPoint { CGPoint(x: x, y: y) }
}

func closestPointOnSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Vec2 {
    let ab = b - a
    let len2 = ab.lengthSquared
    guard len2 > 1e-9 else { return a }
    let t = max(0, min(1, (p - a).dot(ab) / len2))
    return a + ab * t
}
