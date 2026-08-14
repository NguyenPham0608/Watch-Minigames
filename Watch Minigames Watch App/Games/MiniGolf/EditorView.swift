//
//  EditorView.swift
//  Watch Minigames Watch App
//
//  On-watch course editor. Select something, then a tool decides what dragging
//  and the crown do to it — move a point, stretch a whole section, or swing
//  everything past it around a bend.
//

import SwiftUI

/// What dragging and the crown do to the current selection.
enum EditTool: Hashable {
    case zoom            // nothing selected
    case move            // waypoint: move just this point; crown sets width
    case stretch         // waypoint: carry this point and the rest of the course
    case bend            // waypoint: swing the rest of the course around the previous point
    case place           // tee / cup
    case rotate          // obstacle
    case size            // obstacle

    var label: String {
        switch self {
        case .zoom: return "Zoom"
        case .move: return "Width"
        case .stretch: return "Stretch"
        case .bend: return "Bend"
        case .place: return "Place"
        case .rotate: return "Rotate"
        case .size: return "Size"
        }
    }

    var symbol: String {
        switch self {
        case .zoom: return "plus.magnifyingglass"
        case .move: return "arrow.left.and.right"
        case .stretch: return "arrow.up.left.and.arrow.down.right"
        case .bend: return "arrow.trianglehead.turn.up.right.diamond"
        case .place: return "hand.tap"
        case .rotate: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .size: return "circle.dashed.inset.filled"
        }
    }
}

