import SwiftUI

/// The fifth training minigame (US-080): wait for the signal, then tap the instant it appears.
///
/// The other four all measure something you do over a stretch of time — a sweep, a burst of taps, a
/// hold, a spin. This one measures a single moment, and the whole game is the wait before it. The
/// delay is randomised so it cannot be anticipated, which is also why tapping early has to cost
/// something: without a false start rule, mashing from the first frame would win every round.
///
/// As with the other four the rules are pure. `delay(using:range:)` draws the wait from the
/// project's own `SeededGenerator`, so a test pins the delay instead of hoping for one, and
/// `grade(latency:)` reads a reaction time — including a negative one, which is exactly what a false
/// start is: a tap that landed before the signal it was supposedly reacting to.
///
/// It reports EXACTLY ONE grade, as `TrainingMinigame` requires: the one its reaction earned, a
/// `.miss` for a false start, or a `.miss` if `reactionTimeout` elapses with the signal never
/// answered. A round the user has already paid for must always end.
struct ReflexStrikeGame: TrainingMinigame {
    static let title = "Reflex Strike"

    /// How long the round makes you wait for the signal, in seconds. The round draws ONE value from
    /// this every time it is played.
    ///
    /// A range rather than a constant because a fixed wait stops being a reflex test the second
    /// time you play it — you learn the beat and tap to it. The bottom is far enough in that the
    /// screen has settled; the top is short enough that waiting is tense rather than boring.
    var delayRange: ClosedRange<TimeInterval> = 1...3

    /// Where the wait comes from. Injected in the manner of `MainScreenModel.makeBattleGenerator`,
    /// so a test hands the round a pinned seed and knows to the millisecond when the signal is due,
    /// while the app gets a wait it cannot learn.
    ///
    /// A factory rather than a generator, because `SeededGenerator` is a value type that must be
    /// mutated to draw from: the round makes its own and keeps the draw sequence to itself.
    var makeGenerator: () -> SeededGenerator = {
        SeededGenerator(seed: UInt64.random(in: UInt64.min...UInt64.max))
    }

    /// How long the signal waits to be answered before the round ends itself as a `.miss`.
    ///
    /// Anything slower than `goodLatency` is a miss already, so this buys no grade — it exists so a
    /// round nobody answers ends on a screen that says Miss, rather than sitting lit forever. See
    /// `TrainingMinigame.init(onFinish:)`.
    var reactionTimeout: TimeInterval = 2

    /// How long the grade holds on screen before the round hands it back. Matches the other four
    /// games' for the same reason: long enough to read, short enough that training does not become a
    /// sequence of dismissals.
    var resultDuration: TimeInterval = 1.0

    #if DEBUG
    /// Debug-only: a reaction time to end the round on at once, instead of one measured from a tap.
    /// nil in the app — every reaction is a real one. Set by `ContentView`'s strike demos so a
    /// `simctl` screenshot lands on a decided round, since `simctl` cannot tap one out.
    ///
    /// It stages WHEN the tap landed, not what it was worth: the staged latency is read by the same
    /// pure `grade(latency:)` a real tap is, negative values included — which is how the false
    /// start gets its own screenshot.
    var demoLatency: TimeInterval? = nil
    #endif

    private let onFinish: (TrainingResult) -> Void

    init(onFinish: @escaping (TrainingResult) -> Void) {
        self.onFinish = onFinish
    }

    /// When the signal is DUE, fixed the moment the round starts. Known in advance so an early tap
    /// has a real number to be early against — see `tap()`.
    @State private var signalDueDate: Date?

    /// When the signal actually appeared. nil while the round is still waiting, which is also what
    /// makes a tap a false start.
    @State private var signalDate: Date?

    /// The reaction the round ended on, in seconds; negative for a false start. nil until a tap or
    /// the timeout decides it.
    @State private var latency: TimeInterval?

