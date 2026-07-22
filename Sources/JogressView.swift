import SwiftUI

/// The pairs the player can fuse right now, one row each (US-132).
///
/// Pushed from `PartyView`'s entry point onto the same `NavigationStack` everything else on this
/// screen is pushed onto, so it keeps a back button — and so the tap that fuses lands the player
/// back on the main screen, which is where the ceremony plays.
struct JogressView: View {
    let offers: [JogressOffer]

    /// Performs this fusion. `MainScreenModel.performJogress(_:)` in the app, which runs the whole
    /// thing as one saved transaction.
    let fuse: (JogressOffer) -> Void

    var body: some View {
        List {
            ForEach(offers) { offer in
                Button {
                    fuse(offer)
                } label: {
                    JogressOfferRow(offer: offer)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(JogressWording.title)
    }
}

/// One offer: the two Digimon going in, the one coming out, and both named underneath.
///
/// The three sprites are the row's real content — a player choosing between fusions is choosing
/// between Digimon they recognise by sight — and the names are underneath rather than beside them
/// because three names on one 41mm line cannot be read at any size that fits.
private struct JogressOfferRow: View {
    let offer: JogressOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                sprite(stage: offer.first.spriteStage, file: offer.first.spriteFile)
                Text("+")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                sprite(stage: offer.second.spriteStage, file: offer.second.spriteFile)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                sprite(stage: offer.resultSpriteStage, file: offer.resultSpriteFile)
            }

            Text(offer.title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(offer.resultDisplayName)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(offer.accessibilityLabel)
    }

    /// `IdleSpriteView` for `PartyRowView`'s reason: this is a LIST, and one still frame per Digimon
    /// costs no `TimelineView` schedule for art being scrolled past. It carries the same
    /// `.interpolation(.none)` — smoothed pixel art is a bug on every screen.
    private func sprite(stage: String, file: String) -> some View {
        IdleSpriteView(stage: stage, name: file, scale: PartyRowLayout.spriteScale)
            .accessibilityHidden(true)
    }
}

/// The Jogress row at the top of `PartyView`: a way in when something can fuse, and a sentence
/// saying why not when nothing can (US-132 AC1/AC2).
///
/// **It is drawn either way and it is never a dead tap target.** A control that disappeared when it
/// had nothing to offer would leave the player with no way to learn that Jogress exists, or what it
/// wants of them; one that stayed tappable and led to an empty list would read as broken. So the
/// unavailable form is not a button at all — it is the reason, in one line.
struct JogressEntryRow: View {
    let board: JogressBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 12))
                    .foregroundStyle(board.isAvailable ? .orange : Color.secondary)
                Text(JogressWording.title)
                    .font(.caption)
                    .lineLimit(1)
                if board.isAvailable {
                    Spacer(minLength: 0)
                    Text(JogressWording.ready(board.offers.count))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }

            if let reason = board.reason {
                Text(reason)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    // Wrapped rather than shrunk: this is a sentence and the player is being asked
                    // to read it, unlike a name they are being asked to recognise.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        JogressView(offers: [
            JogressOffer(
                first: JogressOffer.Parent(rowId: 0, digimonId: "wargreymon",
                                           displayName: "WarGreymon", spriteFile: "WarGreymon",
                                           stage: .ultimate, originDigitamaId: "agu_digitama"),
                second: JogressOffer.Parent(rowId: 1, digimonId: "metalgarurumon",
                                            displayName: "MetalGarurumon",
                                            spriteFile: "MetalGarurumon", stage: .ultimate,
                                            originDigitamaId: "gabu_digitama"),
                resultId: "omegamon", resultDisplayName: "Omegamon",
                resultSpriteFile: "Omegamon", resultStage: .ultimate),
        ], fuse: { _ in })
    }
}