struct EditorView: View {
    @Environment(ScoreStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: HoleDesign
    @State private var geo: FairwayGeometry
    @State private var renderCache: GolfRenderCache
    @State private var selection: Selection = .none
    @State private var cam: Vec2
    @State private var zoom = 0.9
    @State private var wpTool: EditTool = .move
    @State private var obTool: EditTool = .rotate
    @State private var dragging: DragTarget? = nil
    /// Waypoint positions captured when a drag began, so multi-point edits
    /// stay anchored instead of drifting.
    @State private var snapshot: [[Waypoint]] = []
    /// The dragged obstacle as it was when the drag began (portals use it to
    /// keep the other end pinned while one end moves).
    @State private var obstacleSnapshot: Obstacle? = nil
    /// Handle position minus touch position at drag start, so a grab slightly
    /// off-center doesn't teleport the handle to the fingertip.
    @State private var grabOffset = Vec2.zero
    @State private var showPalette = false
    @State private var showTest = false
    @State private var showSave = false
    @State private var courseName: String
    /// Throttle for interactive rebuilds: drags and crown bursts rebuild the
    /// SDF pipeline at most ~15×/s, with a pending item guaranteeing a
    /// trailing rebuild when a burst stops mid-interval.
    @State private var lastRebuildAt = 0.0
    @State private var pendingRebuild: DispatchWorkItem? = nil

    enum Selection: Equatable {
        case none
        case waypoint(Int, Int)   // (path, index): path 0 = main fairway
        case obstacle(UUID)
        /// A portal's landing pad — draggable independently of its mouth.
        case portalExit(UUID)
        case tee
        case cup
    }

    enum DragTarget {
        case selection
        case pan(startCam: Vec2)
    }

    /// True when building a brand-new course (vs editing an existing one).
    private let isNew: Bool

    init(hole: HoleDesign?, newNumber: Int = 1) {
        isNew = hole == nil
        let h = hole ?? HoleDesign.newCustom(number: newNumber)
        _draft = State(initialValue: h)
        _geo = State(initialValue: FairwayGeometry(paths: h.allPaths))
        _renderCache = State(initialValue: GolfRenderCache(hole: h))
        _cam = State(initialValue: Vec2((h.tee.x + h.cup.x) / 2, (h.tee.y + h.cup.y) / 2))
        _courseName = State(initialValue: h.name)
    }

    // MARK: Current tool

    private var tool: EditTool {
        switch selection {
        case .none: return .zoom
        case .waypoint: return wpTool
        case .obstacle: return obTool
        case .portalExit, .tee, .cup: return .place
        }
    }

    private var toolCycle: [EditTool] {
        switch selection {
        case .waypoint: return [.move, .stretch, .bend]
        case .obstacle: return [.rotate, .size]
        default: return []
        }
    }

    private func cycleTool() {
        let options = toolCycle
        guard options.count > 1 else { return }
        let next = options[((options.firstIndex(of: tool) ?? 0) + 1) % options.count]
        switch selection {
        case .waypoint: wpTool = next
        case .obstacle: obTool = next
        default: break
        }
    }

    // MARK: Body

    var body: some View {
        GeometryReader { screen in
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    editorCanvas(size: screen.size,
                                 t: timeline.date.timeIntervalSinceReferenceDate)
                }
                .gesture(editGesture(size: screen.size))

                controls
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .crownDetents { delta in applyCrown(delta: delta) }
        .sheet(isPresented: $showPalette) { palette }
        .sheet(isPresented: $showTest) {
            NavigationStack {
                GolfView(holes: [draft], isPractice: true)
                    .environment(store)
            }
        }
        .sheet(isPresented: $showSave) { savePanel }
    }

    // MARK: Canvas

    @ViewBuilder
    private func editorCanvas(size: CGSize, t: Double) -> some View {
        let proj = CourseProjection(cam: cam, size: size, zoom: zoom)
        let renderer = CourseRenderer(hole: draft, geo: geo, proj: proj, time: t,
                                      cache: renderCache)
        Canvas { ctx, _ in
            renderer.draw(into: ctx, engine: nil)
            drawEditorOverlay(ctx, proj: proj, t: t)
        }
    }

    private func drawEditorOverlay(_ ctx: GraphicsContext, proj: CourseProjection, t: Double) {
        // Guides for the selected waypoint: the section being edited, and the
        // width bar the crown adjusts.
        if case .waypoint(let sp, let i) = selection, i < pathRef(sp).count {
            let pts = pathRef(sp)
            let wp = pts[i]
            let a = anchorIndex(path: sp, for: i)
            if a != i {
                var guideLine = Path()
                guideLine.move(to: proj.point(pts[a].pos))
                guideLine.addLine(to: proj.point(wp.pos))
                ctx.stroke(guideLine, with: .color(Palette.gold.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                // Mark the pivot the section stretches from / bends around.
                let ap = proj.point(pts[a].pos)
                ctx.stroke(Path(ellipseIn: CGRect(x: ap.x - 4, y: ap.y - 4, width: 8, height: 8)),
                           with: .color(Palette.gold), style: StrokeStyle(lineWidth: 1.4))
            }
            if wpTool == .move {
                let dir = sectionDirection(path: sp, at: i).perp
                var bar = Path()
                bar.move(to: proj.point(wp.pos + dir * (wp.width / 2)))
                bar.addLine(to: proj.point(wp.pos - dir * (wp.width / 2)))
                ctx.stroke(bar, with: .color(Palette.gold.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }

        // Waypoint handles on every path.
        for (sp, pts) in draft.allPaths.enumerated() {
            for (i, wp) in pts.enumerated() {
                let p = proj.point(wp.pos)
                let isSel = selection == .waypoint(sp, i)
                let r: Double = isSel ? 7 : 5
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(isSel ? 0.95 : 0.6)))
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .color(Palette.ink.opacity(0.7)), style: StrokeStyle(lineWidth: 1.2))
                if isSel { selectionRing(ctx, at: p, radius: r + 4, t: t) }
            }
        }

        // Tee marker.
        let teeP = proj.point(draft.tee)
        var teePath = Path()
        teePath.addRect(CGRect(x: teeP.x - 4, y: teeP.y - 4, width: 8, height: 8))
        ctx.fill(teePath, with: .color(Color(red: 0.45, green: 0.62, blue: 0.82)))
        ctx.stroke(teePath, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.2))
        if selection == .tee { selectionRing(ctx, at: teeP, radius: 9, t: t) }
        if selection == .cup { selectionRing(ctx, at: proj.point(draft.cup), radius: 10, t: t) }

        if case .obstacle(let id) = selection,
           let o = draft.obstacles.first(where: { $0.id == id }) {
            selectionRing(ctx, at: proj.point(o.pos),
                          radius: selectionRadius(for: o) * zoom + 5, t: t)
            if o.kind == .portal { drawPortalLink(ctx, o, proj: proj) }
        }
        if case .portalExit(let id) = selection,
           let o = draft.obstacles.first(where: { $0.id == id }) {
            selectionRing(ctx, at: proj.point(o.portalExit), radius: 14, t: t)
            drawPortalLink(ctx, o, proj: proj)
        }
    }

    /// Dashed guide between a portal's two ends while either is selected,
    /// tinted with the pair's own hue.
    private func drawPortalLink(_ ctx: GraphicsContext, _ o: Obstacle, proj: CourseProjection) {
        let index = draft.obstacles.filter { $0.kind == .portal }
            .firstIndex { $0.id == o.id } ?? 0
        var link = Path()
        link.move(to: proj.point(o.pos))
        link.addLine(to: proj.point(o.portalExit))
        ctx.stroke(link, with: .color(Palette.portalHue(index).main.opacity(0.9)),
                   style: StrokeStyle(lineWidth: 1.6, dash: [3, 3]))
    }

    private func selectionRing(_ ctx: GraphicsContext, at p: CGPoint, radius: Double, t: Double) {
        var ring = Path()
        ring.addEllipse(in: CGRect(x: p.x - radius, y: p.y - radius,
                                   width: radius * 2, height: radius * 2))
        ctx.stroke(ring, with: .color(Palette.gold),
                   style: StrokeStyle(lineWidth: 1.6, dash: [4, 3], dashPhase: t * 8))
    }

    private func selectionRadius(for o: Obstacle) -> Double {
        switch o.kind {
        case .bumper: return o.bumperRadius + 4
        case .sand: return o.sandRadius
        case .boost: return max(o.boostHalfLength, o.boostHalfWidth) + 4
        case .arcWall: return o.arcRadius
        case .pillar: return o.pillarRadius + 4
        case .barrier: return o.barrierHalfLength + 4
        case .spinner: return o.spinnerArmLength + 4
        case .coin: return o.coinRadius + 6
        case .hill: return o.hillRadius
        case .vortex: return o.vortexRadius
        case .fan: return 12 * o.scale + 4
        case .portal: return o.portalRadius + 6
        case .tree: return o.treeRadius + 8
        case .flowers: return 12 * o.scale
        }
    }

    // MARK: Path accessors

    private func pathRef(_ p: Int) -> [Waypoint] {
        if p == 0 { return draft.waypoints }
        let islands = draft.islands ?? []
        return p - 1 < islands.count ? islands[p - 1] : []
    }

    private func modifyPath(_ p: Int, _ body: (inout [Waypoint]) -> Void) {
        if p == 0 {
            body(&draft.waypoints)
        } else if var islands = draft.islands, p - 1 < islands.count {
            body(&islands[p - 1])
            draft.islands = islands
        }
    }

    // MARK: Waypoint section helpers

    /// The point a section pivots around: the previous waypoint, or the next
    /// one when the first waypoint is selected.
    private func anchorIndex(path p: Int, for i: Int) -> Int {
        if i > 0 { return i - 1 }
        return pathRef(p).count > 1 ? 1 : 0
    }

    /// Waypoints carried along by stretch/bend: everything from `i` onward, or
    /// just the first point when it is the one selected.
    private func affected(path p: Int, from i: Int) -> Range<Int> {
        let count = pathRef(p).count
        guard i > 0 else { return 0..<min(1, count) }
        return min(i, count)..<count
    }

    private func sectionDirection(path p: Int, at i: Int) -> Vec2 {
        let a = anchorIndex(path: p, for: i)
        guard a != i else { return Vec2(0, -1) }
        let pts = pathRef(p)
        guard i < pts.count, a < pts.count else { return Vec2(0, -1) }
        return (pts[i].pos - pts[a].pos).normalized
    }

    // MARK: Gesture

    private func editGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let proj = CourseProjection(cam: cam, size: size, zoom: zoom)
                if dragging == nil {
                    if let hit = hitTest(value.startLocation, proj: proj) {
                        selection = hit
                        snapshot = draft.allPaths
                        if case .obstacle(let id) = hit {
                            obstacleSnapshot = draft.obstacles.first { $0.id == id }
                        } else {
                            obstacleSnapshot = nil
                        }
                        let handle = selectionWorldPosition(hit)
                        grabOffset = handle.map { $0 - worldPoint(value.startLocation, proj: proj) }
                            ?? .zero
                        dragging = .selection
                    } else {
                        dragging = .pan(startCam: cam)
                    }
                }
                switch dragging {
                case .selection:
                    // A plain tap selects without nudging: movement only
                    // starts once the finger has clearly traveled.
                    if hypot(value.translation.width, value.translation.height) > 6 {
                        moveSelection(to: value.location, proj: proj)
                    }
                case .pan(let startCam):
                    cam = Vec2(startCam.x - Double(value.translation.width) / zoom,
                               startCam.y - Double(value.translation.height) / zoom)
                case nil:
                    break
                }
            }
            .onEnded { value in
                if case .pan = dragging,
                   hypot(value.translation.width, value.translation.height) < 6 {
                    selection = .none
                }
                if case .selection = dragging { clampTeeAndCup() }
                dragging = nil
            }
    }

