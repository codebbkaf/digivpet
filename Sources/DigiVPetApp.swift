import SwiftUI
#if canImport(WatchKit)
import WatchKit
#endif

/// The one game the app is running, shared by the screen and the background delegate.
///
/// A singleton for one specific reason: `WKApplicationDelegate` is handed background tasks with no
/// reference to any view, so the delegate cannot be given the screen's model — and building its own
/// would open a SECOND `GameStore` on the same file, with its own in-memory `EnergyLedger`. Two
/// ledgers credit the same steps twice, which is the exact bug US-014's delta crediting exists to
/// prevent. One model, one store, one ledger.
@MainActor
enum GameSession {
    static let model = MainScreenModel()
    static let coordinator = BackgroundRefreshCoordinator(model: model)
}

@main
struct DigiVPetApp: App {
    #if canImport(WatchKit)
    @WKApplicationDelegateAdaptor(DigiVPetAppDelegate.self) private var delegate
    #endif

    init() {
        // Decode the evolution graph at launch rather than on first evolution, so a broken
        // graph surfaces immediately instead of mid-game. `bundled` is a `static let`, so this
        // is the one and only decode; every later reference reuses it.
        _ = EvolutionGraph.bundled
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // US-055's spike. Replaces the whole UI rather than sitting beside it, so the
            // authorization gate cannot prompt underneath the probe and confuse its readings.
            if let mode = HealthMetricProbe.mode() {
                Text("Probing…")
                    .task { await HealthMetricProbe.run(mode: mode) }
            } else {
                appBody
            }
            #else
            appBody
            #endif
        }
    }

    @ViewBuilder
    private var appBody: some View {
        // The gate explains health access before the system prompt and shows the blocked
        // state if the request fails. The main screen only ever runs behind it, so it never
        // has to read health data that was never asked for.
        HealthAuthorizationGate(model: Self.makeAuthorizationModel()) {
            ContentView(model: GameSession.model)
                // BEHIND THE GATE, so the observers are registered only once the user has
                // answered the health prompt — registering one before that fails outright with
                // "Authorization not determined", and a failed observer is never retried.
                // Here rather than inside `ContentView` so the view stays free of the singleton
                // and can still be built with a model of its own in a test.
                .task { GameSession.coordinator.beginObservingHealthUpdates() }
        }
    }

    @MainActor
    private static func makeAuthorizationModel() -> HealthAuthorizationModel {
        #if DEBUG
        if let stub = StubHealthAuthorizer.fromLaunchArguments() {
            return HealthAuthorizationModel(authorizer: stub)
        }
        #endif
        return HealthAuthorizationModel()
    }
}

#if canImport(WatchKit)
/// Runs the game while nobody is looking: the scheduled background refresh, and the HealthKit
/// observers that ask for an early one.
///
/// Thin on purpose — every decision lives in `BackgroundRefreshCoordinator`, which is testable,
/// while this only does the two things no test can: adapt `WKRefreshBackgroundTask` and tell watchOS
/// the task is finished.
final class DigiVPetAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in GameSession.coordinator.begin() }
    }

    /// EVERY task handed over must be completed, including the kinds this app never asks for.
    /// watchOS suspends an app that leaves one outstanding and stops granting it wakes, so the
    /// `default` branch is not tidiness — it is what keeps the schedule alive.
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refreshTask as WKApplicationRefreshBackgroundTask:
                Task { @MainActor in
                    await GameSession.coordinator.performRefresh()
                    // No snapshot: the refresh may have hatched, evolved or sickened the Digimon,
                    // but the complication is what shows that (US-034) — the app's own snapshot is
                    // only the screen the user last saw.
                    refreshTask.setTaskCompletedWithSnapshot(false)
                }
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
#endif
