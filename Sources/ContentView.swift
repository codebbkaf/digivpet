import SwiftUI

/// The main screen: your Digimon, idling, with what it is and what stage it has reached.
///
/// US-017 adds the four energy bars beneath the sprite, which is why the sprite does not simply
/// fill the screen.
struct ContentView: View {
    @StateObject private var model: MainScreenModel
    @Environment(\.scenePhase) private var scenePhase

    /// The model is always passed in rather than defaulted: building one is a `@MainActor` call,
    /// and a default argument would be evaluated in this `init`'s non-isolated context. Same
    /// reason as `HealthAuthorizationGate`.
    init(model: @autoclosure @escaping () -> MainScreenModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
            case .playing:
                digimon
            case .failed(let detail):
                SavedGameUnavailableView(detail: detail)
            }
        }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            // The whole refresh: health data is only read when the app is in front, since
            // watchOS gives a backgrounded app no reason to expect it will run at all.
            // `start()` covers the first appearance; this covers every return to it.
            guard phase == .active else { return }
            Task { await model.refresh() }
        }
    }

    @ViewBuilder
    private var digimon: some View {
        if let presentation = model.presentation {
            VStack(spacing: 2) {
                Text(presentation.displayName)
                    .font(.headline)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                DigimonSpriteView(
                    stage: presentation.spriteStage,
                    name: presentation.spriteFile,
                    animation: .idle,
                    scale: 5
                )

                Text(presentation.stage.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                if let progress = model.energyProgress {
                    EnergyBarsView(progress: progress, dominant: model.state?.dominantEnergyType)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // The graph has no node for the saved id — a roster edit that dropped a Digimon out
            // from under a live save. Nothing to draw, so say so rather than showing an empty box.
            SavedGameUnavailableView(detail: model.state.map { "Unknown Digimon '\($0.currentDigimonId)'." })
        }
    }
}

/// Shown when there is a saved game to open but it cannot be reached or drawn.
struct SavedGameUnavailableView: View {
    let detail: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("No Digimon")
                    .font(.headline)

                Text("Your saved game could not be opened.")
                    .font(.footnote)

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    ContentView(model: MainScreenModel())
}