    private func hitTest(_ screenPoint: CGPoint, proj: CourseProjection) -> Selection? {
        var best: Selection? = nil
        var bestD = 22.0

        func consider(_ sel: Selection, _ world: Vec2, bonus: Double = 0) {
            let p = proj.point(world)
            let d = hypot(p.x - screenPoint.x, p.y - screenPoint.y) - bonus
            if d < bestD { bestD = d; best = sel }
        }

        for (sp, pts) in draft.allPaths.enumerated() {
            for (i, wp) in pts.enumerated() { consider(.waypoint(sp, i), wp.pos) }
        }
        consider(.tee, draft.tee, bonus: 2)
        consider(.cup, draft.cup, bonus: 2)
        for o in draft.obstacles {
            consider(.obstacle(o.id), o.pos, bonus: 4)
            if o.kind == .portal { consider(.portalExit(o.id), o.portalExit, bonus: 4) }
        }
        return best
    }

    /// Re-derives a portal's aim and reach so its exit lands on `exit`.
    private func aimPortal(_ index: Int, exitAt exit: Vec2) {
        let delta = exit - draft.obstacles[index].pos
        guard delta.length > 8 else { return }
        // No upper bound: a portal can reach across the whole course.
        draft.obstacles[index].scale = max(delta.length / 74, 0.15)
        draft.obstacles[index].rot = atan2(delta.x, -delta.y)
    }

