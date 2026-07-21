import SwiftUI

/// The fourth training minigame (US-079): spin the Digital Crown to fill the gauge before time runs
/// out.
///
/// The first of the six played with something other than a finger. Where the masher asks how fast
/// you can tap, this asks how fast you can spin — the same four grades, bought on the one input the
/// watch has that a phone does not. Rotation ACCUMULATES: every unit the crown turns counts, in
/// either direction, so the game is a sprint against `window` rather than a target to land on.
///
/// As with the other three, the rules are pure. `crownDelta(from:to:range:)` says how far one
/// movement of the crown travelled, `progress(rotation:target:)` says how full that leaves the
/// gauge, and `grade(rotation:target:)` says what the round earned, so "grade-from-rotation is pure
/// and unit-tested" is assertable without hosting a view or turning anything.
///
/// It reports EXACTLY ONE grade, as `TrainingMinigame` requires: the one its rotation earned when
/// the window closed, a `perfect` the moment the target is reached, or `.miss` if `idleTimeout`
/// elapses with the crown never touched. A round the user has already paid for must always end.
struct CrownSprintGame: TrainingMinigame {
    static let title = "Crown Sprint"

    /// How far the crown must travel, in the binding's own units, for a `perfect`. Injected, in the
    /// manner of `ButtonMasherGame.window`, so a test grades a whole sprint by arithmetic and never
    /// turns one — and so US-082 can hand a Digimon a longer spin.
    var rotationTarget: Double = defaultRotationTarget

    /// Seconds the round lasts, timed from the FIRST movement of the crown. Starts there rather than
    /// on appear for the masher's reason: none of the window should be spent realising it has begun,
    /// and the turn that starts the clock already counts toward the target.
    var window: TimeInterval = 5

    /// How long the grade holds on screen before the round hands it back. Matches the other three
    /// games' for the same reason: long enough to read, short enough that training does not become a
    /// sequence of dismissals.
    var resultDuration: TimeInterval = 1.0

    /// How long the round waits for the FIRST movement before ending itself as a `.miss`. Once
    /// turned it is `window` that ends the round; this only covers the round nobody plays — see
    /// `TrainingMinigame.init(onFinish:)`.
    var idleTimeout: TimeInterval = 12

    #if DEBUG
    /// Debug-only: a rotation to start the round already holding, instead of an untouched zero. nil
    /// in the app — every unit is a real turn of the crown. Set by `ContentView`'s sprint demos so a
    /// `simctl` screenshot lands on a gauge with something in it, since `simctl` has no way to turn
    /// a crown at all.
    ///
    /// It stages HOW FAR the crown got, not what that is worth: the staged rotation is read by the
    /// same pure `grade(rotation:target:)` the real one is.
    var demoRotation: Double? = nil

    /// Debug-only: whether the staged rotation is graded at once, so a screenshot lands on a decided
    /// round rather than a gauge still filling.
    var demoGradesImmediately = false

    /// Debug-only: how far to advance the crown binding every `demoSpinInterval`, so the gauge is
    /// caught filling across two screenshots. nil in the app.
    ///
    /// It moves the BINDING, not the rotation — the accumulation, the wrap handling and the tint all
    /// happen in `spun(from:to:)`, which is the same code the real crown drives. What it cannot fake
    /// is the crown itself.
    var demoSpinStep: Double? = nil
    var demoSpinInterval: TimeInterval = 0.15
    #endif

    private let onFinish: (TrainingResult) -> Void

    init(onFinish: @escaping (TrainingResult) -> Void) {
        self.onFinish = onFinish
    }

    /// The crown binding's raw value. Meaningless on its own — it wanders around its range and wraps
    /// — which is why the game keeps `rotation` separately.
    @State private var crown: Double = 0

    /// How far the crown has travelled this round, in binding units. This is what gets graded.
    @State private var rotation: Double = 0

    /// When the first movement landed, and so when the window began. nil until the round is running.
    @State private var startDate: Date?

    /// What the round earned. nil until it is over; set exactly once.
    @State private var grade: TrainingResult?

