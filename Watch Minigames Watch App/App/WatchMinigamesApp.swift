//
//  WatchMinigamesApp.swift
//  Watch Minigames Watch App
//
//  Created by Nguyen Pham on 8/1/26.
//

import SwiftUI

@main
struct WatchMinigamesApp: App {
    @State private var store = ScoreStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .onChange(of: scenePhase) { _, phase in
            // Push any pending debounced score writes to disk before suspension.
            if phase != .active { store.flush() }
        }
    }
}
