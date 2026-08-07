//
//  ScoreStore.swift
//  Watch Minigames Watch App
//
//  Persistence for best scores, the coin bank and custom courses.
//  Everything lives in one JSON file in Application Support.
//

import Foundation
import Observation
import os

@Observable
final class ScoreStore {

    // Nonisolated so the Codable conformances stay usable from the
    // background save path (and stay legal under Swift 6).
    nonisolated private struct StoreData: Codable {
        var coins = 0
        var bestRound: Int? = nil
        var bestByHole: [String: Int] = [:]
        var customHoles: [HoleDesign] = []
        var customCounter = 0
        // Optional so stores saved before Super Pong still decode.
        var pongWins: Int? = nil
        var pongDifficulty: Int? = nil
        /// Legacy field; folded into `arcadeBests["stacker"]` on load.
        var stackerBest: Int? = nil
        /// Bests for the arcade games, keyed by game id ("bricks", "echo",
        /// "fruit", "stacker", "2048", "pairs", "spin", "keepups").
        /// Optional so older stores decode. Pairs stores fewest moves
        /// (lower is better).
        var arcadeBests: [String: Int]? = nil
    }

    private var data = StoreData()

    var coins: Int { data.coins }
    var pongWins: Int { data.pongWins ?? 0 }
    /// 0 easy, 1 medium, 2 hard (the original tuning). Clamped so a bad
    /// store file can never index the difficulty tables out of range.
    var pongDifficulty: Int { min(max(data.pongDifficulty ?? 2, 0), 2) }
    var bestRound: Int? { data.bestRound }
    var customHoles: [HoleDesign] { data.customHoles }
    /// The number the next new course will take, without claiming it.
    var peekCustomNumber: Int { data.customCounter + 1 }

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
        scheduleSave()
    }

    /// Records a finished hole; returns true if it's a new personal best.
    @discardableResult
    func recordHole(_ hole: HoleDesign, strokes: Int) -> Bool {
        let key = hole.id.uuidString
        if let existing = data.bestByHole[key], existing <= strokes { return false }
        data.bestByHole[key] = strokes
        scheduleSave()
        return true
    }

    /// Records a full built-in round; returns true if it's a new best round.
    @discardableResult
    func recordRound(total: Int) -> Bool {
        if let existing = data.bestRound, existing <= total { return false }
        data.bestRound = total
        scheduleSave()
        return true
    }

    func arcadeBest(_ key: String) -> Int {
        data.arcadeBests?[key] ?? 0
    }

    @discardableResult
    func recordArcadeBest(_ key: String, _ score: Int) -> Bool {
        guard score > arcadeBest(key) else { return false }
        var bests = data.arcadeBests ?? [:]
        bests[key] = score
        data.arcadeBests = bests
        scheduleSave()
        return true
    }

    /// Lower-is-better variant for move-count games (Pairs); 0 means unset.
    @discardableResult
    func recordArcadeBestLow(_ key: String, _ score: Int) -> Bool {
        let current = arcadeBest(key)
        guard score > 0, current == 0 || score < current else { return false }
        var bests = data.arcadeBests ?? [:]
        bests[key] = score
        data.arcadeBests = bests
        scheduleSave()
        return true
    }

    func setPongDifficulty(_ d: Int) {
        data.pongDifficulty = min(max(d, 0), 2)
        scheduleSave()
    }

    func recordPongWin() {
        data.pongWins = (data.pongWins ?? 0) + 1
        scheduleSave()
    }

    /// Claims the next course number. Call only when a course actually
    /// saves, so a cancelled editor never burns one; `peekCustomNumber`
    /// previews it for naming the draft.
    func nextCustomNumber() -> Int {
        data.customCounter += 1
        scheduleSave()
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
        scheduleSave()
    }

    func deleteCustom(_ hole: HoleDesign) {
        data.customHoles.removeAll { $0.id == hole.id }
        data.bestByHole.removeValue(forKey: hole.id.uuidString)
        scheduleSave()
    }

    // MARK: Disk

    nonisolated private static let logger = Logger(
        subsystem: "com.nguyen.Watch-Minigames.watchkitapp", category: "store")

    nonisolated private static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static var fileURL: URL {
        directory.appendingPathComponent("minigames-store.json")
    }

    /// Pre-rename store file; read once and migrated forward.
    nonisolated private static var legacyFileURL: URL {
        directory.appendingPathComponent("minigolf-store.json")
    }

    private var saveTask: Task<Void, Never>? = nil

    private func load() {
        var migratedFromLegacy = false
        var raw = try? Data(contentsOf: Self.fileURL)
        if raw == nil, let legacy = try? Data(contentsOf: Self.legacyFileURL) {
            raw = legacy
            migratedFromLegacy = true
        }
        guard let raw else { return }
        do {
            data = try JSONDecoder().decode(StoreData.self, from: raw)
        } catch {
            Self.logger.warning("Store decode failed: \(error.localizedDescription)")
            return
        }
        // One-time migration: the bespoke stacker best joins the arcade table.
        if let legacyBest = data.stackerBest {
            var bests = data.arcadeBests ?? [:]
            bests["stacker"] = max(bests["stacker"] ?? 0, legacyBest)
            data.arcadeBests = bests
            data.stackerBest = nil
            scheduleSave()
        }
        // Player courses promoted into the built-in list keep their ids, so
        // drop any lingering custom copies to avoid duplicates.
        let builtInIDs = Set(GolfLevels.builtIn.map(\.id))
        if data.customHoles.contains(where: { builtInIDs.contains($0.id) }) {
            data.customHoles.removeAll { builtInIDs.contains($0.id) }
            scheduleSave()
        }
        if migratedFromLegacy {
            // Rewrite under the new name; the legacy file goes away only once
            // the replacement is safely on disk.
            if Self.write(data) {
                try? FileManager.default.removeItem(at: Self.legacyFileURL)
            }
        }
    }

    /// Coalesces bursts of mutations into one disk write shortly after, off
    /// the main actor — game-over paths no longer pay for a synchronous
    /// encode + file write mid-frame.
    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard let self, !Task.isCancelled else { return }
            self.saveTask = nil
            let snapshot = self.data
            Task.detached(priority: .utility) {
                Self.write(snapshot)
            }
        }
    }

    /// Synchronous write-through for suspension, so nothing pending is lost.
    func flush() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        Self.write(data)
    }

    @discardableResult
    nonisolated private static func write(_ data: StoreData) -> Bool {
        do {
            let raw = try JSONEncoder().encode(data)
            try raw.write(to: fileURL, options: .atomic)
            return true
        } catch {
            logger.warning("Store save failed: \(error.localizedDescription)")
            return false
        }
    }
}
