import SwiftUI

/// The second training minigame (US-077): tap as fast as you can before the window runs out.
///
/// Where the timing bar asks for one tap at the right moment, this asks for as many as you can land
/// in a few seconds — the same four grades, bought with a different skill. As with `TimingBarGame`,
/// the whole rule is pure: `requiredTaps(for:window:)` says what each grade costs and
/// `grade(taps:window:)` reads a count against it, so "grade-from-count is unit-tested at each
/// threshold" is assertable without hosting a view or tapping anything.
///
/// It reports EXACTLY ONE grade, as `TrainingMinigame` requires: the one its count earned, or
/// `.miss` if `idleTimeout` elapses with the round never started. A round the user has already paid
/// for must always end.
struct ButtonMasherGame: TrainingMinigame {
    static let title = "Button Masher"

    /// Seconds the round lasts, timed from the FIRST tap. Injected, in the manner of
    /// `TimingBarGame.sweepDuration`, so a test drives a whole round by arithmetic and never waits
    /// one — and so US-082 can hand a Digimon a shorter, meaner window.
    ///
    /// It starts on the first tap rather than on appear so none of it is spent realising the round
    /// has begun; the tap that starts the clock is itself tap number one.
    var window: TimeInterval = 5

    /// How long the grade holds on screen before the round hands it back. Matches the timing bar's,
    /// for the same reason: long enough to read, short enough that training does not become a
    /// sequence of dismissals.
    var resultDuration: TimeInterval = 1.0

    /// How long the round waits for the FIRST tap before ending itself as a `.miss`. Once tapped it
    /// is `window` that ends the round; this only covers the round nobody plays — see
    /// `TrainingMinigame.init(onFinish:)`.
    var idleTimeout: TimeInterval = 12

    #if DEBUG
    /// Debug-only: a count to start the round already holding, instead of an untapped zero. nil in
    /// the app — every tap is a real tap. Set by `ContentView`'s masher demos so a `simctl`
    /// screenshot lands on a round with something on the counter, since `simctl` cannot tap one up.
    ///
    /// It stages HOW MANY taps the round ends on, not what they are worth: the count still runs the
    /// real `window` and is still read by the same pure `grade(taps:window:)`.
    var demoTapCount: Int? = nil
    #endif

    private let onFinish: (TrainingResult) -> Void

    init(onFinish: @escaping (TrainingResult) -> Void) {
        self.onFinish = onFinish
    }

    /// Taps landed so far. Shown live — the count IS the feedback, since there is nothing else on
    /// screen to tell you whether you are fast enough.
    @State private var taps = 0

    /// When the first tap landed, and so when the window began. nil until the round is under way.
    @State private var startDate: Date?

