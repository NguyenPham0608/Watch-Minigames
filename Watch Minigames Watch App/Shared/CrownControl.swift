//
//  CrownControl.swift
//  Watch Minigames Watch App
//
//  Relative Digital Crown input with the system scroll feel: haptic detents,
//  list-scroll pacing, and no dead travel when a control is pinned at an edge.
//

import SwiftUI

enum CrownFeel {
    /// How far one crown detent moves a paddle, in points. One shared knob so
    /// every game paces alike; raise it if steering feels too slow.
    static let pointsPerDetent = 3.0
}

/// Accumulates rotation over an effectively unbounded range and hands each
/// change to the view as a delta in detent units. Sensitivity is defined per
/// integer step of the bound value, so `by: 1` here gives a fixed
/// rotation-per-detent no matter what the caller maps detents onto — unlike a
/// 0...1 binding, where the whole range flies by in a single step's twist.
/// Relative deltas also mean drags and the crown never fight: whichever moved
/// last simply nudges the control from where it is.
private struct CrownDetents: ViewModifier {
    var sensitivity: DigitalCrownRotationalSensitivity
    let onDetents: (Double) -> Void

    /// Wide enough that play never reaches an edge; `isContinuous` wraps
    /// there, and the guard below drops that one absurd wrap delta.
    private static let bound = 100_000.0

    @State private var accum = 0.0
    @State private var baseline = 0.0

    func body(content: Content) -> some View {
        content
            .focusable()
            .digitalCrownRotation($accum, from: -Self.bound, through: Self.bound,
                                  by: 1, sensitivity: sensitivity,
                                  isContinuous: true, isHapticFeedbackEnabled: true)
            .onChange(of: accum) { _, value in
                let delta = value - baseline
                baseline = value
                guard abs(delta) < Self.bound else { return }
                onDetents(delta)
            }
    }
}

extension View {
    /// Steer with the crown at system-scroll pace: `onDetents` receives the
    /// rotation since the last call, in haptic detent units.
    func crownDetents(sensitivity: DigitalCrownRotationalSensitivity = .medium,
                      _ onDetents: @escaping (Double) -> Void) -> some View {
        modifier(CrownDetents(sensitivity: sensitivity, onDetents: onDetents))
    }
}
