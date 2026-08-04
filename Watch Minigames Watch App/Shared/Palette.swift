//
//  Palette.swift
//  Minigames Watch App
//
//  The shared cartoon palette: flat bright fills behind bold ink outlines.
//  Every game draws from this one set so the app reads as a single world.
//

import SwiftUI

enum Palette {
    static let ink = Color(red: 0.15, green: 0.15, blue: 0.13)
    static let bg = Color(red: 0.835, green: 0.855, blue: 0.795)
    static let fairway = Color(red: 0.42, green: 0.73, blue: 0.42)
    static let fairwayStripe = Color(red: 0.47, green: 0.775, blue: 0.455)
    static let wallTop = Color(red: 0.965, green: 0.96, blue: 0.93)
    static let wallSide = Color(red: 0.72, green: 0.72, blue: 0.665)
    static let cup = Color(red: 0.13, green: 0.17, blue: 0.12)
    static let sand = Color(red: 0.90, green: 0.81, blue: 0.58)
    static let sandDark = Color(red: 0.74, green: 0.63, blue: 0.40)
    static let gold = Color(red: 0.92, green: 0.72, blue: 0.28)
    static let goldDeep = Color(red: 0.71, green: 0.52, blue: 0.14)
    static let boostBlue = Color(red: 0.42, green: 0.64, blue: 0.79)
    static let boostBlueDeep = Color(red: 0.29, green: 0.49, blue: 0.63)
    static let bumperCoral = Color(red: 0.89, green: 0.48, blue: 0.40)
    static let shadow = Color.black.opacity(0.16)
    static let hillLight = Color(red: 0.55, green: 0.80, blue: 0.50)
    static let hillLighter = Color(red: 0.64, green: 0.86, blue: 0.57)
    static let deepGreen = Color(red: 0.30, green: 0.56, blue: 0.34)
    static let treeGreen = Color(red: 0.30, green: 0.55, blue: 0.33)
    static let trunkBrown = Color(red: 0.47, green: 0.35, blue: 0.22)
    static let fanGray = Color(red: 0.60, green: 0.63, blue: 0.66)

    /// Muted hue per portal pair, so multiple pairs on one hole stay
    /// tellable apart. Indexed by the pair's order among the hole's portals.
    static let portalHues: [(main: Color, deep: Color, light: Color)] = [
        (Color(red: 0.42, green: 0.64, blue: 0.79),
         Color(red: 0.29, green: 0.49, blue: 0.63),
         Color(red: 0.76, green: 0.86, blue: 0.92)),
        (Color(red: 0.89, green: 0.48, blue: 0.40),
         Color(red: 0.70, green: 0.34, blue: 0.27),
         Color(red: 0.96, green: 0.79, blue: 0.74)),
        (Color(red: 0.63, green: 0.53, blue: 0.79),
         Color(red: 0.48, green: 0.39, blue: 0.63),
         Color(red: 0.85, green: 0.80, blue: 0.92)),
        (Color(red: 0.38, green: 0.70, blue: 0.66),
         Color(red: 0.27, green: 0.54, blue: 0.50),
         Color(red: 0.76, green: 0.89, blue: 0.86)),
        (Color(red: 0.92, green: 0.72, blue: 0.28),
         Color(red: 0.71, green: 0.52, blue: 0.14),
         Color(red: 0.97, green: 0.88, blue: 0.67)),
    ]

    static let confettiColors: [Color] = [
        gold, bumperCoral, boostBlue,
        Color(red: 0.63, green: 0.53, blue: 0.79),
        Color(red: 0.38, green: 0.70, blue: 0.66),
        wallTop,
    ]

    static func portalHue(_ i: Int) -> (main: Color, deep: Color, light: Color) {
        portalHues[((i % portalHues.count) + portalHues.count) % portalHues.count]
    }
}
