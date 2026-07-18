import SwiftUI
import WidgetKit

struct DigiVPetComplication: Widget {
    static let kind = "DigiVPetComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ComplicationProvider()) { entry in
            DigiVPetComplicationEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Digimon")
        .description("Your Digimon and its strongest energy.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

@main
struct DigiVPetComplicationBundle: WidgetBundle {
    var body: some Widget {
        DigiVPetComplication()
    }
}
