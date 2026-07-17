import SwiftUI

@main
struct DigiVPetApp: App {
    init() {
        // Decode the evolution graph at launch rather than on first evolution, so a broken
        // graph surfaces immediately instead of mid-game. `bundled` is a `static let`, so this
        // is the one and only decode; every later reference reuses it.
        _ = EvolutionGraph.bundled
    }

    var body: some Scene {
        WindowGroup {
            // The gate explains health access before the system prompt and shows the blocked
            // state if the request fails. The main screen only ever runs behind it, so it never
            // has to read health data that was never asked for.
            HealthAuthorizationGate(model: Self.makeAuthorizationModel()) {
                ContentView(model: MainScreenModel())
            }
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
