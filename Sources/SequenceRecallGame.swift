import SwiftUI

/// The sixth training minigame (US-081): watch a pattern, then play it back from memory.
///
/// The other five all measure the body — a tap on a beat, a burst of taps, a hold, a spin, a
/// reaction. This one measures memory, and so it is the first game where the round can end while the
/// user is still doing everything right: the first wrong entry stops it dead, and what you had
/// remembered up to that point is what you are paid for.
///
/// As with the other five the rules are pure. `sequence(using:length:)` draws the pattern from the
/// project's own `SeededGenerator`, so a test pins a pattern instead of hoping for one;
/// `correctCount(of:against:)` is the stop-at-the-first-mistake rule on its own; and
/// `grade(correct:length:)` reads a count of remembered steps. None of the three needs a view.
///
/// It reports EXACTLY ONE grade, as `TrainingMinigame` requires: the one its recall earned, whether
/// the round ended on a wrong entry, a complete pattern, or `inputTimeout` elapsing with the user
/// never answering. A round the user has already paid for must always end.
struct SequenceRecallGame: TrainingMinigame {
    static let title = "Sequence Recall"

    /// How many steps the pattern is. Injected, in the manner of `ButtonMasherGame.window`, so a test
    /// drives a whole round by arithmetic and so US-082 can hand a Digimon a longer pattern.
    ///
    /// Four is deliberately short: the pads are the size of a fingertip and the screen is a watch, so
    /// the difficulty here is meant to be remembering, not scrolling back through a long recital.
    var sequenceLength: Int = 4

    /// How long each pad stays lit during playback, in seconds. The playback speed, in other words —
    /// injectable for the same reason `sequenceLength` is, and because a test that had to sit through
    /// a real recital would be waiting seconds per round.
    var stepDuration: TimeInterval = 0.45

    /// The dark gap between two lit pads, in seconds.
    ///
    /// It exists so a pattern that lights the SAME pad twice in a row reads as two steps rather than
    /// one long flash. That is the only thing standing between the game and an unfair round, so it is
    /// never zero in the shipped game — see `sequence(using:length:)`, which allows repeats.
    var stepGap: TimeInterval = 0.18

    /// Where the pattern comes from. Injected in the manner of `ReflexStrikeGame.makeGenerator`, so a
    /// test hands the round a pinned seed and knows exactly which pads are coming, while the app gets
    /// a pattern it cannot learn.
    ///
    /// A factory rather than a generator, because `SeededGenerator` is a value type that must be
    /// mutated to draw from: the round makes its own and keeps the draw sequence to itself.
    var makeGenerator: () -> SeededGenerator = {
        SeededGenerator(seed: UInt64.random(in: UInt64.min...UInt64.max))
    }

    /// How long the round waits for the user to play the pattern back before ending itself on
    /// whatever they had remembered so far. Covers the round nobody answers — see
    /// `TrainingMinigame.init(onFinish:)`.
    var inputTimeout: TimeInterval = 12

    /// How long the grade holds on screen before the round hands it back. Matches the other five
    /// games' for the same reason: long enough to read, short enough that training does not become a
    /// sequence of dismissals.
    var resultDuration: TimeInterval = 1.0

    #if DEBUG
    /// Debug-only: how many steps of the pattern to start the round already having played back
    /// correctly, instead of an empty attempt. nil in the app — every entry is a real tap. Set by
    /// `ContentView`'s recall demos so a `simctl` screenshot lands on a decided round, since `simctl`
    /// cannot tap one out.
    ///
    /// It stages HOW MUCH was remembered, not what it was worth: a short attempt is completed with a
    /// deliberately wrong pad and then read by the same pure `correctCount(of:against:)` and
    /// `grade(correct:length:)` a real attempt is, which is how the wrong-entry ending gets its own
    /// screenshot.
    var demoCorrectCount: Int? = nil
    #endif

    private let onFinish: (TrainingResult) -> Void

