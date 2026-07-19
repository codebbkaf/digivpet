import SwiftUI

/// The field guide: every Digimon in the roster, with the ones you have raised filled in.
///
/// The top level is a list of evolution lines, not the roster itself — each row opens that line's
/// `EvolutionTreeView`. That is what keeps the screen affordable at 865 entries now that a node is
/// drawn in a tree: the list rows are text, so opening the Dex decodes no art at all, and a tree
/// only ever decodes the one line it was opened for.
struct DexView: View {
    @StateObject private var model: DexModel
    @State private var selected: DexRow?

    #if DEBUG
    @State private var showsLineDemo = CommandLine.arguments.contains("-dexLineDemo")
    #endif

    /// As in `ContentView`: passed in rather than defaulted, because building one is a
    /// `@MainActor` call and a default argument would run in this non-isolated `init`.
    init(model: @autoclosure @escaping () -> DexModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        List(model.sections) { section in
            NavigationLink {
                destination(for: section)
            } label: {
                DexSectionRow(section: section)
            }
        }
        .navigationTitle("\(model.discoveredCount)/\(model.totalCount)")
        .sheet(item: $selected) { row in
            DexDetailView(row: row)
        }
        #if DEBUG
        // Debug-only: `simctl` cannot tap a list row, so an opened line is unscreenshottable
        // without a way to push one from the launch command — the same reason `-dexDemo` exists
        // to push this screen at all. Compiled out of release builds.
        .navigationDestination(isPresented: $showsLineDemo) {
            if let section = demoSection { destination(for: section) }
        }
        #endif
        .onAppear {
            if !model.isLoaded { model.load() }
            #if DEBUG
            selectFirstDiscoveredIfRequested()
            #endif
        }
    }

    /// A line gets its tree; `Others` has no edges to draw, so it keeps the flat grid.
    @ViewBuilder
    private func destination(for section: DexSection) -> some View {
        if section.isLine {
            EvolutionTreeView(rows: section.rows)
                .navigationTitle(section.title)
        } else {
            DexGridView(rows: section.rows)
                .navigationTitle(section.title)
        }
    }

    #if DEBUG
    /// The line `-dexLineDemo` opens: Agumon's, because it is the one shipped line that branches,
    /// so a screenshot of it shows a fork and its converging connectors rather than a straight
    /// ladder. Falls back to the first line so the arg still lands somewhere if that changes.
    private var demoSection: DexSection? {
        model.sections.first { $0.id == "agumon" } ?? model.sections.first
    }

    /// Debug-only: sets exactly the state a tap sets, so the detail sheet can be screenshotted.
    /// `simctl` has no touch command and Simulator UI scripting needs an accessibility grant this
    /// machine does not have, so a real tap cannot be synthesised. Compiled out of release builds.
    private func selectFirstDiscoveredIfRequested() {
        guard CommandLine.arguments.contains("-dexDetailDemo") else { return }
        selected = model.rows.first { $0.isDiscovered }
    }
    #endif
}

/// One row of the line list: the line's name and how much of it has been met.
///
/// Text only, deliberately. Showing the line's namesake sprite here would decode one image per
/// line the moment the Dex opens, which is exactly the eagerness the list exists to avoid.
private struct DexSectionRow: View {
    let section: DexSection

    var body: some View {
        HStack {
            Text(section.title)
                .font(.body)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(section.discoveredCount)/\(section.totalCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

/// The flat grid, now only for `Others` — the 157 idle-frame-only Digimon, which are in no edge
/// and so have no tree to be drawn in.
///
/// A `LazyVGrid` inside a `ScrollView`, which is what keeps that section affordable: only the
/// cells on screen are built, so only their sprites are ever decoded.
struct DexGridView: View {
    let rows: [DexRow]

    @State private var selected: DexRow?

    /// Three 32pt columns fit a 41mm watch, the narrowest screen the app supports.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(rows) { row in
                    Button {
                        selected = row
                    } label: {
                        DexCell(row: row)
                    }
                    .buttonStyle(.plain)
                    // Undiscovered entries are still tappable, but there is nothing to tell.
                    .disabled(!row.isDiscovered)
                }
            }
            .padding(.horizontal, 2)
        }
        .sheet(item: $selected) { row in
            DexDetailView(row: row)
        }
    }
}

/// One grid cell: the Digimon's idle sprite, or a placeholder if it has never been met.
private struct DexCell: View {
    let row: DexRow

    var body: some View {
        Group {
            if row.isDiscovered {
                IdleSpriteView(stage: row.node.stage.rawValue, name: row.node.spriteFile)
            } else {
                // A "?" rather than a silhouette: a silhouette would have to be derived from the
                // sprite, which would mean decoding the very art this screen is withholding.
                Text("?")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, height: 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
    }
}

/// What is known about one discovered Digimon.
struct DexDetailView: View {
    let row: DexRow

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                IdleSpriteView(stage: row.node.stage.rawValue, name: row.node.spriteFile, scale: 4)

                Text(row.node.displayName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)

                Text(row.node.stage.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let firstDiscovered = row.firstDiscovered {
                    Text("First met \(firstDiscovered.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    NavigationStack {
        DexView(model: DexModel())
    }
}
