//
//  GolfView.swift
//  Watch Minigames Watch App
//
//  Playable hole(s): canvas + slingshot gesture + result overlays. Handles
//  single holes, full rounds, and editor test sessions.
//

import SwiftUI

struct GolfView: View {
    let holes: [HoleDesign]
    var isRound: Bool = false
    /// Editor test session: minimal chrome, "Done" returns to the editor.
    var isPractice: Bool = false

    @Environment(ScoreStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var engine: GolfEngine
    @State private var renderCache: GolfRenderCache
    @State private var result: HoleResult? = nil
    @State private var roundStrokes: [Int] = []
    @State private var showScorecard = false
    @State private var roundWasBest = false
    @State private var crownZoom = 1.0

    struct HoleResult {
        var strokes: Int
        var par: Int
        var isBestHole: Bool
    }

    init(holes: [HoleDesign], isRound: Bool = false, isPractice: Bool = false) {
        // Never trust an empty list — a placeholder hole beats a crash.
        let safeHoles = holes.isEmpty ? [HoleDesign.newCustom(number: 1)] : holes
        self.holes = safeHoles
        self.isRound = isRound
        self.isPractice = isPractice
        _engine = State(initialValue: GolfEngine(hole: safeHoles[0]))
        _renderCache = State(initialValue: GolfRenderCache(hole: safeHoles[0]))
    }

    private var hole: HoleDesign { holes[index] }

    var body: some View {
        ArcadeScreen { size, date in
            canvasView(size: size, date: date)
        } overlay: {
            Group {
                if showScorecard {
                    scorecard
                } else if let result {
                    resultOverlay(result)
                }
            }
        }
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
            proj: CourseProjection(cam: engine.cam, size: size, zoom: engine.zoom),
            time: engine.time,
            cache: renderCache)

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
            case .sunk(let strokes):
                handleSunk(strokes: strokes)
            }
        }
    }

    private func handleSunk(strokes: Int) {
        var isBest = false
        if !isPractice {
            isBest = store.recordHole(hole, strokes: strokes)
        }
        if isRound { roundStrokes.append(strokes) }
        // Let the confetti and the scoreline popup breathe before the card.
        let pending = HoleResult(strokes: strokes, par: hole.par, isBestHole: isBest)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.arcadePop) {
                result = pending
            }
        }
    }

    private func advance() {
        // Coins bank once per completed hole — never in practice, and a
        // retry discards them along with the hole.
        if !isPractice { store.addCoins(engine.collectedCoins.count) }
        if isRound && index + 1 < holes.count {
            loadHole(index + 1)
        } else if isRound {
            let total = roundStrokes.reduce(0, +)
            roundWasBest = store.recordRound(total: total)
            withAnimation(.arcadePop) { result = nil; showScorecard = true }
        } else {
            dismiss()
        }
    }

    private func loadHole(_ newIndex: Int) {
        index = newIndex
        engine = GolfEngine(hole: holes[newIndex])
        renderCache = GolfRenderCache(hole: holes[newIndex])
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
        ResultCard(title: resultTitle(r),
                   subtitle: "\(r.strokes) stroke\(r.strokes == 1 ? "" : "s") · Par \(r.par)",
                   titleGold: r.strokes <= r.par,
                   detail: r.isBestHole ? "New Best" : nil,
                   horizontalPadding: 16) {
            OverlayCircleButton(symbol: "arrow.counterclockwise") { loadHole(index) }
            if isPractice {
                OverlayCircleButton(symbol: "checkmark") { dismiss() }
            } else {
                OverlayCircleButton(symbol: isRound && index + 1 >= holes.count
                                    ? "flag.checkered" : "arrow.right",
                                    prominent: true) { advance() }
                if !isRound {
                    OverlayCircleButton(symbol: "list.bullet") { dismiss() }
                }
            }
        }
    }

    // MARK: Scorecard

    private var scorecard: some View {
        let total = roundStrokes.reduce(0, +)
        let parTotal = holes.map(\.par).reduce(0, +)
        let isNewBest = roundWasBest
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
                .buttonStyle(BouncyButtonStyle())
                .padding(.top, 6)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 20)
        }
        .background(Palette.bg)
    }
}