    /// The crown only sends rotation to a focused view, so the round takes focus on appear and the
    /// first turn is already counted rather than spent waking the view up.
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 6) {
                Text(grade?.displayName ?? Self.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(grade?.tint ?? Color.primary)

                gauge

                timerBar

                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($focused)
        .digitalCrownRotation($crown,
                              from: 0,
                              through: Self.crownRange,
                              by: Self.crownStride,
                              sensitivity: .high,
                              isContinuous: true,
                              isHapticFeedbackEnabled: true)
        .onChange(of: crown) { old, new in spun(from: old, to: new) }
        .onAppear { focused = true }
        .task(id: startDate) { await runRound() }
        .task(id: grade) { await handOffGrade() }
        #if DEBUG
        .task { await demoSpin() }
        #endif
    }

    private var footer: String {
        if let grade { return "+\(grade.strengthGain) STR" }
        return startDate == nil ? "Turn the crown" : "Spin!"
    }

    /// The gauge, filling with the rotation. Tinted by the grade the round would earn if it ended
    /// now — the gauge IS the feedback, and there is nothing else on screen to say whether spinning
    /// harder is still buying anything.
    ///
    /// Unlike the power meter's charge, there is no zone to overshoot into, so the live tint and the
    /// finished round's tint can be the one `TrainingResult.tint`.
    private var gauge: some View {
        Gauge(value: Self.progress(rotation: rotation, target: rotationTarget), in: 0...1) {
            EmptyView()
        } currentValueLabel: {
            Text(Self.percentLabel(rotation: rotation, target: rotationTarget))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .gaugeStyle(.circular)
        .tint(Self.grade(rotation: rotation, target: rotationTarget).tint)
        .frame(height: Self.gaugeHeight)
    }

    /// What is left of the window, draining left to right — the same bar the masher runs, over the
    /// same kind of window. Paused, not hidden, before the first turn and after the last.
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

    /// How much of the window is left to draw: full before the round starts, and frozen at empty
    /// once it has ended.
    private func remainingFraction(now: Date) -> CGFloat {
        guard let startDate, grade == nil else { return startDate == nil ? 1 : 0 }
        return Self.remainingFraction(at: now.timeIntervalSince(startDate), window: window)
    }

    /// One movement of the crown. Ignored once the round is decided, so spinning on the result
    /// cannot inflate it.
    private func spun(from old: Double, to new: Double) {
        guard grade == nil else { return }
        let delta = Self.crownDelta(from: old, to: new, range: Self.crownRange)
        guard delta > 0 else { return }
        if startDate == nil { startDate = Date() }
        withAnimation(.easeOut(duration: 0.1)) { rotation += delta }
        // Reaching the target ends the sprint there and then. Spinning on past it cannot buy a
        // fifth grade, and making the user keep going after they have won reads as a bug.
        if rotation >= rotationTarget { settle(.perfect) }
    }

    private func settle(_ grade: TrainingResult) {
        withAnimation(.easeOut(duration: 0.15)) {
            self.grade = grade
        }
    }

    /// The round's own clock. Before the first movement it is the idle timeout that is running; the
    /// turn that sets `startDate` cancels this and restarts it as the window itself.
    private func runRound() async {
        guard let startDate else {
            #if DEBUG
            if let demoRotation {
                // Setting startDate re-fires this task, which then runs the real window over the
                // staged rotation.
                rotation = demoRotation
                self.startDate = Date()
                if demoGradesImmediately {
                    settle(Self.grade(rotation: rotation, target: rotationTarget))
                }
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
        // `grade` may already be set by a sprint that reached the target early; the window closing
        // must not grade the same round a second time.
        guard !Task.isCancelled, grade == nil else { return }
        settle(Self.grade(rotation: rotation, target: rotationTarget))
    }

    /// Holds the graded result on screen, then hands it back — once, which is the whole contract a
    /// minigame has with `TrainAction`.
    private func handOffGrade() async {
        guard let grade else { return }
        try? await Task.sleep(for: .seconds(resultDuration))
        guard !Task.isCancelled else { return }
        onFinish(grade)
    }

    #if DEBUG
    /// Debug-only: turns the crown binding on a timer so a screenshot can catch the gauge filling.
    /// Every step goes through `onChange` and `spun(from:to:)`, exactly as a finger on the crown
    /// would — what is staged is the input, never the grade.
    private func demoSpin() async {
        guard let demoSpinStep else { return }
        while !Task.isCancelled, grade == nil {
            try? await Task.sleep(for: .seconds(demoSpinInterval))
            guard !Task.isCancelled else { return }
            crown = (crown + demoSpinStep).truncatingRemainder(dividingBy: Self.crownRange)
        }
    }
    #endif

    // MARK: - The rules, as pure functions

    /// The scale the crown binding runs on, and the point it wraps at. Wide enough that a whole
    /// sprint rarely reaches the end of it, and `isContinuous` plus `crownDelta` mean it costs
    /// nothing when it does.
    static let crownRange: Double = 1000

    /// How much the binding moves per detent of the crown. Together with `sensitivity` this is the
    /// whole feel of the game, and neither number has a documented physical meaning — see
    /// `defaultRotationTarget`.
    static let crownStride: Double = 1

    /// What the game ships at, named rather than left as an inline literal so the pure tests assert
    /// against the target the app actually plays.
    ///
    /// How many binding units a revolution of the crown is worth is the system's business, not
    /// ours, so this is a first guess at "a brisk few seconds of spinning" rather than a measured
    /// number — which is exactly why it is injectable. US-082 can retune it per Digimon without
    /// touching a rule.
    static let defaultRotationTarget: Double = 120

    /// Where the `great` and `good` floors sit, as shares of the target.
    ///
    /// A half and a quarter, so with any sensible target every floor is exactly representable and a
    /// boundary test asserts ON the number rather than a whisker either side of one floating-point
    /// rounding has already moved. Same reason as `PowerMeterGame.greatShare`.
    static let greatShare: Double = 0.5
    static let goodShare: Double = 0.25

    /// What a round that travelled `rotation` units against `target` earns.
    ///
    /// Floors are INCLUSIVE of the better grade — landing exactly on the number is landing in, the
    /// same way round as the masher's thresholds and the meter's band edges.
    ///
    /// A non-positive target is a `miss` whatever the rotation: a degenerate target must not hand a
    /// perfect to a crown nobody touched.
    static func grade(rotation: Double, target: Double) -> TrainingResult {
        guard target > 0 else { return .miss }
        if rotation >= target { return .perfect }
        if rotation >= target * greatShare { return .great }
        if rotation >= target * goodShare { return .good }
        return .miss
    }

    /// How full the gauge is, 0 to 1. Clamped at both ends, and empty for a non-positive target
    /// rather than dividing by zero.
    static func progress(rotation: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(max(rotation / target, 0), 1)
    }

    /// The number in the middle of the gauge. Rounded DOWN, so it only says 100% when the sprint is
    /// actually finished.
    static func percentLabel(rotation: Double, target: Double) -> String {
        "\(Int((progress(rotation: rotation, target: target) * 100).rounded(.down)))%"
    }

    /// How far the crown travelled when its binding moved from `old` to `new`, as a distance.
    ///
    /// Unsigned, because a sprint counts rotation in EITHER direction: making the user spin one way
    /// only would turn a speed test into a dexterity test, and the crown does not say which way is
    /// forward.
    ///
    /// The binding is continuous, so it wraps from the top of its range back to the bottom. A wrap
    /// is a tiny movement that looks like an enormous one, so the shorter way round is always the
    /// true distance — without this, one wrap would win the round outright.
    static func crownDelta(from old: Double, to new: Double, range: Double) -> Double {
        let raw = new - old
        guard range > 0 else { return abs(raw) }
        let wrapped = raw.truncatingRemainder(dividingBy: range)
        if wrapped > range / 2 { return abs(wrapped - range) }
        if wrapped < -range / 2 { return abs(wrapped + range) }
        return abs(wrapped)
    }

    // MARK: - Drawing constants

    static let gaugeHeight: CGFloat = 62
    static let barHeight: CGFloat = 6
}

#Preview {
    CrownSprintGame(onFinish: { _ in })
}
