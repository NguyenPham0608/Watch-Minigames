//
//  ContentView.swift
//  Watch Minigames Watch App
//
//  The app shell: a vertical carousel of game home pages, paged by swipe
//  or the crown.
//

import SwiftUI

/// Every game in the carousel, in page order. Adding a game is one new case
/// plus one arm in `home` — the tabs and the crown range follow.
enum Game: Int, CaseIterable, Identifiable {
    case golf, pong, stacker, bricks, echo, fruit, game2048, pairs, spin

    var id: Int { rawValue }

    @ViewBuilder var home: some View {
        switch self {
        case .golf: GolfHome()
        case .pong: PongHome()
        case .stacker: StackerHome()
        case .bricks: BricksHome()
        case .echo: EchoHome()
        case .fruit: FruitHome()
        case .game2048: Game2048Home()
        case .pairs: PairsHome()
        case .spin: SpinHome()
        }
    }
}

struct ContentView: View {
    @State private var page = 0
    @State private var crown = 0.0

    var body: some View {
        NavigationStack {
            #if DEBUG
            if let demo = ProcessInfo.processInfo.environment["DEMO_GAME"] {
                demoDestination(demo)
            } else {
                home
            }
            #else
            home
            #endif
        }
    }

    private var home: some View {
        TabView(selection: $page) {
            ForEach(Game.allCases) { game in
                game.home.tag(game.rawValue)
            }
        }
        .focusable()
        .digitalCrownRotation($crown, from: 0, through: Double(Game.allCases.count - 1),
                              by: 1, sensitivity: .low, isContinuous: false,
                              isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, value in
            let target = Int(value.rounded())
            if target != page {
                withAnimation(.easeInOut(duration: 0.25)) { page = target }
            }
        }
        .onChange(of: page) { _, value in
            // After a swipe, restart the crown from the settled page.
            if Int(crown.rounded()) != value { crown = Double(value) }
        }
    }

    #if DEBUG
    /// Verification hook: `SIMCTL_CHILD_DEMO_GAME=<key> simctl launch …`
    /// opens a game directly for screenshot capture.
    @ViewBuilder
    private func demoDestination(_ key: String) -> some View {
        switch key {
        case "golf": GolfView(holes: GolfLevels.builtIn, isRound: true)
        case "courses": CustomCourseList()
        case "pong": PongView()
        case "stacker": StackerView()
        case "bricks": BricksView()
        case "echo": EchoView()
        case "fruit": FruitView()
        case "2048": Game2048View()
        case "pairs": PairsView()
        case "spin": SpinView()
        default: home
        }
    }
    #endif
}

#Preview {
    ContentView()
        .environment(ScoreStore())
}
