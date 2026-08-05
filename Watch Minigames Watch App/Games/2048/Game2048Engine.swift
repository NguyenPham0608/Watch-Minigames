//
//  Game2048Engine.swift
//  Minigames Watch App
//
//  2048: swipe to slide the board; equal tiles merge and double toward the
//  gold 2048. Slides tween with a spring overshoot, merges pop, the whole
//  board nudges in the swipe direction when the tiles slam home.
//

import Foundation
import CoreGraphics
import WatchKit

final class Game2048Engine {

    enum Dir {
        case up, down, left, right

        var dx: Int { self == .left ? -1 : (self == .right ? 1 : 0) }
        var dy: Int { self == .up ? -1 : (self == .down ? 1 : 0) }
        var vec: Vec2 { Vec2(Double(dx), Double(dy)) }
    }

    struct Tile {
        var id: Int
        var value: Int
        var col: Int
        var row: Int
        var fromCol: Int
        var fromRow: Int
        var movedAt: Double
        var spawnedAt: Double
        var mergedAt: Double
        /// Slides under its partner and vanishes when the move resolves.
        var dying = false
        /// Doubles (and pops) when the slide lands.
        var absorbing = false
    }

    /// Screen geometry for the board; the view keeps courtW/H current.
    struct Layout {
        var board: Double
        var ox: Double
        var oy: Double
        var gap: Double
        var cell: Double

        func rect(_ colD: Double, _ rowD: Double) -> CGRect {
            CGRect(x: ox + gap + colD * (cell + gap),
                   y: oy + gap + rowD * (cell + gap),
                   width: cell, height: cell)
        }
    }

    // MARK: Config

    static let n = 4
    static let slideDur = 0.13

    var courtW = 180.0
    var courtH = 220.0

    // MARK: State

    var tiles: [Tile] = []
    var score = 0
    var done = false
    var time = 0.0
    var shakeAmp = 0.0
    var particles: [Particle] = []
    var floaters: [Floater] = []
    /// Timing for juice: chip flashes and the board slam nudge.
    var lastMergeAt = -10.0
    var nudgeAt = -10.0
    var nudgeDir = Vec2.zero
    var onGameOver: ((Int) -> Void)?

    private var nextID = 1
    private var lastDate: Date?
    private var resolveAt: Double? = nil
    private var lastDir: Dir = .left
    private var pendingSpawn: (col: Int, row: Int, value: Int)? = nil
    private var pendingSwipe: (dir: Dir, at: Double)? = nil
    private var celebrated = false

    init() {
        spawnRandomTile()
        spawnRandomTile()
    }

    func layout() -> Layout {
        // Top margin clears the clock and the glass score chip so the
        // top corner tiles never hide beneath them.
        let side = 10.0, top = 70.0, bottom = 12.0
        let board = min(courtW - side * 2, courtH - top - bottom)
        let gap = board * 0.03
        return Layout(board: board,
                      ox: (courtW - board) / 2,
                      oy: top + (courtH - top - bottom - board) / 2,
                      gap: gap,
                      cell: (board - gap * 5) / 4)
    }

    // MARK: Stepping

    func step(to date: Date) {
        guard let last = lastDate else {
            lastDate = date
            return
        }
        let dt = max(0, min(date.timeIntervalSince(last), 1.0 / 30.0))
        lastDate = date
        time += dt

        shakeAmp *= exp(-8 * dt)
        updateParticles(dt)
        floaters.removeAll { time - $0.bornAt > 0.8 }

        if let at = resolveAt, time >= at { resolve() }
        // A swipe made while tiles were still flying fires as soon as
        // the board settles — fast play stays fast.
        if resolveAt == nil, let p = pendingSwipe {
            pendingSwipe = nil
            if time - p.at < 0.45 { apply(p.dir) }
        }
    }

    // MARK: Input

    func move(_ d: Dir) {
        guard !done else { return }
        if resolveAt != nil {
            pendingSwipe = (d, time)
            return
        }
        apply(d)
    }

