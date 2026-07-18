import SwiftUI

/// The field guide: every Digimon in the roster, with the ones you have raised filled in.
///
/// A `LazyVGrid` inside a `ScrollView`, which is the whole reason the roster can grow to 865
/// entries: only the cells on screen are built, so only their sprites are ever decoded.
struct DexView: View {
    @StateObject private var model: DexModel
    @State private var selected: DexRow?

    /// Three 32pt columns fit a 41mm watch, the narrowest screen the app supports.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    /// As in `ContentView`: passed in rather than defaulted, because building one is a
    /// `@MainActor` call and a default argument would run in this non-isolated `init`.
    init(model: @autoclosure @escaping () -> DexModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(model.rows) { row in
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
        .navigationTitle("\(model.discoveredCount)/\(model.totalCount)")
        .sheet(item: $selected) { row in
            DexDetailView(row: row)
        }
        .onAppear {
            if !model.isLoaded { model.load() }
            #if DEBUG
            selectFirstDiscoveredIfRequested()
            #endif
        }
    }

    #if DEBUG
    /// Debug-only: sets exactly the state a tap sets, so the detail sheet can be screenshotted.
    /// `simctl` has no touch command and Simulator UI scripting needs an accessibility grant this
    /// machine does not have, so a real tap cannot be synthesised. Compiled out of release builds.
    private func selectFirstDiscoveredIfRequested() {
        guard CommandLine.arguments.contains("-dexDetailDemo") else { return }
        selected = model.rows.first { $0.isDiscovered }
    }
    #endif
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
