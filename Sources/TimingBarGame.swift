import SwiftUI

/// The first training minigame (US-076): a marker sweeps a bar, a tap stops it, and where it stopped
/// decides the grade.
///
/// The whole rule of the game is two pure functions — `position(at:sweepDuration:)` says where the
/// marker is at a moment, `grade(at:zoneWidth:)` says what stopping there is worth — and the view is
/// only what draws them and takes the tap. That split is what makes "grade-from-position is pure and
/// unit-tested at each zone boundary" assertable without hosting a view or waiting a sweep.
///
/// It reports EXACTLY ONE grade, as `TrainingMinigame` requires: either the tap's, or `.miss` if
/// `roundTimeout` elapses with nothing tapped. A round the user has already paid for must always end.
struct TimingBarGame: TrainingMinigame {
    static let title = "Timing Bar"

    /// Seconds for one full round trip — left edge to right edge and back. Injected, in the manner of
    /// `BattleView.turnDuration`, so a test drives a whole sweep by arithmetic and never waits one.
    var sweepDuration: TimeInterval = 1.8

    /// The target zone's full width, as a fraction of the bar. Injected for the same reason, and
    /// because US-082 may want a harder or easier bar per Digimon without a second game.
    ///
    /// The default is a quarter of the bar, which at the perfect sub-zone's share is a centre band
    /// about 6% of the bar wide — hittable, but not by tapping blindly.
    var zoneWidth: CGFloat = 0.25

    /// How long the grade holds on screen before the round hands it back. Long enough to read, short
    /// enough that training does not become a sequence of dismissals.
    var resultDuration: TimeInterval = 1.0

    /// How long a round waits for a tap before ending itself as a `.miss`. A round that never ends is
    /// a round the user has paid for and cannot leave — see `TrainingMinigame.init(onFinish:)`.
    var roundTimeout: TimeInterval = 12

    #if DEBUG
    /// Debug-only: a position to start the round already stopped at, instead of sweeping. nil in the
    /// app — every round is played. Set by `ContentView`'s `-timingBarResultDemo` so a `simctl`
    /// screenshot lands on a decided round rather than on a marker that cannot be tapped, the same
    /// staging `BattleView.demoFocusTurn` does. It stages WHERE the round ends, not how it is graded:
    /// the grade still comes from the same pure `grade(at:zoneWidth:)` the tap goes through.
    var demoStopPosition: CGFloat? = nil
    #endif

    private let onFinish: (TrainingResult) -> Void

    init(onFinish: @escaping (TrainingResult) -> Void) {
        self.onFinish = onFinish
    }

    /// Where the marker came to rest, and what that was worth. nil while it is still sweeping.
    private struct Stop: Equatable {
        let position: CGFloat
        let grade: TrainingResult
    }
    @State private var stop: Stop?

    /// When the sweep started. The marker's position is derived from the clock rather than stepped by
    /// a timer, so what a tap grades is exactly where the marker is at the instant of the tap.
    @State private var startDate = Date()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                Text(stop?.grade.displayName ?? Self.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(stop?.grade.tint ?? Color.primary)

                bar

                Text(stop.map { "+\($0.grade.strengthGain) STR" } ?? "Tap to stop")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The whole screen is the button: a 3pt marker moving at speed is not something to ask
        // anyone to hit with a finger, and it is the TIMING that is meant to be hard, not the aim.
        .contentShape(Rectangle())
        .onTapGesture { tap() }
        .task { await runRound() }
        .task(id: stop) { await handOffGrade() }
    }