    private func slot(_ d: Dir, _ lane: Int, _ k: Int) -> (col: Int, row: Int) {
        switch d {
        case .left: return (k, lane)
        case .right: return (Self.n - 1 - k, lane)
        case .up: return (lane, k)
        case .down: return (lane, Self.n - 1 - k)
        }
    }

    private func apply(_ d: Dir) {
        var grid = [[Int?]](repeating: [Int?](repeating: nil, count: Self.n),
                            count: Self.n)
        for (i, t) in tiles.enumerated() { grid[t.col][t.row] = i }

        var movedAny = false
        for lane in 0..<Self.n {
            // Tiles in this lane, nearest-to-edge first.
            var order: [Int] = []
            for k in 0..<Self.n {
                let s = slot(d, lane, k)
                if let i = grid[s.col][s.row] { order.append(i) }
            }
            var write = 0
            var prev: Int? = nil
            for i in order {
                if let p = prev, tiles[p].value == tiles[i].value, !tiles[p].absorbing {
                    // Merge: `i` slides under `p` and dies; `p` doubles on
                    // landing. A tile only merges once per move.
                    let s = slot(d, lane, write - 1)
                    setTarget(i, s.col, s.row)
                    tiles[i].dying = true
                    tiles[p].absorbing = true
                    prev = nil
                    movedAny = true
                } else {
                    let s = slot(d, lane, write)
                    if tiles[i].col != s.col || tiles[i].row != s.row {
                        setTarget(i, s.col, s.row)
                        movedAny = true
                    }
                    prev = i
                    write += 1
                }
            }
        }

        guard movedAny else {
            // Nothing budged: the board leans into the wall and shrugs.
            nudgeAt = time
            nudgeDir = d.vec * 0.45
            return
        }
        lastDir = d
        resolveAt = time + Self.slideDur

        // Pick the spawn cell now, from the settled occupancy.
        var taken = Set<Int>()
        for t in tiles where !t.dying { taken.insert(t.col * Self.n + t.row) }
        let empty = (0..<(Self.n * Self.n)).filter { !taken.contains($0) }
        if let cell = empty.randomElement() {
            pendingSpawn = (cell / Self.n, cell % Self.n,
                            Double.random(in: 0..<1) < 0.1 ? 4 : 2)
        }
    }

    private func setTarget(_ i: Int, _ col: Int, _ row: Int) {
        tiles[i].fromCol = tiles[i].col
        tiles[i].fromRow = tiles[i].row
        tiles[i].col = col
        tiles[i].row = row
        tiles[i].movedAt = time
    }

    // MARK: Resolution

    private func resolve() {
        resolveAt = nil
        let l = layout()
        tiles.removeAll { $0.dying }

        var merged: [Int] = []
        for i in tiles.indices where tiles[i].absorbing {
            tiles[i].absorbing = false
            tiles[i].value *= 2
            tiles[i].mergedAt = time
            score += tiles[i].value
            merged.append(tiles[i].value)

            let r = l.rect(Double(tiles[i].col), Double(tiles[i].row))
            let c = Vec2(r.midX, r.midY)
            floaters.append(Floater(pos: Vec2(c.x, c.y - l.cell * 0.4),
                                    text: "+\(tiles[i].value)", bornAt: time,
                                    color: tiles[i].value >= 128
                                        ? Palette.goldDeep : Palette.ink))
            spawnBurst(at: c, big: tiles[i].value >= 128)
        }

        nudgeAt = time
        nudgeDir = lastDir.vec

        if merged.isEmpty {
            Haptics.play(.click, minInterval: 0.06)
        } else {
            lastMergeAt = time
            let top = merged.max() ?? 0
            if top >= 128 {
                shakeAmp = 3.5
                Haptics.play(.notification, minInterval: 0.1)
            } else {
                Haptics.play(.directionUp, minInterval: 0.05)
            }
            if top >= 2048, !celebrated {
                celebrated = true
                let c = Vec2(l.ox + l.board / 2, l.oy + l.board / 2)
                floaters.append(Floater(pos: Vec2(c.x, c.y - 20), text: "2048!",
                                        bornAt: time, color: Palette.goldDeep))
                spawnConfetti(at: c)
                Haptics.play(.success, minInterval: 0)
            }
        }

        if let s = pendingSpawn {
            spawnTile(col: s.col, row: s.row, value: s.value)
            pendingSpawn = nil
        }

        if isStuck() {
            done = true
            Haptics.play(.failure, minInterval: 0)
            let final = score
            let cb = onGameOver
            DispatchQueue.main.async { cb?(final) }
        }
    }

