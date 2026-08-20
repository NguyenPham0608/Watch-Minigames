//
//  Haptics.swift
//  Watch Minigames Watch App
//
//  Thin rate-limited wrapper around WKInterfaceDevice haptics.
//

import Foundation
import WatchKit

enum Haptics {
    private static var lastPlayed: [WKHapticType: Date] = [:]

    /// Play a haptic, dropping repeats that arrive faster than `minInterval`.
    static func play(_ type: WKHapticType, minInterval: TimeInterval = 0.08) {
        let now = Date()
        if let last = lastPlayed[type], now.timeIntervalSince(last) < minInterval { return }
        lastPlayed[type] = now
        WKInterfaceDevice.current().play(type)
    }

    /// Wall impacts bucketed by speed: soft taps for grazes, firm hits for slams.
    static func bounce(impactSpeed: Double) {
        if impactSpeed > 190 {
            play(.notification, minInterval: 0.12)
        } else if impactSpeed > 95 {
            play(.directionDown, minInterval: 0.1)
        } else if impactSpeed > 34 {
            play(.click)
        }
    }

    /// A bigger two-pulse fanfare for game- or match-defining wins, reserved
    /// for moments that should feel distinctly bigger than a routine .success.
    static func celebrate() {
        play(.success, minInterval: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            play(.notification, minInterval: 0)
        }
    }

    /// A heavier two-pulse pattern for a decisive, match-ending loss.
    static func bigLoss() {
        play(.failure, minInterval: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            play(.failure, minInterval: 0)
        }
    }
}