    /// The bar itself: the target zone, the perfect sub-zone inside it, and the marker.
    ///
    /// Zone and sub-zone are drawn from the SAME `bandEdges` the grade is read off, so what the user
    /// aims at cannot drift out of step with what the tap is worth.
    private var bar: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let edges = Self.bandEdges(zoneWidth: zoneWidth)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))

                band(halfWidth: edges.zone, in: width)
                    .fill(Color.green.opacity(0.45))

                band(halfWidth: edges.perfect, in: width)
                    .fill(Color.yellow)

                // Paused once stopped, so the marker holds exactly where it was graded rather than
                // sweeping on past the evidence.
                TimelineView(.animation(paused: stop != nil)) { context in
                    marker(at: position(now: context.date), in: width)
                }
            }
        }
        .frame(height: Self.barHeight)
    }

    /// One band of the target, centred on the bar and reaching `halfWidth` (a fraction of the bar) to
    /// each side of centre.
    private func band(halfWidth: CGFloat, in width: CGFloat) -> some Shape {
        Capsule()
            .path(in: CGRect(x: (0.5 - halfWidth) * width, y: 0,
                             width: 2 * halfWidth * width, height: Self.barHeight))
    }

    private func marker(at position: CGFloat, in width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.white)
            .frame(width: Self.markerWidth, height: Self.barHeight + 6)
            .offset(x: position * width - Self.markerWidth / 2, y: -3)
    }

    /// Where to draw the marker: frozen at the graded stop, or swept from the clock.
    private func position(now: Date) -> CGFloat {
        stop?.position ?? Self.position(at: now.timeIntervalSince(startDate),
                                        sweepDuration: sweepDuration)
    }

    /// The tap. Ignored once the round is decided, so a second tap on the result cannot re-grade it.
    private func tap() {
        guard stop == nil else { return }
        let landed = Self.position(at: Date().timeIntervalSince(startDate),
                                   sweepDuration: sweepDuration)
        settle(Self.grade(at: landed, zoneWidth: zoneWidth), at: landed)
    }

    private func settle(_ grade: TrainingResult, at position: CGFloat) {
        withAnimation(.easeOut(duration: 0.15)) {
            stop = Stop(position: position, grade: grade)
        }
    }

    /// The round's own clock: it ends itself as a `.miss` if nothing is tapped.
    private func runRound() async {
        #if DEBUG
        if let demoStopPosition {
            return settle(Self.grade(at: demoStopPosition, zoneWidth: zoneWidth), at: demoStopPosition)
        }
        #endif
        try? await Task.sleep(for: .seconds(roundTimeout))
        guard !Task.isCancelled, stop == nil else { return }
        // Frozen where the marker actually was, but graded a miss whatever that was: the round was
        // not played, and landing in the zone by standing still must not pay.
        settle(.miss, at: Self.position(at: roundTimeout, sweepDuration: sweepDuration))
    }

    /// Holds the graded result on screen, then hands it back — once, which is the whole contract a
    /// minigame has with `TrainAction`.
    private func handOffGrade() async {
        guard let stop else { return }
        try? await Task.sleep(for: .seconds(resultDuration))
        guard !Task.isCancelled else { return }
        onFinish(stop.grade)
    }

    // MARK: - The rules, as pure functions

    /// The perfect and great bands, as shares of the target zone's half-width.
    ///
    /// Powers of two on purpose: every band edge is then exactly representable for any sensible
    /// `zoneWidth`, so a test can assert the grade AT a boundary rather than a whisker either side of
    /// a number floating-point rounding has already moved.
    static let perfectShare: CGFloat = 0.25
    static let greatShare: CGFloat = 0.5

    /// How far from the centre of the bar each band reaches, as a fraction of the whole bar.
    ///
    /// One source of truth for both the drawing and the grading. `zoneWidth` is clamped to 0...1, so
    /// an absurd injected width cannot produce a zone wider than the bar it is drawn on.
    static func bandEdges(zoneWidth: CGFloat) -> (perfect: CGFloat, great: CGFloat, zone: CGFloat) {
        let zone = min(max(zoneWidth, 0), 1) / 2
        return (zone * perfectShare, zone * greatShare, zone)
    }

    /// What stopping the marker at `position` (0 at the left end of the bar, 1 at the right) earns.
    ///
    /// Outside the zone is a `.miss` — the round happened and the energy is still spent, which is why
    /// `TrainAction.begin` charges on entry. Inside it, the closer to centre the better, with the
    /// centre sub-zone paying `.perfect`. Edges are INCLUSIVE of the better grade: landing exactly on
    /// the line is landing in, which is the way round that never punishes a hit.
    static func grade(at position: CGFloat, zoneWidth: CGFloat) -> TrainingResult {
        let edges = bandEdges(zoneWidth: zoneWidth)
        let distance = abs(position - 0.5)
        if distance > edges.zone { return .miss }
        if distance <= edges.perfect { return .perfect }
        if distance <= edges.great { return .great }
        return .good
    }

    /// Where the marker is `elapsed` seconds into the round: 0 at the left end, 1 at the right,
    /// bouncing back and forth with a period of `sweepDuration`.
    ///
    /// A triangle wave rather than a wrap-around, so the marker reverses at the ends instead of
    /// teleporting back to the left. A non-positive `sweepDuration` parks it dead centre rather than
    /// dividing by zero.
    static func position(at elapsed: TimeInterval, sweepDuration: TimeInterval) -> CGFloat {
        guard sweepDuration > 0 else { return 0.5 }
        let phase = (max(0, elapsed) / sweepDuration).truncatingRemainder(dividingBy: 1)
        return CGFloat(phase < 0.5 ? phase * 2 : 2 - phase * 2)
    }

    /// The whole game in one call: what a tap `elapsed` seconds into the round is worth. This is the
    /// path `tap()` takes, so a test exercises the real rule rather than a re-derivation of it.
    static func grade(stoppingAt elapsed: TimeInterval,
                      sweepDuration: TimeInterval,
                      zoneWidth: CGFloat) -> TrainingResult {
        grade(at: position(at: elapsed, sweepDuration: sweepDuration), zoneWidth: zoneWidth)
    }

    // MARK: - Drawing constants

    static let barHeight: CGFloat = 14
    static let markerWidth: CGFloat = 3
}

#Preview {
    TimingBarGame(onFinish: { _ in })
}
