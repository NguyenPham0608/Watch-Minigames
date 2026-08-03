//
//  Levels.swift
//  Minigames Watch App
//
//  The built-in holes. IDs are fixed so best scores stay attached across
//  launches (player-designed holes keep their original ids).
//

import Foundation

enum Levels {
    private static func bid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!
    }

    private static func oid(_ hole: Int, _ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-9000-%06d%06d", hole, n))!
    }

    private static func wp(_ x: Double, _ y: Double, _ w: Double) -> Waypoint {
        Waypoint(pos: Vec2(x, y), width: w)
    }

    static let builtIn: [HoleDesign] = [
        // 1 — Gentle S-curve opener.
        HoleDesign(
            id: bid(1), name: "First Bend", par: 2,
            tee: Vec2(100, 482), cup: Vec2(122, 262),
            waypoints: [
                wp(100, 500, 64), wp(85, 415, 60), wp(140, 330, 58), wp(120, 240, 62),
            ],
            obstacles: [
                Obstacle(id: oid(1, 1), kind: .coin, pos: Vec2(112, 372)),
            ]
        ),

        // 3 — Wide-bellied opener with a coin trail up the middle.
        // (Player-designed; keeps its original id so best scores carry over.)
        HoleDesign(
            id: UUID(uuidString: "8DFA4415-D919-4DAE-9070-FBDC1DB6B897")!,
            name: "The Meadow", par: 3,
            tee: Vec2(150, 420), cup: Vec2(150, 195),
            waypoints: [
                wp(150, 440, 72), wp(146.3, 324, 150), wp(150, 180, 72),
            ],
            obstacles: [
                Obstacle(id: oid(9, 1), kind: .coin, pos: Vec2(148.5, 370.3)),
                Obstacle(id: oid(9, 2), kind: .coin, pos: Vec2(148.3, 311.9)),
                Obstacle(id: oid(9, 3), kind: .coin, pos: Vec2(148.8, 248.1)),
            ]
        ),

        // 4 — Climb, hard right, and a bumper field guarding the green.
        HoleDesign(
            id: UUID(uuidString: "D41027AF-6BE6-423B-AE36-C301D6538638")!,
            name: "Pinball Corner", par: 3,
            tee: Vec2(150, 420), cup: Vec2(324.5, 40.4),
            waypoints: [
                wp(150, 440, 72), wp(150, 320, 72), wp(158.5, 138.2, 137.8),
                wp(331.9, 46.3, 150),
            ],
            obstacles: [
                Obstacle(id: oid(10, 1), kind: .bumper, pos: Vec2(148.8, 267.1)),
                Obstacle(id: oid(10, 2), kind: .sand, pos: Vec2(152.7, 334.4), rot: 12.373, scale: 1.905),
                Obstacle(id: oid(10, 3), kind: .arcWall, pos: Vec2(320.6, 50.5), rot: 0.997),
                Obstacle(id: oid(10, 4), kind: .bumper, pos: Vec2(363.3, 28.2)),
                Obstacle(id: oid(10, 5), kind: .spinner, pos: Vec2(145.0, 156.1), scale: 1.791),
                Obstacle(id: oid(10, 6), kind: .bumper, pos: Vec2(200.7, 61.9)),
                Obstacle(id: oid(10, 7), kind: .bumper, pos: Vec2(230.1, 110.4)),
            ]
        ),

        // 5 — A grand circuit that loops back over its own start.
        HoleDesign(
            id: UUID(uuidString: "E5AC3C0D-D3CC-4D5E-A826-54139F840355")!,
            name: "The Loop", par: 3,
            tee: Vec2(150, 420), cup: Vec2(-166.9, 37.9),
            waypoints: [
                wp(148.8, 438.1, 150), wp(65.3, 390.4, 68.7), wp(-83.4, 251.0, 72),
                wp(-227.6, 62.3, 72), wp(-183.0, 64.5, 129.3), wp(207.2, 158.6, 84.7),
                wp(114.7, 377.3, 72),
            ],
            obstacles: [
                Obstacle(id: oid(11, 1), kind: .spinner, pos: Vec2(-184.4, 60.6)),
                Obstacle(id: oid(11, 2), kind: .bumper, pos: Vec2(18.9, 349.9)),
                Obstacle(id: oid(11, 3), kind: .sand, pos: Vec2(-54.4, 278.2), rot: 1.216, scale: 1.572),
                Obstacle(id: oid(11, 4), kind: .boost, pos: Vec2(154.3, 310.0), rot: 0.569),
                Obstacle(id: oid(11, 5), kind: .boost, pos: Vec2(185.3, 251.2), rot: 0.455),
                Obstacle(id: oid(11, 6), kind: .boost, pos: Vec2(208.4, 174.5)),
                Obstacle(id: oid(11, 7), kind: .boost, pos: Vec2(170.1, 126.9), rot: -1.164),
                Obstacle(id: oid(11, 8), kind: .bumper, pos: Vec2(-6.9, 86.9)),
            ]
        ),

        // 6 — A long sideways trek: sand and coins on the flats, then a
        // guarded uphill green.
        HoleDesign(
            id: UUID(uuidString: "C9493A3C-765E-480E-B0BA-05517903EAD7")!,
            name: "Long Haul", par: 3,
            tee: Vec2(150, 420), cup: Vec2(572.2, 323.0),
            waypoints: [
                wp(145.0, 431.4, 139.6), wp(162.1, 440.4, 72), wp(490.4, 514.0, 72),
                wp(586.4, 271.4, 137.0),
            ],
            obstacles: [
                Obstacle(id: oid(12, 1), kind: .boost, pos: Vec2(525.2, 468.0), rot: 0.356),
                Obstacle(id: oid(12, 2), kind: .arcWall, pos: Vec2(569.2, 349.2), rot: 0.228),
                Obstacle(id: oid(12, 3), kind: .bumper, pos: Vec2(551.8, 278.2)),
                Obstacle(id: oid(12, 4), kind: .bumper, pos: Vec2(613.6, 292.2)),
                Obstacle(id: oid(12, 5), kind: .sand, pos: Vec2(336.3, 494.7), rot: 0.009, scale: 1.720),
                Obstacle(id: oid(12, 6), kind: .coin, pos: Vec2(359.5, 507.5)),
                Obstacle(id: oid(12, 7), kind: .coin, pos: Vec2(394.2, 516.2)),
                Obstacle(id: oid(12, 8), kind: .coin, pos: Vec2(432.1, 518.9)),
            ]
        ),

        // 7 — Paths crossing over each other in every direction.
        HoleDesign(
            id: UUID(uuidString: "4CAAD5FD-1BF4-42D8-AAF1-9D071CA19D0E")!,
            name: "Crossfire", par: 3,
            tee: Vec2(166.4, 483.3), cup: Vec2(266.8, 15.9),
            waypoints: [
                wp(153.0, 408.5, 72), wp(91.4, 121.9, 72), wp(371.6, 163.9, 72),
                wp(200.3, 415.5, 72), wp(269.4, 10.0, 72), wp(166.8, 483.5, 122.5),
            ],
            obstacles: [
                Obstacle(id: oid(13, 1), kind: .boost, pos: Vec2(117.5, 312.5), rot: -0.241),
                Obstacle(id: oid(13, 2), kind: .boost, pos: Vec2(275, 356.4), rot: 0.728),
                Obstacle(id: oid(13, 3), kind: .spinner, pos: Vec2(187.9, 372.4), rot: -4.757, scale: 1.920),
                Obstacle(id: oid(13, 4), kind: .sand, pos: Vec2(226.5, 197.6), scale: 2.441),
                Obstacle(id: oid(13, 5), kind: .bumper, pos: Vec2(246.7, 108.2)),
            ]
        ),

        // 8 — One long portal ride carries the ball to a far-off island green.
        // (Player-designed; keeps its original id so best scores carry over.)
        HoleDesign(
            id: UUID(uuidString: "34AE8231-5BDF-4295-BF9D-3C891CB30B5F")!,
            name: "The Ferry", par: 3,
            tee: Vec2(123.337, 355.632), cup: Vec2(-74.501, 354.062),
            waypoints: [
                wp(124.081, 358.123, 79.812), wp(327.11, 298.62, 72.651),
            ],
            islands: [
                [wp(-69.056, 398.689, 64), wp(-87.336, 216.321, 64)],
            ],
            obstacles: [
                Obstacle(id: oid(15, 1), kind: .portal, pos: Vec2(319.746, 293.66), rot: -1.468, scale: 5.464),
                Obstacle(id: oid(15, 2), kind: .boost, pos: Vec2(195.501, 329.979), rot: 1.281),
            ]
        ),

        // 9 — Island-hopping: each stone has a hazard and the portal onward.
        // (Player-designed; keeps its original id so best scores carry over.)
        HoleDesign(
            id: UUID(uuidString: "074C4E08-CAE9-48BE-8FD4-8B38DC22EC2D")!,
            name: "Stepping Stones", par: 3,
            tee: Vec2(150, 420), cup: Vec2(500.101, 354.297),
            waypoints: [
                wp(150, 440, 72), wp(150, 320, 72), wp(150, 180, 72),
            ],
            islands: [
                [wp(265, 352.5, 64), wp(265, 262.5, 64)],
                [wp(376.853, 358.476, 64), wp(380, 262.5, 64)],
                [wp(500, 355.833, 64), wp(500, 265.833, 64)],
            ],
            obstacles: [
                Obstacle(id: oid(16, 1), kind: .spinner, pos: Vec2(150.947, 319.136)),
                Obstacle(id: oid(16, 2), kind: .bumper, pos: Vec2(264.934, 306.744)),
                Obstacle(id: oid(16, 3), kind: .barrier, pos: Vec2(379.516, 313.79)),
                Obstacle(id: oid(16, 4), kind: .sand, pos: Vec2(488.883, 307.534)),
                Obstacle(id: oid(16, 5), kind: .portal, pos: Vec2(150.676, 207.936), rot: 2.018, scale: 1.724),
                Obstacle(id: oid(16, 6), kind: .portal, pos: Vec2(264.508, 347.743), rot: 0.94, scale: 1.949),
                Obstacle(id: oid(16, 7), kind: .portal, pos: Vec2(376.728, 357.899), rot: 0.931, scale: 2.077),
            ]
        ),

        // 10 — A bumper gauntlet, then a portal onto a tiny detached green.
        // (Player-designed; keeps its original id so best scores carry over.)
        HoleDesign(
            id: UUID(uuidString: "CE39D5FA-52A8-445D-BFDA-B3F8381B5D2B")!,
            name: "Postage Stamp", par: 3,
            tee: Vec2(150, 420), cup: Vec2(145.326, 42.261),
            waypoints: [
                wp(150, 440, 72), wp(150, 320, 150), wp(150, 180, 72),
            ],
            islands: [
                [wp(145.974, 76.795, 64), wp(144.402, 38.67, 64)],
            ],
            obstacles: [
                Obstacle(id: oid(17, 1), kind: .bumper, pos: Vec2(108.881, 309.135)),
                Obstacle(id: oid(17, 2), kind: .bumper, pos: Vec2(190.451, 308.607)),
                Obstacle(id: oid(17, 3), kind: .bumper, pos: Vec2(150.299, 309.734)),
                Obstacle(id: oid(17, 4), kind: .arcWall, pos: Vec2(150.485, 264.733), rot: -3.126, scale: 0.56),
                Obstacle(id: oid(17, 5), kind: .portal, pos: Vec2(149.275, 180.786), rot: -0.021, scale: 1.482),
            ]
        ),

        // 11 — A grand tour across three islands, pinball arena included.
        // (Player-designed; keeps its original id so best scores carry over.)
        HoleDesign(
            id: UUID(uuidString: "1E49608F-C9A9-4BA8-80AA-4B292903D123")!,
            name: "Archipelago", par: 3,
            tee: Vec2(150, 420), cup: Vec2(404.489, 148.203),
            waypoints: [
                wp(150, 440, 72), wp(156.73, 322.308, 72), wp(175.341, 9.915, 72), wp(187.894, -137.955, 150),
            ],
            islands: [
                [wp(330.4, -47.879, 64), wp(395.601, -156.899, 64), wp(473.144, -70.195, 64), wp(340.31, -47.427, 64)],
                [wp(727.531, -66.509, 150), wp(724.876, -171.696, 150)],
                [wp(403.509, 234.504, 64), wp(403.509, 144.504, 64)],
            ],
            obstacles: [
                Obstacle(id: oid(18, 1), kind: .sand, pos: Vec2(158.417, 281.586), rot: 1.591, scale: 1.691),
                Obstacle(id: oid(18, 2), kind: .boost, pos: Vec2(162.423, 224.54), rot: 0.039),
                Obstacle(id: oid(18, 3), kind: .arcWall, pos: Vec2(183.892, -73.565), rot: -3.041),
                Obstacle(id: oid(18, 4), kind: .spinner, pos: Vec2(183.422, -63.673)),
                Obstacle(id: oid(18, 5), kind: .portal, pos: Vec2(187.448, -154.332), rot: 2.062, scale: 2.413),
                Obstacle(id: oid(18, 6), kind: .spinner, pos: Vec2(727.107, -118.133), rot: -4.385, scale: 2.241),
                Obstacle(id: oid(18, 7), kind: .bumper, pos: Vec2(691.284, -50.688)),
                Obstacle(id: oid(18, 8), kind: .bumper, pos: Vec2(726.819, -28.631)),
                Obstacle(id: oid(18, 9), kind: .bumper, pos: Vec2(765.093, -49.656)),
                Obstacle(id: oid(18, 10), kind: .bumper, pos: Vec2(725.399, -213.184)),
                Obstacle(id: oid(18, 11), kind: .bumper, pos: Vec2(688.692, -193.315)),
                Obstacle(id: oid(18, 12), kind: .bumper, pos: Vec2(763.442, -193.33)),
                Obstacle(id: oid(18, 13), kind: .portal, pos: Vec2(454.846, -119.637), rot: 1.56, scale: 3.285),
                Obstacle(id: oid(18, 14), kind: .portal, pos: Vec2(759.908, -87.016), rot: -2.294, scale: 6.415),
                Obstacle(id: oid(18, 15), kind: .spinner, pos: Vec2(403.154, 194.416)),
            ]
        ),
    ]
}
