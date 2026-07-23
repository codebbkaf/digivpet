import SwiftUI

/// The Sleep Time screen, behind the action grid's Sleep button (US-213).
///
/// The Zz reading used to be a `DashBar` pinned under the sprite, where it was one anonymous row of
/// dashes competing with the Digimon for a 41mm screen. US-213 moved it onto the grid as a ring, and
/// a ring alone cannot say "6 of 16" — so the numbers land here, on the screen the ringed button
/// opens, which is the same bargain every other ring in the grid struck.
///
/// What it shows today is the total: the whole hours the ACTIVE Digimon has banked (`sleepHours`,
/// off `GameState.accumulatedSleepHours`, so switching who is out shows that Digimon's own rest) and
/// the nominal full-night ceiling it is read against. US-214 adds the per-Digimon bedtime, wake time
/// and nap window beneath it; this view is deliberately built to take that as more rows rather than
/// as a rewrite.
struct SleepTimeView: View {
    /// Whole hours slept, and the ceiling that counts as fully rested — `MainScreenModel.sleepHours`
    /// and `.sleepHoursCap`, the same pair the Sleep button's ring is drawn from, so the screen and
    /// the button it opened from cannot disagree.
    let sleptHours: Int
    let goalHours: Int

    /// What the ring shows, spelled out: the hours bounded by the ceiling they are read against, so
    /// a Digimon that has banked more than a full night reads as rested rather than as "19 of 16".
    /// The raw total is not lost — `hoursSlept` is the unclamped number, and it is what the caption
    /// speaks once it passes the goal.
    var clampedHours: Int { min(max(sleptHours, 0), max(goalHours, 0)) }

    /// Whether this Digimon has reached a full night's rest. The caption's condition, kept out of
    /// `body` so a test can ask it.
    var isFullyRested: Bool { goalHours > 0 && sleptHours >= goalHours }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                // The number, said plainly and once. The unit is on the value rather than in a
                // separate label because "6 h" is two glyphs narrower than a labelled row, and this
                // screen has to read at a glance on the 42mm.
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(clampedHours)")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.indigo)
                    Text("h")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("of \(goalHours) h")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                // The same `DashBar` the Zz row drew, at the same weight — the reading is not
                // re-invented here, it is re-housed. Indigo rather than the old `.secondary` so the
                // bar, the number above it and the ring on the button that opened this screen are
                // all one colour.
                DashBar(filled: sleptHours, total: goalHours, tint: .indigo,
                        dashHeight: 6, spacing: 1)

                Text(isFullyRested ? "Fully rested." : "Slept so far.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
            // Leading-aligned inside the full width, so the number does not float in the middle of
            // a screen whose later rows (US-214's schedule) are a left-aligned list.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Sleep")
    }
}

#Preview {
    NavigationStack {
        SleepTimeView(sleptHours: 6, goalHours: 16)
    }
}