    /// Screen point back to world space (the projection's scale depends on the
    /// point's own depth, so solve it by iterating).
    private func worldPoint(_ screenPoint: CGPoint, proj: CourseProjection) -> Vec2 {
        var world = cam
        for _ in 0..<3 {
            let f = proj.factor(world)
            world = Vec2(
                cam.x + (Double(screenPoint.x) - Double(proj.size.width) / 2) / (zoom * f),
                cam.y + (Double(screenPoint.y) - Double(proj.size.height) / 2) / (zoom * f))
        }
        return world
    }

    /// Current world position of a selectable handle.
    private func selectionWorldPosition(_ sel: Selection) -> Vec2? {
        switch sel {
        case .waypoint(let sp, let i):
            let pts = pathRef(sp)
            return i < pts.count ? pts[i].pos : nil
        case .obstacle(let id): return draft.obstacles.first { $0.id == id }?.pos
        case .portalExit(let id): return draft.obstacles.first { $0.id == id }?.portalExit
        case .tee: return draft.tee
        case .cup: return draft.cup
        case .none: return nil
        }
    }

    private func moveSelection(to screenPoint: CGPoint, proj: CourseProjection) {
        let world = worldPoint(screenPoint, proj: proj) + grabOffset
        switch selection {
        case .waypoint(let sp, let i):
            guard sp < snapshot.count, i < snapshot[sp].count else { break }
            let snap = snapshot[sp]
            switch wpTool {
            case .stretch:
                // Carry this point and everything after it, so the section
                // grows or shrinks without reshaping the rest of the course.
                let delta = world - snap[i].pos
                modifyPath(sp) { pts in
                    for k in self.affected(path: sp, from: i) {
                        pts[k].pos = snap[k].pos + delta
                    }
                }
            case .bend:
                // Swing everything from here on around the pivot.
                let anchor = snap[anchorIndex(path: sp, for: i)].pos
                let from = snap[i].pos - anchor
                let to = world - anchor
                guard from.lengthSquared > 1, to.lengthSquared > 1 else { break }
                let angle = atan2(from.cross(to), from.dot(to))
                modifyPath(sp) { pts in
                    for k in self.affected(path: sp, from: i) {
                        pts[k].pos = anchor + (snap[k].pos - anchor).rotated(by: angle)
                    }
                }
            default:
                modifyPath(sp) { $0[i].pos = world }
            }
            rebuildGeometryThrottled()
        case .obstacle(let id):
            if let idx = draft.obstacles.firstIndex(where: { $0.id == id }) {
                draft.obstacles[idx].pos = world
                // Dragging a portal's mouth leaves its landing pad in place.
                if let snap = obstacleSnapshot, snap.id == id, snap.kind == .portal {
                    aimPortal(idx, exitAt: snap.portalExit)
                }
            }
        case .portalExit(let id):
            if let idx = draft.obstacles.firstIndex(where: { $0.id == id }) {
                aimPortal(idx, exitAt: world)
            }
        case .tee: draft.tee = world
        case .cup: draft.cup = world
        case .none: break
        }
    }

