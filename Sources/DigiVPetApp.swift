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
            // state if the request fails. US-016 replaces what it wraps, not the gate itself.
            HealthAuthorizationGate(model: Self.makeAuthorizationModel()) {
                ContentView()
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
