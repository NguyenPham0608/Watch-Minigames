//
//  ScoreStore.swift
//  Minigames Watch App
//
//  Persistence for best scores, the coin bank and custom courses.
//  Everything lives in one JSON file in Application Support.
//

import Foundation
import Observation

@Observable
final class ScoreStore {

    private struct StoreData: Codable {
        var coins = 0
        var bestRound: Int? = nil
        var bestByHole: [String: Int] = [:]
        var customHoles: [HoleDesign] = []
        var customCounter = 0
        // Optional so stores saved before Super Pong still decode.
        var pongWins: Int? = nil
        var pongDifficulty: Int? = nil
        var stackerBest: Int? = nil
    }

    private var data = StoreData()

    var coins: Int { data.coins }
    var pongWins: Int { data.pongWins ?? 0 }
    /// 0 easy, 1 medium, 2 hard (the original tuning).
    var pongDifficulty: Int { data.pongDifficulty ?? 2 }
    var stackerBest: Int { data.stackerBest ?? 0 }
    var bestRound: Int? { data.bestRound }
    var customHoles: [HoleDesign] { data.customHoles }

    init() {
        load()
    }

    // MARK: Queries

    func best(for hole: HoleDesign) -> Int? {
        data.bestByHole[hole.id.uuidString]
    }

    // MARK: Mutations

    func addCoins(_ n: Int) {
        guard n > 0 else { return }
        data.coins += n
        save()
    }

    /// Records a finished hole; returns true if it's a new personal best.
    @discardableResult
    func recordHole(_ hole: HoleDesign, strokes: Int) -> Bool {
        let key = hole.id.uuidString
        if let existing = data.bestByHole[key], existing <= strokes { return false }
        data.bestByHole[key] = strokes
        save()
        return true
    }

    /// Records a full built-in round; returns true if it's a new best round.
    @discardableResult
    func recordRound(total: Int) -> Bool {
        if let existing = data.bestRound, existing <= total { return false }
        data.bestRound = total
        save()
        return true
    }

    @discardableResult
    func recordStackerBest(_ score: Int) -> Bool {
        guard score > (data.stackerBest ?? 0) else { return false }
        data.stackerBest = score
        save()
        return true
    }

    func setPongDifficulty(_ d: Int) {
        data.pongDifficulty = d
        save()
    }

    func recordPongWin() {
        data.pongWins = (data.pongWins ?? 0) + 1
        save()
    }

    func nextCustomNumber() -> Int {
        data.customCounter += 1
        save()
        return data.customCounter
    }

    func saveCustom(_ hole: HoleDesign) {
        var hole = hole
        hole.isCustom = true
        if let i = data.customHoles.firstIndex(where: { $0.id == hole.id }) {
            data.customHoles[i] = hole
        } else {
            data.customHoles.append(hole)
        }
        save()
    }

    func deleteCustom(_ hole: HoleDesign) {
        data.customHoles.removeAll { $0.id == hole.id }
        data.bestByHole.removeValue(forKey: hole.id.uuidString)
        save()
    }

    /// Removes all custom courses (the original 8 are untouched by design).
    func factoryReset() {
        for hole in data.customHoles {
            data.bestByHole.removeValue(forKey: hole.id.uuidString)
        }
        data.customHoles.removeAll()
        save()
    }

    // MARK: Disk

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("minigolf-store.json")
    }

    private func load() {
        guard let raw = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode(StoreData.self, from: raw) else { return }
        data = decoded
        // Player courses promoted into the built-in list keep their ids, so
        // drop any lingering custom copies to avoid duplicates.
        let builtInIDs = Set(Levels.builtIn.map(\.id))
        if data.customHoles.contains(where: { builtInIDs.contains($0.id) }) {
            data.customHoles.removeAll { builtInIDs.contains($0.id) }
            save()
        }
    }

    private func save() {
        guard let raw = try? JSONEncoder().encode(data) else { return }
        try? raw.write(to: Self.fileURL, options: .atomic)
    }
}
