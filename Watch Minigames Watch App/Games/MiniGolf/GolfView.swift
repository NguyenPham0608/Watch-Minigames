//
//  GameView.swift
//  Minigames Watch App
//
//  Playable hole(s): canvas + slingshot gesture + result overlays. Handles
//  single holes, full rounds, and editor test sessions.
//

import SwiftUI

struct GameView: View {
    let holes: [HoleDesign]
    var isRound: Bool = false
    /// Editor test session: minimal chrome, "Done" returns to the editor.
    var isPractice: Bool = false

    @Environment(ScoreStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var engine: GameEngine
    @State private var result: HoleResult? = nil
    @State private var roundStrokes: [Int] = []
    @State private var showScorecard = false
    @State private var crownZoom = 1.0

    struct HoleResult {
        var strokes: Int
        var par: Int
        var isBestHole: Bool
    }

    init(holes: [HoleDesign], isRound: Bool = false, isPractice: Bool = false) {
        self.holes = holes
        self.isRound = isRound
        self.isPractice = isPractice
        _engine = State(initialValue: GameEngine(hole: holes[0]))
    }

    private var hole: HoleDesign { holes[index] }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation) { timeline in
                    canvasView(size: geo.size, date: timeline.date)
                }
                if showScorecard {
                    scorecard
                } else if let result {
                    resultOverlay(result)
                }
            }
        }
        .ignoresSafeArea()
        .focusable()
        .digitalCrownRotation($crownZoom, from: 0.7, through: 1.5, by: 0.05,
                              sensitivity: .low, isContinuous: false,
                              isHapticFeedbackEnabled: false)
        .onChange(of: crownZoom) { _, newValue in
            engine.zoomTarget = newValue
        }
        .onAppear { wireEngine() }
    }

    // MARK: Canvas (inside TimelineView so it refreshes each frame)

    private func canvasView(size: CGSize, date: Date) -> some View {
        engine.step(to: date)
        let renderer = CourseRenderer(
            hole: hole,
            geo: engine.geo,
            proj: Projection(cam: engine.cam, size: size, zoom: engine.zoom),
            time: engine.time)

        return Canvas { ctx, _ in
            renderer.draw(into: ctx, engine: engine)
        }
        .gesture(aimGesture)
        .onTapGesture { engine.skipIntro() }
    }

    // MARK: Gesture

    private var aimGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                engine.updateAim(drag: value.translation)
            }
            .onEnded { _ in
                engine.releaseAim()
            }
    }

    // MARK: Engine lifecycle

    private func wireEngine() {
        engine.zoom = crownZoom
        engine.zoomTarget = crownZoom
        engine.onEvent = { event in
            switch event {
            case .coin:
                break
            case .sunk(let strokes):
                handleSunk(strokes: strokes)
            }
        }
    }

    private func handleSunk(strokes: Int) {
        store.addCoins(engine.collectedCoins.count)
        var isBest = false
        if !isPractice {
            isBest = store.recordHole(hole, strokes: strokes)
        }
        if isRound { roundStrokes.append(strokes) }
        // Let the confetti and the scoreline popup breathe before the card.
        let pending = HoleResult(strokes: strokes, par: hole.par, isBestHole: isBest)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.3)) {
                result = pending
            }
        }
    }

    private func advance() {
        if isRound && index + 1 < holes.count {
            loadHole(index + 1)
        } else if isRound {
            let total = roundStrokes.reduce(0, +)
            store.recordRound(total: total)
            withAnimation { result = nil; showScorecard = true }
        } else {
            dismiss()
        }
    }

    private func loadHole(_ newIndex: Int) {
        index = newIndex
        engine = GameEngine(hole: holes[newIndex])
        wireEngine()
        withAnimation { result = nil }
    }

    // MARK: Result overlay

    private func resultTitle(_ r: HoleResult) -> String {
        if r.strokes == 1 { return "Ace!" }
        switch r.strokes - r.par {
        case ..<(-1): return "Eagle!"
        case -1: return "Birdie!"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double Bogey"
        default: return "+\(r.strokes - r.par)"
        }
    }

    private func resultOverlay(_ r: HoleResult) -> some View {
        VStack(spacing: 6) {
            Text(resultTitle(r))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(r.strokes <= r.par ? Palette.goldDeep : Palette.ink)
            Text("\(r.strokes) stroke\(r.strokes == 1 ? "" : "s") · Par \(r.par)")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Palette.ink.opacity(0.55))
            if r.isBestHole {
                Text("New Best")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.goldDeep)
            }
            HStack(spacing: 10) {
                overlayButton("arrow.counterclockwise") { loadHole(index) }
                if isPractice {
                    overlayButton("checkmark") { dismiss() }
                } else {
                    overlayButton(isRound && index + 1 >= holes.count ? "flag.checkered" : "arrow.right",
                                  prominent: true) { advance() }
                    if !isRound {
                        overlayButton("list.bullet") { dismiss() }
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.ink, lineWidth: 1.8))
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private func overlayButton(_ symbol: String, prominent: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(prominent ? Palette.gold : Color.white))
                .overlay(Circle().stroke(Palette.ink, lineWidth: 1.6))
                .foregroundStyle(Palette.ink)
        }
        .buttonStyle(.plain)
    }

    // MARK: Scorecard

    private var scorecard: some View {
        let total = roundStrokes.reduce(0, +)
        let parTotal = holes.map(\.par).reduce(0, +)
        let isNewBest = store.bestRound == total
        return ScrollView {
            VStack(spacing: 5) {
                Text("Round Complete")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                if isNewBest {
                    Text("★ New Best Round ★")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.goldDeep)
                }
                ForEach(roundStrokes.indices, id: \.self) { i in
                    HStack {
                        Text("Hole \(i + 1)")
                            .foregroundStyle(Palette.ink.opacity(0.55))
                        Spacer()
                        Text("\(roundStrokes[i])")
                            .fontWeight(.semibold)
                            .foregroundStyle(roundStrokes[i] <= holes[i].par
                                             ? Palette.goldDeep : Palette.ink)
                        Text("/ \(holes[i].par)")
                            .foregroundStyle(Palette.ink.opacity(0.55))
                    }
                    .font(.system(size: 12, design: .rounded))
                }
                Divider().padding(.vertical, 2)
                HStack {
                    Text("Total").fontWeight(.bold)
                    Spacer()
                    Text("\(total) / \(parTotal)").fontWeight(.bold)
                }
                .font(.system(size: 13, design: .rounded))
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Palette.gold))
                        .overlay(Capsule().stroke(Palette.ink, lineWidth: 1.6))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 20)
        }
        .background(Palette.bg)
    }
}
