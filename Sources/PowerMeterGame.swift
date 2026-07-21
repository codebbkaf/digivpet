import SwiftUI

/// The third training minigame (US-078): hold to charge the meter, let go before it overloads.
///
/// Where the timing bar asks you to stop a marker and the masher asks for speed, this one asks you to
/// stop yourself: the meter keeps filling for exactly as long as you hold, the best grade lives near
/// the top of it, and holding past the target band bursts the meter for nothing. Charging harder is
/// always worth more right up until it is worth nothing at all, which is the whole game.
///
/// As with the other two, the rule is pure: `fill(afterHolding:fillRate:)` says how charged the meter
/// is after a hold and `grade(fill:lowerBound:upperBound:)` says what letting go there is worth, so
/// "grade-from-fill is pure and unit-tested including the overload case" is assertable without
/// hosting a view or holding anything.
///
/// It reports EXACTLY ONE grade, as `TrainingMinigame` requires: the one its release earned, the
/// overload if the meter burst, or `.miss` if `idleTimeout` elapses untouched. A round the user has
/// already paid for must always end.
struct PowerMeterGame: TrainingMinigame {
    static let title = "Power Meter"

    /// How fast the meter charges, in meter-fractions per second. Injected, in the manner of
    /// `ButtonMasherGame.window`, so a test drives a whole charge by arithmetic and never waits one —
    /// and so US-082 can hand a Digimon a twitchier meter.
    ///
    /// The default fills the whole meter in two seconds, which leaves the target band open for half a
    /// second: long enough to aim for, short enough that you cannot drift into it.
    var fillRate: Double = defaultFillRate

    /// The bottom of the target band, as a fraction of the meter. Releasing at or above this — and at
    /// or below `bandUpperBound` — is a `perfect`.
    var bandLowerBound: CGFloat = defaultBandLowerBound

    /// The top of the target band. Above this the meter is overloaded and the round pays nothing,
    /// however long you held it: see `grade(fill:lowerBound:upperBound:)`.
    var bandUpperBound: CGFloat = defaultBandUpperBound

    /// How long the grade holds on screen before the round hands it back. Matches the other two games'
    /// for the same reason: long enough to read, short enough that training does not become a sequence
    /// of dismissals.
    var resultDuration: TimeInterval = 1.0

    /// How long the round waits for the FIRST touch before ending itself as a `.miss`. Once held it is
    /// the meter's own capacity that ends the round; this only covers the round nobody plays — see
    /// `TrainingMinigame.init(onFinish:)`.
    var idleTimeout: TimeInterval = 12

    #if DEBUG
    /// Debug-only: a fill to start the round already charged to, instead of an untouched zero. nil in
    /// the app — every charge is a real hold. Set by `ContentView`'s meter demos so a `simctl`
    /// screenshot lands on a meter with something in it, since `simctl` cannot hold one down.
    ///
    /// It stages HOW FAR the charge got, not what that is worth: the fill is back-dated onto the real
    /// clock and still read by the same pure `grade(fill:lowerBound:upperBound:)`.
    var demoFill: CGFloat? = nil

    /// Debug-only: whether the staged charge is let go of at once, so a screenshot lands on a decided
    /// round rather than a meter still climbing. Goes through the same `release` the finger does.
    var demoReleasesImmediately = false
    #endif

    private let onFinish: (TrainingResult) -> Void

    init(onFinish: @escaping (TrainingResult) -> Void) {
        self.onFinish = onFinish
    }

    /// When the hold began, and so when the meter started filling. nil until a finger is down.
    @State private var holdStart: Date?

