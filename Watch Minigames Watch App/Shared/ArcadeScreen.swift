//
//  ArcadeScreen.swift
//  Watch Minigames Watch App
//
//  The shell every arcade game plays inside: canvas, HUD chip and result
//  overlays, with a render clock that pauses when nobody is watching.
//

import SwiftUI

/// The shared in-game screen shell: full-bleed TimelineView + Canvas content,
/// an optional HUD chip pinned top-trailing OUTSIDE the per-frame subtree,
/// and result overlays. Pauses the render clock when the scene is inactive,
/// in Always-On Display, or when the game asks (`extraPaused`) — the engines'
/// dt clamp absorbs the resume gap.
struct ArcadeScreen<Content: View, Chip: View, Overlay: View>: View {
    /// nil = display rate; e.g. 30 for turn-based games with no fast motion.
    var fps: Double? = nil
    var extraPaused = false
    @ViewBuilder let content: (CGSize, Date) -> Content
    @ViewBuilder var chip: () -> Chip
    @ViewBuilder var overlay: () -> Overlay

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var paused: Bool {
        scenePhase != .active || isLuminanceReduced || extraPaused
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation(minimumInterval: fps.map { 1 / $0 },
                                        paused: paused)) { timeline in
                    content(geo.size, timeline.date)
                }
                .overlay(alignment: .topTrailing) { chip() }
                overlay()
            }
        }
        .ignoresSafeArea()
    }
}

extension ArcadeScreen where Chip == EmptyView {
    init(fps: Double? = nil, extraPaused: Bool = false,
         @ViewBuilder content: @escaping (CGSize, Date) -> Content,
         @ViewBuilder overlay: @escaping () -> Overlay) {
        self.init(fps: fps, extraPaused: extraPaused, content: content,
                  chip: { EmptyView() }, overlay: overlay)
    }
}

extension ArcadeScreen where Chip == EmptyView, Overlay == EmptyView {
    init(fps: Double? = nil, extraPaused: Bool = false,
         @ViewBuilder content: @escaping (CGSize, Date) -> Content) {
        self.init(fps: fps, extraPaused: extraPaused, content: content,
                  chip: { EmptyView() }, overlay: { EmptyView() })
    }
}