    /// What the round earned. nil until it is over; set exactly once.
    @State private var grade: TrainingResult?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 6) {
                Text(grade?.displayName ?? Self.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(grade?.tint ?? Color.primary)

                Text("\(taps)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(grade?.tint ?? Color.primary)

                timerBar

                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The whole screen is the button. Mashing is meant to test how fast you can tap, not how
        // accurately, so there is nothing smaller than the watch face to hit.
        .contentShape(Rectangle())
        .onTapGesture { tap() }
        .task(id: startDate) { await runRound() }
        .task(id: grade) { await handOffGrade() }
    }

    private var footer: String {
        if let grade { return "+\(grade.strengthGain) STR" }
        return startDate == nil ? "Tap to start" : "Keep tapping!"
    }

    /// What is left of the window, draining left to right. It is the only thing on screen that says
    /// how long you have, so it is paused — not hidden — before the first tap and after the last.
    private var timerBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))

                TimelineView(.animation(paused: startDate == nil || grade != nil)) { context in
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: remainingFraction(now: context.date) * geometry.size.width)
                }
            }
        }
        .frame(height: Self.barHeight)
    }

    /// How much of the window is left to draw: full before the round starts, and frozen at whatever
    /// it was when the round ended.
    private func remainingFraction(now: Date) -> CGFloat {
        guard let startDate, grade == nil else { return startDate == nil ? 1 : 0 }
        return Self.remainingFraction(at: now.timeIntervalSince(startDate), window: window)
    }

    /// The tap. Ignored once the round is decided, so mashing on the result cannot inflate it.
    private func tap() {
        guard grade == nil else { return }
        if startDate == nil { startDate = Date() }
        withAnimation(.easeOut(duration: 0.1)) { taps += 1 }
    }

    private func settle(_ grade: TrainingResult) {
        withAnimation(.easeOut(duration: 0.15)) {
            self.grade = grade
        }
    }

    /// The round's own clock. Before the first tap it is the idle timeout that is running; the tap
    /// that sets `startDate` cancels this and restarts it as the window itself.
    private func runRound() async {
        guard let startDate else {
            #if DEBUG
            if let demoTapCount {
                // Setting startDate re-fires this task, which then runs the real window over the
                // staged count.
                taps = demoTapCount
                self.startDate = Date()
                return
            }
            #endif
            try? await Task.sleep(for: .seconds(idleTimeout))
            guard !Task.isCancelled, self.startDate == nil else { return }
            // Never played, so never paid — a round left alone is a miss, not a free zero.
            return settle(.miss)
        }

        let remaining = window - Date().timeIntervalSince(startDate)
        try? await Task.sleep(for: .seconds(max(0, remaining)))
        guard !Task.isCancelled else { return }
        settle(Self.grade(taps: taps, window: window))
    }

    /// Holds the graded result on screen, then hands it back — once, which is the whole contract a
    /// minigame has with `TrainAction`.
    private func handOffGrade() async {
        guard let grade else { return }
        try? await Task.sleep(for: .seconds(resultDuration))
        guard !Task.isCancelled else { return }
        onFinish(grade)
    }

    // MARK: - The rules, as pure functions

    /// The pace each grade asks for, in taps per second.
    ///
    /// A RATE rather than a flat count, because `window` is injectable: with fixed counts, halving
    /// the window would silently make every round a miss, and a test running a round in
    /// milliseconds could not grade anything at all. As a rate, the game means the same thing at
    /// any window — three taps a second is a good round whether it lasts two seconds or ten.
    ///
    /// A `miss` asks for nothing: it is what a round that fell short of `good` is worth, including
    /// one that was never tapped.
    static func tapsPerSecond(for grade: TrainingResult) -> Double {
        switch grade {
        case .miss: return 0
        case .good: return 3
        case .great: return 4.5
        case .perfect: return 6
        }
    }

    /// How many taps a `window`-second round must land to earn `grade`.
    ///
    /// Rounded UP, so a fractional requirement is never met by falling short of it, and floored at
    /// one tap for every grade above `miss`: a window so short that the arithmetic asks for zero
    /// taps must not hand out a perfect to someone who never touched the screen.
    static func requiredTaps(for grade: TrainingResult, window: TimeInterval) -> Int {
        guard grade != .miss else { return 0 }
        return max(1, Int((tapsPerSecond(for: grade) * max(0, window)).rounded(.up)))
    }

    /// What landing `taps` taps in a `window`-second round earns.
    ///
    /// Thresholds are INCLUSIVE of the better grade — landing exactly on the number is landing in,
    /// the same way round as the timing bar's band edges. Counts are integers, so every threshold
    /// here is exact and a boundary test asserts ON the number rather than either side of it.
    static func grade(taps: Int, window: TimeInterval) -> TrainingResult {
        if taps >= requiredTaps(for: .perfect, window: window) { return .perfect }
        if taps >= requiredTaps(for: .great, window: window) { return .great }
        if taps >= requiredTaps(for: .good, window: window) { return .good }
        return .miss
    }

    // `remainingFraction(at:window:)` — how much of the window is left — moved to `TrainingMinigame`
    // in US-079, when the crown sprint needed the same draining bar over the same kind of window.
    // Still reachable as `ButtonMasherGame.remainingFraction(at:window:)`.

    // MARK: - Drawing constants

    static let barHeight: CGFloat = 6
}

#Preview {
    ButtonMasherGame(onFinish: { _ in })
}