    /// What the round earned. nil until it is over; set exactly once.
    @State private var grade: TrainingResult?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 8) {
                Text(grade?.displayName ?? Self.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(grade?.tint ?? Color.primary)

                signal

                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The whole screen is the target. The game measures WHEN you tapped, not where, and asking
        // for accuracy as well would make a slow finger look like a bad reflex.
        .contentShape(Rectangle())
        .onTapGesture { tap() }
        .task { await runRound() }
        .task(id: grade) { await handOffGrade() }
    }

    /// The signal itself: dark until it is time, lit the instant it is, and wearing the round's own
    /// colour once the round is decided.
    ///
    /// One big shape rather than a bar or a gauge — the other four games draw something that moves,
    /// but there is nothing here to watch. The only event is the change, so the change has to be the
    /// largest thing on the screen.
    private var signal: some View {
        ZStack {
            Circle()
                .fill(signalTint)

            Image(systemName: "bolt.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.black)
                .opacity(signalDate == nil ? 0.35 : 1)

            if let reactionLabel {
                Text(reactionLabel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.black)
                    .offset(y: Self.reactionLabelOffset)
            }
        }
        .frame(width: Self.signalDiameter, height: Self.signalDiameter)
        .animation(.easeOut(duration: 0.1), value: signalDate)
    }

    /// Dim while waiting, green the moment it is time to strike, then the grade's own colour. Green
    /// rather than the game's red because it is a GO, and a red circle appearing reads as a thing to
    /// avoid.
    private var signalTint: Color {
        if let grade { return grade.tint }
        return signalDate == nil ? Color.secondary.opacity(0.3) : .green
    }

    /// The reaction time, once there is one. A false start says so in words instead of showing a
    /// negative number, which is arithmetic rather than feedback.
    private var reactionLabel: String? {
        guard let latency else { return nil }
        return latency > 0 ? String(format: "%.2fs", latency) : "Too soon"
    }

    private var footer: String {
        if let grade { return "+\(grade.strengthGain) STR" }
        return signalDate == nil ? "Wait for it…" : "Strike!"
    }

    /// The tap. One path for a real reaction and for a false start, because a false start IS a
    /// reaction time — a negative one, measured against the moment the signal was due.
    ///
    /// Ignored once the round is decided, so tapping on the result cannot change it.
    private func tap() {
        guard grade == nil, let signalDueDate else { return }
        let now = Date()
        let latency: TimeInterval
        if let signalDate {
            // Measured from the actual reveal, not from when it was due: a timer that overslept by
            // a millisecond must not be charged to the user's thumb.
            latency = now.timeIntervalSince(signalDate)
        } else {
            // Nothing is lit yet, so this cannot be a reaction to it however late the reveal timer
            // is running — clamped strictly below zero, which is what `grade(latency:)` reads as a
            // false start.
            latency = min(now.timeIntervalSince(signalDueDate), 0).nextDown
        }
        self.latency = latency
        settle(Self.grade(latency: latency))
    }

    private func settle(_ grade: TrainingResult) {
        withAnimation(.easeOut(duration: 0.15)) {
            self.grade = grade
        }
    }

    /// The round: draw a wait, show the signal, then give it `reactionTimeout` to be answered.
    private func runRound() async {
        var generator = makeGenerator()
        let delay = Self.delay(using: &generator, range: delayRange)
        let due = Date().addingTimeInterval(delay)
        signalDueDate = due

        #if DEBUG
        if let demoLatency {
            // A staged reaction still goes through the real `grade(latency:)`; only the tap is
            // fake. A negative one leaves the signal unlit, which is what a false start looks like.
            if demoLatency > 0 { signalDate = Date() }
            latency = demoLatency
            return settle(Self.grade(latency: demoLatency))
        }
        #endif

        try? await Task.sleep(for: .seconds(delay))
        // A false start has already decided the round — the signal must not appear after it.
        guard !Task.isCancelled, grade == nil else { return }
        withAnimation(.easeOut(duration: 0.1)) { signalDate = Date() }

        try? await Task.sleep(for: .seconds(reactionTimeout))
        guard !Task.isCancelled, grade == nil else { return }
        // Never answered, so never paid — see `reactionTimeout`.
        settle(.miss)
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

    /// How long to wait before the signal, drawn from `generator`.
    ///
    /// Pulled out of the view so the wait is testable without hosting one: with a pinned seed this
    /// returns the same number on every machine, which is what lets a test know when the signal was
    /// due. See `SeededGenerator`.
    ///
    /// A negative bound would be a wait that has already elapsed, so the range is lifted to zero
    /// before it is drawn from rather than trapping on it.
    static func delay(using generator: inout SeededGenerator,
                      range: ClosedRange<TimeInterval>) -> TimeInterval {
        let lower = max(0, range.lowerBound)
        let upper = max(lower, range.upperBound)
        guard lower < upper else { return lower }
        return TimeInterval.random(in: lower...upper, using: &generator)
    }

    /// The reaction each grade asks for, in seconds. A tap at or under the number earns it.
    ///
    /// A quarter second is about as fast as a primed thumb gets, so a `perfect` is meant to be rare;
    /// half a second is a good honest reaction, and a whole second is "you were awake". Anything
    /// slower buys nothing — see `grade(latency:)`.
    ///
    /// All three are exact in binary, so a boundary test asserts ON the number with no epsilon, the
    /// same way round as the masher's counts and the sprint's floors.
    static let perfectLatency: TimeInterval = 0.25
    static let greatLatency: TimeInterval = 0.5
    static let goodLatency: TimeInterval = 1.0

    /// What a reaction of `latency` seconds earns.
    ///
    /// Thresholds are INCLUSIVE of the better grade — landing exactly on the number is landing in,
    /// the same way round as every other game here.
    ///
    /// A non-positive latency is a `miss` whatever its size: that is a tap that landed at or before
    /// the signal, which is a false start rather than an impossibly fast reflex. Guessing must never
    /// out-earn reacting, or the game becomes "mash from the first frame".
    static func grade(latency: TimeInterval) -> TrainingResult {
        guard latency > 0 else { return .miss }
        if latency <= perfectLatency { return .perfect }
        if latency <= greatLatency { return .great }
        if latency <= goodLatency { return .good }
        return .miss
    }

    // No draining timer bar here, deliberately: `TrainingMinigame.remainingFraction(at:window:)`
    // draws down a window the user is spending, and this round's window is one they are waiting
    // through. Showing it would count the delay down and hand away the one thing the round is
    // built on — see `delayRange`.

    // MARK: - Drawing constants

    static let signalDiameter: CGFloat = 84
    static let reactionLabelOffset: CGFloat = 26
}

#Preview {
    ReflexStrikeGame(onFinish: { _ in })
}
