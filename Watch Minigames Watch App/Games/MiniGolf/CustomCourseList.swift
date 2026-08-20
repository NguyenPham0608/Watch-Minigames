//
//  CustomCourseList.swift
//  Watch Minigames Watch App
//
//  The player's saved courses: tap to play, pencil to reopen in the
//  editor, trash to delete (with a confirm).
//

import SwiftUI

struct CustomCourseList: View {
    @Environment(ScoreStore.self) private var store

    @State private var editing: HoleDesign? = nil
    @State private var deleting: HoleDesign? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if store.customHoles.isEmpty {
                    // Reachable by deleting the last course from here; an
                    // empty ScrollView also collapses to its padding width,
                    // so keep the frame stretched.
                    Text("No saved courses yet.\nDesign one with New Course.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.top, 28)
                }
                ForEach(store.customHoles) { hole in
                    row(hole)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
        }
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle("My Courses")
        .sheet(item: $editing) { hole in
            NavigationStack {
                EditorView(hole: hole)
                    .environment(store)
            }
        }
        .confirmationDialog(
            "Delete \u{201C}\(deleting?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { deleting != nil },
                                 set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let hole = deleting { store.deleteCustom(hole) }
                deleting = nil
            }
        }
    }

    private func row(_ hole: HoleDesign) -> some View {
        HStack(spacing: 6) {
            NavigationLink {
                LazyView { GolfView(holes: [hole]) }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(hole.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(bestLine(hole))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.92)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.ink, lineWidth: 1.3))
            }
            .buttonStyle(BouncyButtonStyle())

            rowButton("pencil") { editing = hole }
            rowButton("trash") { deleting = hole }
        }
    }

    private func rowButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white))
                .overlay(Circle().stroke(Palette.ink, lineWidth: 1.3))
                .foregroundStyle(Palette.ink)
        }
        .buttonStyle(BouncyButtonStyle())
    }

    private func bestLine(_ hole: HoleDesign) -> String {
        if let best = store.best(for: hole) {
            return "Par \(hole.par) \u{00B7} Best \(best)"
        }
        return "Par \(hole.par)"
    }
}
