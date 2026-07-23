import SwiftUI

/// The Sleep Time screen, behind the action grid's Sleep button (US-213).
///
/// The Zz reading used to be a `DashBar` pinned under the sprite, where it was one anonymous row of
/// dashes competing with the Digimon for a 41mm screen. US-213 moved it onto the grid as a ring, and
/// a ring alone cannot say "6 of 16" — so the numbers land here, on the screen the ringed button
/// opens, which is the same bargain every other ring in the grid struck.
///
/// It shows two things. The TOTAL: the whole hours the ACTIVE Digimon has banked (`sleepHours`, off
/// `GameState.accumulatedSleepHours`, so switching who is out shows that Digimon's own rest) and the
/// nominal full-night ceiling it is read against. And, beneath it, that Digimon's own SCHEDULE
/// (US-214) — bedtime, wake time and one afternoon nap, derived from its id by `SleepRoutine` so
/// every creature rests on its own hours without a bedtime having been authored for 1,000+ entries.
///
/// The schedule is flavour and says so: `SleepRoutine`'s note explains why it must not be confused
/// with `SleepSchedule`, which is the window that actually decides whether the Digimon is asleep.
struct SleepTimeView: View {
    /// Whole hours slept, and the ceiling that counts as fully rested — `MainScreenModel.sleepHours`
    /// and `.sleepHoursCap`, the same pair the Sleep button's ring is drawn from, so the screen and
    /// the button it opened from cannot disagree.
    let sleptHours: Int
    let goalHours: Int

    /// Whose schedule this is: the active Digimon's id, the ONLY input to the times below. Empty for
    /// a save that has not opened a Digimon yet, which still answers — `SleepRoutine` is total — so
    /// the screen never has a blank half.
    var digimonId: String = ""

    /// The times, derived once per body pass. Pure in `digimonId`, so this is not state and never
    /// needs invalidating.
    var routine: SleepRoutine { SleepRoutine.forDigimon(id: digimonId) }

    /// What the ring shows, spelled out: the hours bounded by the ceiling they are read against, so
    /// a Digimon that has banked more than a full night reads as rested rather than as "19 of 16".
    /// The raw total is not lost — `hoursSlept` is the unclamped number, and it is what the caption
    /// speaks once it passes the goal.
    var clampedHours: Int { min(max(sleptHours, 0), max(goalHours, 0)) }

    /// Whether this Digimon has reached a full night's rest. The caption's condition, kept out of
    /// `body` so a test can ask it.
    var isFullyRested: Bool { goalHours > 0 && sleptHours >= goalHours }

    var body: some View {
        ScrollViewReader { proxy in
            scrollingBody(proxy: proxy)
        }
        .navigationTitle("Sleep")
    }

    private func scrollingBody(proxy: ScrollViewProxy) -> some View {
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

                // US-214's half: this Digimon's own hours. A divider rather than a second card,
                // because the 42mm screen has no room for two boxes and the two halves are about
                // the same thing — one is rest banked, the other is when it is taken.
                Divider()
                    .padding(.vertical, 4)

                Text("SCHEDULE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                scheduleRow(symbol: "moon.fill", label: "Bed", value: routine.bedtime.formatted)
                scheduleRow(symbol: "sun.max.fill", label: "Wake", value: routine.wakeTime.formatted)
                scheduleRow(symbol: "zzz", label: "Nap", value: routine.napWindowText)

                // The day's rest, and the split that says where the nap went (AC4). Two lines rather
                // than one long one: at 42mm "9 h 15 m a day" and "8 h 15 m night + 1 h nap" do not
                // fit side by side, and the total is the one a glance wants first.
                Text("\(SleepRoutine.durationText(minutes: routine.totalMinutes)) a day")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .padding(.top, 4)
                Text(routine.splitText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .id(SleepTimeView.lastRowId)
            }
            .padding(.horizontal, 2)
            // Leading-aligned inside the full width, so the number does not float in the middle of
            // a screen whose remaining rows are a left-aligned list.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if DEBUG
        // Screenshot hook, the same one `SettingsView` and `PartyView` carry and for the same
        // reason: `simctl` can neither tap nor scroll, and on the 42mm the schedule's last two lines
        // sit past the fold — without this, "the layout scrolls" cannot be photographed at all. It
        // moves the scroll position and nothing else.
        .task {
            guard CommandLine.arguments.contains("-sleepBottomDemo") else { return }
            // After a beat, not immediately: `.task` runs before the rows have been measured, and
            // scrolling to an item whose height is not settled lands short of it.
            try? await Task.sleep(nanoseconds: 500_000_000)
            proxy.scrollTo(SleepTimeView.lastRowId, anchor: .bottom)
        }
        #endif
    }

    /// The id of the bottom-most line, the target the `-sleepBottomDemo` scroll hook aims at.
    private static let lastRowId = "sleep-schedule-split"

    /// One line of the schedule: glyph, what it is, and when. The time is trailing and monospaced-
    /// digit so `07:00` and `22:30` line up down the column instead of shuffling by a pixel.
    private func scheduleRow(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.indigo)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 12))
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        // One element per row, so VoiceOver says "Bed, 22:30" instead of walking a glyph, a word and
        // a number separately.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        SleepTimeView(sleptHours: 6, goalHours: 16, digimonId: "agumon")
    }
}