    init(onFinish: @escaping (TrainingResult) -> Void) {
        self.onFinish = onFinish
    }

    /// The pattern this round is asking for, drawn once when the round starts. Empty until then.
    @State private var sequence: [Int] = []

    /// What the user has entered so far, in order — including the wrong entry that ended the round.
    /// Kept whole rather than as a count so `correctCount(of:against:)` grades the attempt itself.
    @State private var entries: [Int] = []

    /// Which pad is lit right now: the one being played back, or the one just entered. nil is every
    /// pad dark.
    @State private var litPad: Int?

    /// Whether playback has finished and the round is listening. Taps before this are ignored — the
    /// game is a memory test, and letting someone answer during the recital would make it a copying
    /// test instead.
    @State private var acceptsInput = false

    /// What the round earned. nil until it is over; set exactly once.
    @State private var grade: TrainingResult?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 6) {
                Text(grade?.displayName ?? Self.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(grade?.tint ?? Color.primary)

                pads

                progress

                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await runRound() }
        .task(id: grade) { await handOffGrade() }
    }

    /// The four pads, in a two by two grid. Unlike the other five games the target is NOT the whole
    /// screen — here WHICH one you hit is the entire answer.
    private var pads: some View {
        VStack(spacing: Self.padSpacing) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: Self.padSpacing) {
                    ForEach(0..<2, id: \.self) { column in
                        pad(row * 2 + column)
                    }
                }
            }
        }
    }

    /// One pad: dim when dark, its own colour when lit.
    ///
    /// Colour AND a symbol, because a pattern told apart by hue alone is unplayable for a colourblind
    /// user — the symbol is what makes the four distinguishable, and the colour is what makes them
    /// quick to distinguish.
    private func pad(_ index: Int) -> some View {
        let isLit = litPad == index
        return RoundedRectangle(cornerRadius: Self.padCornerRadius)
            .fill(Self.tint(for: index).opacity(isLit ? 1 : 0.25))
            .overlay {
                Image(systemName: Self.symbol(for: index))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black.opacity(isLit ? 0.85 : 0.4))
            }
            .frame(width: Self.padSize, height: Self.padSize)
            .contentShape(Rectangle())
            .onTapGesture { tap(pad: index) }
            .animation(.easeOut(duration: 0.08), value: litPad)
    }

    /// One dot per step of the pattern, filled as it is remembered. It is the only thing on screen
    /// that says how far through the answer you are — the pads themselves cannot show it, since
    /// showing which one is next would be showing the answer.
    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(sequence.indices, id: \.self) { step in
                Circle()
                    .fill(step < correct ? (grade?.tint ?? Color.green) : Color.secondary.opacity(0.3))
                    .frame(width: Self.dotDiameter, height: Self.dotDiameter)
            }
        }
        .frame(height: Self.dotDiameter)
        .animation(.easeOut(duration: 0.1), value: entries)
    }

    /// How much of the pattern has been played back correctly so far — the same pure rule that
    /// decides the round, so what the dots show is what the grade will be read from.
    private var correct: Int {
        Self.correctCount(of: entries, against: sequence)
    }

    private var footer: String {
        if let grade { return "+\(grade.strengthGain) STR" }
        return acceptsInput ? "Your turn — \(correct)/\(sequence.count)" : "Watch…"
    }

    /// One entry. Ignored during playback and once the round is decided, so tapping along with the
    /// recital or on the result cannot change either.
    ///
    /// The wrong-entry ending lives here, but the rule itself does not: the attempt is appended and
    /// then read by `correctCount(of:against:)`, so what ends the round is the same function the
    /// tests assert on.
    private func tap(pad: Int) {
        guard acceptsInput, grade == nil else { return }
        entries.append(pad)
        // The pad you pressed stays lit until you press another, so an entry is always visibly
        // acknowledged — and so the wrong one is still lit under the verdict that ended the round.
        withAnimation(.easeOut(duration: 0.08)) { litPad = pad }

        let correct = Self.correctCount(of: entries, against: sequence)
        // Either the entry was wrong — in which case `correct` has stopped short of what was entered
        // and the round is over — or it was right and completed the pattern.
        guard correct < entries.count || correct == sequence.count else { return }
        settle(Self.grade(correct: correct, length: sequence.count))
    }

    private func settle(_ grade: TrainingResult) {
        acceptsInput = false
        withAnimation(.easeOut(duration: 0.15)) {
            self.grade = grade
        }
    }

    /// The round: draw a pattern, play it back, then listen.
    private func runRound() async {
        var generator = makeGenerator()
        sequence = Self.sequence(using: &generator, length: sequenceLength)

        #if DEBUG
        if let demoCorrectCount {
            return stageDemoAttempt(correct: demoCorrectCount)
        }
        #endif

        for step in sequence {
            withAnimation(.easeOut(duration: 0.06)) { litPad = step }
            try? await Task.sleep(for: .seconds(stepDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.06)) { litPad = nil }
            // The gap is what makes a repeated pad two flashes instead of one — see `stepGap`.
            try? await Task.sleep(for: .seconds(stepGap))
            guard !Task.isCancelled else { return }
        }

        acceptsInput = true

        try? await Task.sleep(for: .seconds(inputTimeout))
        guard !Task.isCancelled, grade == nil else { return }
        // Never answered, or answered too slowly to finish: paid for what was remembered, which for
        // an untouched round is nothing.
        settle(Self.grade(correct: Self.correctCount(of: entries, against: sequence),
                          length: sequence.count))
    }

    #if DEBUG
    /// Stages an attempt that remembered `correct` steps, then lets the real rules decide it.
    ///
    /// A short attempt is finished with a pad that is deliberately NOT the next one, so the staged
    /// round ends the way a real one does — on a wrong entry — rather than by asserting a grade.
    private func stageDemoAttempt(correct: Int) {
        let remembered = min(max(0, correct), sequence.count)
        entries = Array(sequence.prefix(remembered))
        if remembered < sequence.count {
            entries.append(Self.wrongPad(insteadOf: sequence[remembered]))
        }
        litPad = entries.last
        settle(Self.grade(correct: Self.correctCount(of: entries, against: sequence),
                          length: sequence.count))
    }
    #endif

    /// Holds the graded result on screen, then hands it back — once, which is the whole contract a
    /// minigame has with `TrainAction`.
    private func handOffGrade() async {
        guard let grade else { return }
        try? await Task.sleep(for: .seconds(resultDuration))
        guard !Task.isCancelled else { return }
        onFinish(grade)
    }

    // MARK: - The rules, as pure functions

    /// How many pads there are to choose between. Four: two by two fits a watch face at a size a
    /// fingertip can hit, and a fifth pad would shrink every one of them.
    static let padCount = 4

    /// A pattern of `length` steps, each a pad index in `0..<padCount`, drawn from `generator`.
    ///
    /// Pulled out of the view so the pattern is testable without hosting one: with a pinned seed this
    /// returns the same steps on every machine, which is what lets a test know what the round is
    /// asking for. See `SeededGenerator`.
    ///
    /// Consecutive repeats are ALLOWED — a pattern that could never light the same pad twice would
    /// leak information about what is coming. `stepGap` is what keeps them readable.
    ///
    /// A non-positive length is an empty pattern rather than a trap; `grade(correct:length:)` reads
    /// that as a `miss`, since a round with nothing to remember cannot be remembered perfectly.
    static func sequence(using generator: inout SeededGenerator, length: Int) -> [Int] {
        guard length > 0 else { return [] }
        return (0..<length).map { _ in Int.random(in: 0..<padCount, using: &generator) }
    }

    /// How many steps of `sequence` the attempt got right, stopping at the FIRST entry that does not
    /// match.
    ///
    /// This is the whole "the first wrong entry ends the round" rule, as one pure function: nothing
    /// after a mistake counts, so a lucky guess later in the pattern can never be worth anything. An
    /// attempt longer than the pattern stops at the pattern's end for the same reason.
    static func correctCount(of attempt: [Int], against sequence: [Int]) -> Int {
        var correct = 0
        for (entry, step) in zip(attempt, sequence) {
            guard entry == step else { break }
            correct += 1
        }
        return correct
    }

    /// The share of the pattern each grade asks to be remembered.
    ///
    /// A SHARE rather than a flat count, because `sequenceLength` is injectable: with fixed counts,
    /// doubling the pattern would silently make every round easier, in the same way and for the same
    /// reason `ButtonMasherGame.tapsPerSecond` is a rate. A `perfect` is the exception — it is 1, the
    /// whole pattern, because "a fully correct sequence yields perfect" is the game's premise and not
    /// a threshold to be tuned.
    static func requiredShare(for grade: TrainingResult) -> Double {
        switch grade {
        case .miss: return 0
        case .good: return 0.5
        case .great: return 0.75
        case .perfect: return 1
        }
    }

    /// How many steps of a `length`-step pattern must be remembered to earn `grade`.
    ///
    /// Rounded UP, so a fractional requirement is never met by falling short of it, and floored at
    /// one step for every grade above `miss`: a pattern so short that the arithmetic asks for zero
    /// steps must not hand out a grade to someone who remembered nothing. A `perfect` is exactly
    /// `length` and never less, however the rounding falls.
    static func requiredCorrect(for grade: TrainingResult, length: Int) -> Int {
        let length = max(0, length)
        guard grade != .miss else { return 0 }
        guard grade != .perfect else { return length }
        return min(length, max(1, Int((requiredShare(for: grade) * Double(length)).rounded(.up))))
    }

    /// What remembering `correct` steps of a `length`-step pattern earns.
    ///
    /// Thresholds are INCLUSIVE of the better grade — landing exactly on the number is landing in,
    /// the same way round as every other game here. Counts are integers, so every threshold is exact
    /// and a boundary test asserts ON the number rather than either side of it.
    ///
    /// A pattern with no steps is a `miss` rather than a free `perfect`: remembering all of nothing
    /// is not a round that was played.
    static func grade(correct: Int, length: Int) -> TrainingResult {
        guard length > 0 else { return .miss }
        let correct = min(max(0, correct), length)
        if correct >= requiredCorrect(for: .perfect, length: length) { return .perfect }
        if correct >= requiredCorrect(for: .great, length: length) { return .great }
        if correct >= requiredCorrect(for: .good, length: length) { return .good }
        return .miss
    }

    /// Any pad that is not `pad`. Used only to stage a wrong entry for a demo — see
    /// `stageDemoAttempt(correct:)`.
    static func wrongPad(insteadOf pad: Int) -> Int {
        (pad + 1) % padCount
    }

    // No draining timer bar here, deliberately: `TrainingMinigame.remainingFraction(at:window:)`
    // draws down a window the user is spending, and `inputTimeout` is not that — it is a backstop on
    // a round nobody answered. Counting it down would put a clock on a memory test, which is a
    // different game.

    // MARK: - Drawing constants

    /// What each pad looks like. Colour tells them apart at a glance; the symbol is what tells them
    /// apart at all — see `pad(_:)`.
    static func tint(for pad: Int) -> Color {
        [Color.red, .blue, .green, .orange][pad % padCount]
    }

    static func symbol(for pad: Int) -> String {
        ["flame.fill", "drop.fill", "leaf.fill", "bolt.fill"][pad % padCount]
    }

    static let padSize: CGFloat = 52
    static let padSpacing: CGFloat = 6
    static let padCornerRadius: CGFloat = 10
    static let dotDiameter: CGFloat = 5
}

#Preview {
    SequenceRecallGame(onFinish: { _ in })
}
