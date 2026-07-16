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
            ContentView()
        }
    }
}
