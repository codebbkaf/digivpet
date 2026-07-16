import SwiftUI

/// Placeholder main screen — US-016 replaces this with the real one. For now it exercises
/// `DigimonSpriteView` so the loops can be seen running in the Simulator.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 6) {
            DigimonSpriteView(stage: "Child", name: "Agumon", animation: .idle)

            HStack(spacing: 6) {
                DigimonSpriteView(stage: "Child", name: "Agumon", animation: .eat, scale: 2)
                DigimonSpriteView(stage: "Child", name: "Agumon", animation: .sleep, scale: 2)
                DigimonSpriteView(stage: "Child", name: "Agumon", animation: .still(.attack), scale: 2)
                DigimonSpriteView(stage: "Digitama", name: "Agu_Digitama", animation: .idle, scale: 2)
                DigimonSpriteView(stage: "Child", name: "NotADigimon", scale: 2)
            }
        }
    }
}

#Preview {
    ContentView()
}
