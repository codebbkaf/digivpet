import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("DigiVPet")
                .font(.headline)
            Text("No Digimon yet")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