    private func isStuck() -> Bool {
        var grid = [[Int]](repeating: [Int](repeating: 0, count: Self.n), count: Self.n)
        for t in tiles {
            if grid[t.col][t.row] != 0 { return false }   // mid-animation, never stuck
            grid[t.col][t.row] = t.value
        }
        for c in 0..<Self.n {
            for r in 0..<Self.n {
                let v = grid[c][r]
                if v == 0 { return false }
                if c + 1 < Self.n, grid[c + 1][r] == v { return false }
                if r + 1 < Self.n, grid[c][r + 1] == v { return false }
            }
        }
        return true
    }

    // MARK: Spawning

    private func spawnRandomTile() {
        var taken = Set<Int>()
        for t in tiles { taken.insert(t.col * Self.n + t.row) }
        let empty = (0..<(Self.n * Self.n)).filter { !taken.contains($0) }
        guard let cell = empty.randomElement() else { return }
        spawnTile(col: cell / Self.n, row: cell % Self.n,
                  value: Double.random(in: 0..<1) < 0.1 ? 4 : 2)
    }

    private func spawnTile(col: Int, row: Int, value: Int) {
        tiles.append(Tile(id: nextID, value: value, col: col, row: row,
                          fromCol: col, fromRow: row,
                          movedAt: -10, spawnedAt: time, mergedAt: -10))
        nextID += 1
    }

    func reset() {
        tiles.removeAll()
        particles.removeAll()
        floaters.removeAll()
        score = 0
        done = false
        celebrated = false
        resolveAt = nil
        pendingSpawn = nil
        pendingSwipe = nil
        shakeAmp = 0
        spawnRandomTile()
        spawnRandomTile()
    }

    // MARK: Particles

    private func updateParticles(_ dt: Double) {
        guard !particles.isEmpty else { return }
        for i in particles.indices {
            particles[i].life -= dt
            particles[i].pos += particles[i].vel * dt
            particles[i].vel = particles[i].vel * exp(-3.4 * dt)
        }
        particles.removeAll { $0.life <= 0 }
    }

    private func spawnBurst(at p: Vec2, big: Bool) {
        let count = big ? 12 : 6
        for k in 0..<count {
            let a = Double.random(in: 0..<(2 * .pi))
            let s = Double.random(in: 30...(big ? 130 : 80))
            let life = Double.random(in: 0.25...0.5)
            particles.append(Particle(
                pos: p, vel: Vec2(cos(a), sin(a)) * s,
                life: life, maxLife: life,
                size: Double.random(in: 1.4...(big ? 3 : 2.2)),
                hue: big ? (k % 3 == 2 ? .white : .gold) : .white))
        }
    }

    private func spawnConfetti(at p: Vec2) {
        for k in 0..<26 {
            let a = Double.random(in: 0..<(2 * .pi))
            let s = Double.random(in: 60...190)
            let life = Double.random(in: 0.5...1.0)
            particles.append(Particle(
                pos: p, vel: Vec2(cos(a), sin(a)) * s,
                life: life, maxLife: life,
                size: Double.random(in: 1.8...3.2), hue: .confetti(k)))
        }
    }
}