    private func clampTeeAndCup() {
        // Never clamp against land a throttled rebuild hasn't traced yet.
        flushPendingRebuild()
        if !geo.contains(draft.tee) { draft.tee = geo.nearestCenterPoint(to: draft.tee) }
        if !geo.contains(draft.cup) { draft.cup = geo.nearestCenterPoint(to: draft.cup) }
    }

    /// Full rebuild, immediately: the SDF pipeline, boundary loops, and a
    /// fresh render cache (a changed course invalidates every stored path).
    private func rebuildGeometry() {
        pendingRebuild?.cancel()
        pendingRebuild = nil
        lastRebuildAt = Date().timeIntervalSinceReferenceDate
        geo = FairwayGeometry(paths: draft.allPaths)
        renderCache = GolfRenderCache(hole: draft)
    }

    /// Rebuild for continuous edits (drag frames, crown ticks): leading-edge
    /// immediate, then at most one rebuild per 1/15 s while the burst keeps
    /// going, with a guaranteed trailing rebuild carrying the final state.
    /// `thenClamp` re-runs the tee/cup clamp after each rebuild that fires.
    private func rebuildGeometryThrottled(thenClamp: Bool = false) {
        let interval = 1.0 / 15.0
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastRebuildAt >= interval {
            rebuildGeometry()
            if thenClamp { clampTeeAndCup() }
        } else {
            pendingRebuild?.cancel()
            let work = DispatchWorkItem {
                rebuildGeometry()
                if thenClamp { clampTeeAndCup() }
            }
            pendingRebuild = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (lastRebuildAt + interval - now),
                                          execute: work)
        }
    }

    /// Runs a queued trailing rebuild right now, so geometry consumers
    /// (clamping, testing, saving) never read stale land.
    private func flushPendingRebuild() {
        guard pendingRebuild != nil else { return }
        rebuildGeometry()
    }

    // MARK: Crown

    private func applyCrown(delta: Double) {
        guard abs(delta) > 0.001 else { return }
        switch selection {
        case .none:
            zoom = min(max(zoom * (1 + delta * 0.012), 0.5), 1.6)

        case .waypoint(let sp, let i):
            switch wpTool {
            case .stretch:
                let dir = sectionDirection(path: sp, at: i)
                let move = dir * (delta * 1.4)
                modifyPath(sp) { pts in
                    for k in self.affected(path: sp, from: i) { pts[k].pos += move }
                }
            case .bend:
                let path = pathRef(sp)
                let a = anchorIndex(path: sp, for: i)
                guard a < path.count else { return }
                let anchor = path[a].pos
                let angle = delta * 0.02
                modifyPath(sp) { pts in
                    for k in self.affected(path: sp, from: i) {
                        pts[k].pos = anchor + (pts[k].pos - anchor).rotated(by: angle)
                    }
                }
            default:
                modifyPath(sp) { pts in
                    guard i < pts.count else { return }
                    pts[i].width = min(max(pts[i].width + delta * 1.1, 34), 150)
                }
            }
            rebuildGeometryThrottled(thenClamp: true)

        case .obstacle(let id):
            guard let idx = draft.obstacles.firstIndex(where: { $0.id == id }) else { return }
            if obTool == .size {
                let grown = draft.obstacles[idx].scale * (1 + delta * 0.015)
                // Portal scale is reach, and reach is unlimited.
                draft.obstacles[idx].scale = draft.obstacles[idx].kind == .portal
                    ? max(grown, 0.15)
                    : min(max(grown, 0.5), 3)
            } else {
                draft.obstacles[idx].rot += delta * 0.035
            }

        case .portalExit(let id):
            // Crown nudges the landing pad farther from / closer to the mouth.
            // No upper bound on reach.
            guard let idx = draft.obstacles.firstIndex(where: { $0.id == id }) else { return }
            draft.obstacles[idx].scale = max(draft.obstacles[idx].scale
                                             * (1 + delta * 0.012), 0.15)

        case .tee, .cup:
            break
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 5) {
            HStack {
                // The sheet's system close button lives in the top-left;
                // this spacer keeps the title centered clear of it.
                Color.clear.frame(width: 30, height: 30)
                Spacer()
                Text(draft.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.92)))
                    .overlay(Capsule().stroke(Palette.ink, lineWidth: 1.3))
                Spacer()
                // Keep clear of the system clock in the top-right corner.
                Color.clear.frame(width: 30, height: 30)
            }
            Spacer()
            toolPill
            HStack(spacing: 8) {
                smallButton("plus") { showPalette = true }
                if deletable { smallButton("trash") { deleteSelection() } }
                Spacer()
                smallButton("play.fill") {
                    clampTeeAndCup()
                    showTest = true
                }
                smallButton("checkmark", fill: Palette.gold) { showSave = true }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    /// Always says what the crown is about to do; tap to switch tools.
    private var toolPill: some View {
        let canCycle = toolCycle.count > 1
        return Button {
            cycleTool()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(tool.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                if canCycle {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 8, weight: .bold))
                        .opacity(0.5)
                }
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(canCycle ? Palette.gold.opacity(0.9) : .white.opacity(0.9)))
            .overlay(Capsule().stroke(Palette.ink, lineWidth: 1.3))
        }
        .buttonStyle(.plain)
        .disabled(!canCycle)
    }

    private var deletable: Bool {
        switch selection {
        case .obstacle, .portalExit: return true
        case .waypoint(let sp, _):
            // Island points are always deletable (deleting the last two
            // removes the island); the main fairway keeps at least two.
            return sp > 0 || draft.waypoints.count > 2
        default: return false
        }
    }

    private func deleteSelection() {
        switch selection {
        case .obstacle(let id), .portalExit(let id):
            draft.obstacles.removeAll { $0.id == id }
        case .waypoint(let sp, let i):
            if sp == 0 {
                guard draft.waypoints.count > 2 else { break }
                draft.waypoints.remove(at: i)
            } else if var islands = draft.islands, sp - 1 < islands.count {
                if islands[sp - 1].count > 2 {
                    islands[sp - 1].remove(at: i)
                } else {
                    islands.remove(at: sp - 1)
                }
                draft.islands = islands.isEmpty ? nil : islands
            }
            rebuildGeometry()
            clampTeeAndCup()
        default: break
        }
        selection = .none
    }

    private func smallButton(_ symbol: String, fill: Color = .white,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Circle().fill(fill.opacity(0.94)))
                .overlay(Circle().stroke(Palette.ink, lineWidth: 1.4))
                .foregroundStyle(Palette.ink)
        }
        .buttonStyle(.plain)
    }

    // MARK: Palette

    private var palette: some View {
        List {
            Button {
                addWaypoint()
                showPalette = false
            } label: {
                Label("Fairway Point", systemImage: "point.3.connected.trianglepath.dotted")
            }
            Button {
                addIsland()
                showPalette = false
            } label: {
                Label("Island", systemImage: "plus.square.on.square")
            }
            ForEach(ObstacleKind.allCases, id: \.self) { kind in
                Button {
                    addObstacle(kind)
                    showPalette = false
                } label: {
                    Label(kind.displayName, systemImage: kind.symbol)
                }
            }
        }
        .font(.system(size: 13, design: .rounded))
    }

    private func addWaypoint() {
        var sp = 0
        var idx = 0
        if case .waypoint(let p, let i) = selection {
            sp = p
            idx = i
        } else {
            var bestD = Double.infinity
            for (p, pts) in draft.allPaths.enumerated() {
                for (i, wp) in pts.enumerated() {
                    let d = wp.pos.distance(to: cam)
                    if d < bestD { bestD = d; sp = p; idx = i }
                }
            }
        }
        let pts = pathRef(sp)
        let a = pts[idx]
        let b = idx + 1 < pts.count ? pts[idx + 1] : nil
        let newPos = b.map { a.pos.lerp(to: $0.pos, 0.5) } ?? a.pos + Vec2(0, -70)
        let newWidth = b.map { (a.width + $0.width) / 2 } ?? a.width
        modifyPath(sp) { $0.insert(Waypoint(pos: newPos, width: newWidth), at: idx + 1) }
        selection = .waypoint(sp, idx + 1)
        rebuildGeometry()
    }

    /// Drops a fresh strip of land near the camera. An island must start life
    /// detached, so the drop point is nudged away from existing land until the
    /// strip has clear water around it — merge it into the course later by
    /// deliberately stretching it there.
    private func addIsland() {
        let halfLen = 45.0
        let width = 64.0

        func isClear(_ c: Vec2) -> Bool {
            for p in [c, c + Vec2(0, halfLen), c - Vec2(0, halfLen)] {
                let n = geo.nearest(p)
                if n.dist - n.half < width / 2 + 22 { return false }
            }
            return true
        }

        var center = cam + Vec2(440, 0)
        if isClear(cam) {
            center = cam
        } else {
            let dirs = [Vec2(1, 0), Vec2(-1, 0), Vec2(0, 1), Vec2(0, -1),
                        Vec2(0.7, 0.7), Vec2(-0.7, 0.7), Vec2(0.7, -0.7), Vec2(-0.7, -0.7)]
            search: for radius in stride(from: 70.0, through: 400.0, by: 45.0) {
                for d in dirs where isClear(cam + d * radius) {
                    center = cam + d * radius
                    break search
                }
            }
        }

        let island = [
            Waypoint(pos: center + Vec2(0, halfLen), width: width),
            Waypoint(pos: center - Vec2(0, halfLen), width: width),
        ]
        draft.islands = (draft.islands ?? []) + [island]
        selection = .waypoint(draft.allPaths.count - 1, 0)
        cam = center
        rebuildGeometry()
    }

    private func addObstacle(_ kind: ObstacleKind) {
        let o = Obstacle(kind: kind, pos: cam)
        draft.obstacles.append(o)
        selection = .obstacle(o.id)
        obTool = .rotate
    }

    // MARK: Save

    private var savePanel: some View {
        VStack(spacing: 10) {
            Text("Save Course")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            TextField("Name", text: $courseName)
                .font(.system(size: 13, design: .rounded))
            Stepper(value: $draft.par, in: 1...9) {
                Text("Par \(draft.par)")
                    .font(.system(size: 13, design: .rounded))
            }
            Button {
                clampTeeAndCup()
                var toSave = draft
                toSave.name = courseName.isEmpty ? draft.name : courseName
                if isNew {
                    // Claim the course number only on a real save, so a
                    // cancelled editor never burns one.
                    _ = store.nextCustomNumber()
                }
                store.saveCustom(toSave)
                showSave = false
                dismiss()
            } label: {
                Text("Save")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.gold.opacity(0.85))
            .foregroundStyle(.black)
        }
        .padding()
    }
}
