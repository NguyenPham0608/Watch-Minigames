//
//  MinigamesApp.swift
//  Minigames Watch App
//
//  Created by Nguyen Pham on 8/1/26.
//

import SwiftUI

@main
struct Minigames_Watch_AppApp: App {
    @State private var store = ScoreStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