    /// Where the meter was let go, and what that was worth. nil while it is still charging; set
    /// exactly once.
    private struct Release: Equatable {
        let fill: CGFloat
        let grade: TrainingResult
    }
    @State private var release: Release?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                Text(release?.grade.displayName ?? Self.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(release?.grade.tint ?? Color.primary)

                meter

                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The whole screen is the button, for the same reason it is in the other two games: what is
        // meant to be hard is knowing when to let go, not keeping a finger on a small target.
        // A zero-distance drag is what gives us a press and a release; `onTapGesture` gives neither.
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginHold() }
                .onEnded { _ in letGo() }
        )
        .task(id: holdStart) { await runRound() }
        .task(id: release) { await handOffGrade() }
    }

    private var footer: String {
        if let release { return "+\(release.grade.strengthGain) STR" }
        return holdStart == nil ? "Hold to charge" : "Let go in the band!"
    }

    /// The meter: the target band, the overload zone above it, and the charge itself.
    ///
    /// Band and overload zone are drawn from the SAME `bandEdges` the grade is read off, so what the
    /// user aims at cannot drift out of step with what letting go is worth.
    private var meter: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let edges = Self.bandEdges(lowerBound: bandLowerBound, upperBound: bandUpperBound)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))

                region(from: edges.lower, to: edges.upper, in: width)
                    .fill(Color.yellow.opacity(0.45))

                region(from: edges.upper, to: Self.meterCapacity, in: width)
                    .fill(Color.red.opacity(0.35))

                // Paused once released, so the charge holds exactly where it was graded rather than
                // climbing on past the evidence.
                TimelineView(.animation(paused: holdStart == nil || release != nil)) { context in
                    charge(to: fill(now: context.date), in: width)
                }
            }
        }
        .frame(height: Self.meterHeight)
    }

    /// One stretch of the meter, from `from` to `to` as fractions of its width.
    private func region(from: CGFloat, to: CGFloat, in width: CGFloat) -> some Shape {
        Capsule()
            .path(in: CGRect(x: from * width, y: 0,
                             width: max(0, to - from) * width, height: Self.meterHeight))
    }

    /// The charge, filling from the left. Tinted by the zone it has reached, so the meter says on its
    /// own whether letting go now would pay — there is no time to read a label mid-hold.
    private func charge(to fill: CGFloat, in width: CGFloat) -> some View {
        Capsule()
            .fill(Self.chargeTint(fill: fill, lowerBound: bandLowerBound, upperBound: bandUpperBound))
            .frame(width: fill * width)
    }

    /// How full to draw the meter: frozen at the graded release, or charged from the clock.
    private func fill(now: Date) -> CGFloat {
        if let release { return release.fill }
        guard let holdStart else { return 0 }
        return Self.fill(afterHolding: now.timeIntervalSince(holdStart), fillRate: fillRate)
    }

    /// The finger going down. `DragGesture.onChanged` fires for every movement of the hold, so this
    /// only starts the clock the first time — and never restarts it on a round already decided.
    private func beginHold() {
        guard release == nil, holdStart == nil else { return }
        holdStart = Date()
    }

    /// The finger coming up. Ignored once the round is decided, so letting go of a burst meter cannot
    /// re-grade it.
    private func letGo() {
        guard release == nil, let holdStart else { return }
        letGo(holdingSince: holdStart)
    }

    /// Grades a hold that began at `start` and ended now, through the one pure rule.
    private func letGo(holdingSince start: Date) {
        let fill = Self.fill(afterHolding: Date().timeIntervalSince(start), fillRate: fillRate)
        settle(Self.grade(fill: fill, lowerBound: bandLowerBound, upperBound: bandUpperBound),
               at: fill)
    }

    private func settle(_ grade: TrainingResult, at fill: CGFloat) {
        withAnimation(.easeOut(duration: 0.15)) {
            release = Release(fill: fill, grade: grade)
        }
    }

    /// The round's own clock. Before the first touch it is the idle timeout that is running; the press
    /// that sets `holdStart` cancels this and restarts it as the meter's own fuse, which burns out
    /// when the meter reaches capacity.
    private func runRound() async {
        guard let holdStart else {
            #if DEBUG
            if let demoFill {
                // Back-dated onto the real clock, so the staged charge is a hold that has been
                // running for exactly as long as that fill takes. Setting holdStart re-fires this
                // task, which then runs the real fuse from there.
                let staged = Date().addingTimeInterval(
                    -Self.holdDuration(toReach: demoFill, fillRate: fillRate))
                self.holdStart = staged
                if demoReleasesImmediately { letGo(holdingSince: staged) }
                return
            }
            #endif
            try? await Task.sleep(for: .seconds(idleTimeout))
            guard !Task.isCancelled, self.holdStart == nil else { return }
            // Never played, so never paid — and a miss whatever the band is set to, because a round
            // nobody touched must not come out a perfect on a degenerate lower bound.
            return settle(.miss, at: 0)
        }

        // The fuse runs to the moment the meter bursts, however long that is — it must NOT be capped
        // at `idleTimeout`, which would cut a slow meter's round short at whatever it happened to
        // have reached and hand out a grade nobody asked for. The timeout is only the fallback for a
        // meter that cannot fill at all — an injected rate of zero, whose fuse is infinite.
        let fuse = Self.holdDuration(toReach: Self.meterCapacity, fillRate: fillRate)
            - Date().timeIntervalSince(holdStart)
        try? await Task.sleep(for: .seconds(fuse.isFinite ? max(0, fuse) : idleTimeout))
        guard !Task.isCancelled, release == nil else { return }
        // Held too long: the meter is graded exactly where it ended up, which past the band's top is
        // the overload and pays nothing.
        letGo(holdingSince: holdStart)
    }

    /// Holds the graded result on screen, then hands it back — once, which is the whole contract a
    /// minigame has with `TrainAction`.
    private func handOffGrade() async {
        guard let release else { return }
        try? await Task.sleep(for: .seconds(resultDuration))
        guard !Task.isCancelled else { return }
        onFinish(release.grade)
    }

    // MARK: - The rules, as pure functions

    /// How full the meter can get before it bursts. The round ends itself here.
    static let meterCapacity: CGFloat = 1

    /// What the game ships at. Named rather than inline literals so the pure tests can assert against
    /// the band the app actually plays, instead of pinning a band of their own that a later tweak to
    /// the stored properties would silently leave behind.
    ///
    /// Eighths and a half: every band edge and every hold duration derived from them is then exactly
    /// representable, so a boundary test asserts ON the number rather than a whisker either side of
    /// one floating-point rounding has already moved.
    static let defaultFillRate: Double = 0.5
    static let defaultBandLowerBound: CGFloat = 0.625
    static let defaultBandUpperBound: CGFloat = 0.875

    /// Where the `great` and `good` floors sit, as shares of the target band's bottom edge.
    ///
    /// Halves on purpose, and the shipped bounds are eighths, so every band edge is exactly
    /// representable and a test can assert the grade AT a boundary rather than a whisker either side
    /// of a number floating-point rounding has already moved. US-076 lost an afternoon to that.
    static let greatShare: CGFloat = 0.5
    static let goodShare: CGFloat = 0.25

    /// The four floors the grade is read off, as fractions of the meter: the `good` and `great`
    /// floors on the way up, then the target band itself.
    ///
    /// One source of truth for both the drawing and the grading. The bounds are sanitised here — the
    /// lower clamped into the meter, the upper never below it — so absurd injected bounds cannot
    /// produce a band wider than the meter or one that reads backwards.
    static func bandEdges(lowerBound: CGFloat, upperBound: CGFloat)
        -> (good: CGFloat, great: CGFloat, lower: CGFloat, upper: CGFloat) {
        let lower = min(max(lowerBound, 0), meterCapacity)
        let upper = min(max(upperBound, lower), meterCapacity)
        return (lower * goodShare, lower * greatShare, lower, upper)
    }

    /// What letting go with the meter at `fill` earns.
    ///
    /// Above the band is a `.miss` and it is checked FIRST: that is the overload, and the point of
    /// the game. It pays nothing rather than the next grade down, so greed costs the whole round and
    /// not a point of it — the round happened and the energy is still spent, which is why
    /// `TrainAction.begin` charges on entry.
    ///
    /// Below the band the grade rises with the charge, so a cautious release still pays something.
    /// Every floor is INCLUSIVE of the better grade: landing exactly on the line is landing in, the
    /// same way round as the timing bar's band edges and the masher's thresholds.
    static func grade(fill: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> TrainingResult {
        let edges = bandEdges(lowerBound: lowerBound, upperBound: upperBound)
        if fill > edges.upper { return .miss }
        if fill >= edges.lower { return .perfect }
        if fill >= edges.great { return .great }
        if fill >= edges.good { return .good }
        return .miss
    }

    /// How full the meter is after holding for `elapsed` seconds, capped at `meterCapacity`.
    ///
    /// A RATE rather than a set of durations, for the reason `ButtonMasherGame` uses taps per second:
    /// `fillRate` is injectable, and the band has to mean the same thing at any rate. A non-positive
    /// rate leaves the meter empty rather than dividing by zero.
    static func fill(afterHolding elapsed: TimeInterval, fillRate: Double) -> CGFloat {
        guard fillRate > 0 else { return 0 }
        return min(CGFloat(max(0, elapsed) * fillRate), meterCapacity)
    }

    /// The inverse: how long a hold has to last to charge the meter to `fill`. Infinite for a meter
    /// that does not fill, which is what caps the round's fuse at `idleTimeout` instead.
    static func holdDuration(toReach fill: CGFloat, fillRate: Double) -> TimeInterval {
        guard fillRate > 0 else { return .infinity }
        return Double(max(0, fill)) / fillRate
    }

    /// The whole game in one call: what letting go `elapsed` seconds into a hold is worth. This is the
    /// path `letGo` takes, so a test exercises the real rule rather than a re-derivation of it.
    static func grade(releasingAfter elapsed: TimeInterval,
                      fillRate: Double,
                      lowerBound: CGFloat,
                      upperBound: CGFloat) -> TrainingResult {
        grade(fill: fill(afterHolding: elapsed, fillRate: fillRate),
              lowerBound: lowerBound, upperBound: upperBound)
    }

    /// What colour the charge is drawn in at `fill`: climbing, in the band, or overloaded. Distinct
    /// from `TrainingResult.tint`, which announces a finished round — this is the live warning, and
    /// the red has to arrive while there is still a finger down to lift.
    static func chargeTint(fill: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> Color {
        let edges = bandEdges(lowerBound: lowerBound, upperBound: upperBound)
        if fill > edges.upper { return .red }
        if fill >= edges.lower { return .yellow }
        return .orange
    }

    // MARK: - Drawing constants

    static let meterHeight: CGFloat = 14
}

#Preview {
    PowerMeterGame(onFinish: { _ in })
}
