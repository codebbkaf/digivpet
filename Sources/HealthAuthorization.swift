import Foundation
import HealthKit

/// The four HealthKit metrics the app reads — one per `EnergyType`.
///
/// Read-only, always: the app never writes to HealthKit, so every request passes an empty
/// `toShare` set. That is also why authorization here behaves the way it does — see
/// `HealthAuthorizationModel` for the consequence.
enum HealthMetric: String, CaseIterable {
    /// Steps -> Strength.
    case steps
    /// Active calories -> Vitality.
    case activeEnergy
    /// Sleep -> Spirit.
    case sleep
    /// Exercise minutes -> Stamina.
    case exercise

    var energyType: EnergyType {
        switch self {
        case .steps: return .strength
        case .activeEnergy: return .vitality
        case .sleep: return .spirit
        case .exercise: return .stamina
        }
    }

    /// The HealthKit type read for this metric.
    var objectType: HKObjectType {
        switch self {
        case .steps: return HKQuantityType(.stepCount)
        case .activeEnergy: return HKQuantityType(.activeEnergyBurned)
        case .sleep: return HKCategoryType(.sleepAnalysis)
        case .exercise: return HKQuantityType(.appleExerciseTime)
        }
    }

    /// What the onboarding screen calls this, in the user's terms rather than HealthKit's.
    var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .activeEnergy: return "Active calories"
        case .sleep: return "Sleep"
        // Not "Exercise minutes": the extra word wraps to a second line on a 41mm watch and
        // pushes the onboarding screen's Continue button off the bottom.
        case .exercise: return "Exercise"
        }
    }
}

/// The result of reading one metric.
///
/// `noData` and `unavailable` are separate from `value(0)` on purpose: a real zero is a day you
/// did not walk, where the other two mean the app was told nothing. US-012 needs that
/// distinction for its "no data" state, and US-027 needs it to tell a lazy day (no care mistake)
/// from a day HealthKit went silent (a care mistake).
enum HealthReading: Equatable {
    /// A number HealthKit actually gave us.
    case value(Double)
    /// Authorized but nothing recorded — or denied. HealthKit deliberately makes those two
    /// indistinguishable for read access, so this case covers both.
    case noData
    /// The type cannot be read at all here: HealthKit is off on this device.
    case unavailable

    /// The number energy conversion uses.
    ///
    /// Both "no data" and "unavailable" convert to zero rather than to an error, so one denied
    /// metric costs its own energy type and nothing else — a user who denies only Sleep still
    /// earns Strength, Vitality and Stamina normally.
    var energyValue: Double {
        switch self {
        case .value(let value): return value
        case .noData, .unavailable: return 0
        }
    }

    /// Whether HealthKit gave a real number, zero or not.
    var hasData: Bool {
        if case .value = self { return true }
        return false
    }
}

/// Whether the system prompt still needs to be shown for a set of metrics.
enum HealthRequestStatus: Equatable, CaseIterable {
    /// The user has not answered for at least one type yet.
    case shouldRequest
    /// The user has already answered for every type — granted or denied, HealthKit will not say.
    case answered
    /// HealthKit could not tell us. Treated like `shouldRequest`: re-requesting an answered type
    /// is a no-op, so guessing this way costs nothing and never skips the prompt.
    case unknown
}

/// The HealthKit calls `HealthAuthorizationModel` needs, behind a protocol so tests drive the
/// state machine without a real `HKHealthStore` — the Simulator has no health data, and no test
/// can answer a system prompt.
protocol HealthAuthorizing {
    var isHealthDataAvailable: Bool { get }
    func requestStatus(for metrics: [HealthMetric]) async -> HealthRequestStatus
    func requestReadAuthorization(for metrics: [HealthMetric]) async throws
}

/// The real thing: read-only authorization against `HKHealthStore`.
struct HealthKitAuthorizer: HealthAuthorizing {
    private let store = HKHealthStore()

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestStatus(for metrics: [HealthMetric]) async -> HealthRequestStatus {
        let read = Set(metrics.map(\.objectType))
        return await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: read) { status, _ in
                switch status {
                case .shouldRequest: continuation.resume(returning: .shouldRequest)
                case .unnecessary: continuation.resume(returning: .answered)
                case .unknown: continuation.resume(returning: .unknown)
                @unknown default: continuation.resume(returning: .unknown)
                }
            }
        }
    }

    func requestReadAuthorization(for metrics: [HealthMetric]) async throws {
        try await store.requestAuthorization(toShare: [], read: Set(metrics.map(\.objectType)))
    }
}

#if DEBUG
/// A stand-in for HealthKit, selected by launch argument.
///
/// It exists so the Simulator can be driven into states the real thing will not produce on
/// demand: the Simulator has no health data, `simctl privacy` has no `health` service, and
/// nothing can script an answer to a system prompt. DEBUG only — a shipping build must never be
/// able to fake an authorization outcome, and launch arguments are not reachable on a real watch.
struct StubHealthAuthorizer: HealthAuthorizing {
    enum Outcome: String, CaseIterable {
        /// The request fails, as on a restricted device.
        case denied = "-healthDenied"
        /// HealthKit is missing entirely.
        case unavailable = "-healthUnavailable"
        /// The user answered the prompt on a previous launch.
        case answered = "-healthAnswered"
    }

    let outcome: Outcome

    /// The stub a launch argument asks for, or nil to use the real HealthKit.
    static func fromLaunchArguments(
        _ arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> StubHealthAuthorizer? {
        Outcome.allCases.first { arguments.contains($0.rawValue) }.map(StubHealthAuthorizer.init)
    }

    var isHealthDataAvailable: Bool { outcome != .unavailable }

    func requestStatus(for metrics: [HealthMetric]) async -> HealthRequestStatus {
        outcome == .answered ? .answered : .shouldRequest
    }

    func requestReadAuthorization(for metrics: [HealthMetric]) async throws {
        guard outcome == .denied else { return }
        throw NSError(
            domain: HKErrorDomain,
            code: HKError.errorAuthorizationDenied.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Authorization request refused (stub)."]
        )
    }
}
#endif

/// Drives the health authorization screens: explain first, then prompt, then get out of the way.
///
/// **HealthKit never reveals whether read access was granted.** Apple's rule: "your app cannot
/// determine whether or not a user has granted permission to read data. If you are not given
/// permission, it simply appears as if there is no data of the requested type." So:
///
/// - `authorizationStatus(for:)` is NOT usable here. For a read-only type it reports
///   `.sharingDenied` even when the user granted read access — reading it would show the denial
///   screen to a user who said yes. It answers a question about WRITING, which this app never does.
/// - A completed prompt does not mean granted, so `.ready` means "the user has answered", not
///   "we have access". Denial arrives later, disguised as `HealthReading.noData` -> zero energy.
/// - `.denied` is therefore reachable only from a request that genuinely FAILED (restricted
///   device, missing entitlement) — the honest half of the picture. The other half is
///   `HealthAccessBlockedView`, which US-012 should also route to once it can see that every
///   metric reads `noData`, since that is the only shape a real denial ever takes.
@MainActor
final class HealthAuthorizationModel: ObservableObject {
    enum Phase: Equatable {
        /// Deciding what to show. Never prompts.
        case checking
        /// Onboarding, shown BEFORE the system prompt.
        case explaining
        /// The system prompt is up.
        case requesting
        /// The user has answered; the app can proceed.
        case ready
        /// The request itself failed. Explains, and offers a way out.
        case denied
        /// No HealthKit on this device at all.
        case unavailable
    }

    @Published private(set) var phase: Phase = .checking
    /// Why the request failed, shown on the blocked screen. Nil unless `phase == .denied`.
    @Published private(set) var failureDetail: String?

    private let authorizer: HealthAuthorizing
    private let metrics: [HealthMetric]

    init(authorizer: HealthAuthorizing = HealthKitAuthorizer(),
         metrics: [HealthMetric] = HealthMetric.allCases) {
        self.authorizer = authorizer
        self.metrics = metrics
    }

    /// Decides what the first screen is. Deliberately does NOT prompt: `confirmAndRequest()` is
    /// the only thing that can, and the only way to reach it is the onboarding screen's button.
    /// That is what guarantees the explainer comes first.
    func start() async {
        failureDetail = nil
        guard authorizer.isHealthDataAvailable else {
            phase = .unavailable
            return
        }
        switch await authorizer.requestStatus(for: metrics) {
        case .shouldRequest, .unknown:
            phase = .explaining
        case .answered:
            phase = .ready
        }
    }

    /// Raises the system prompt. Called when the user taps Continue, never on launch.
    func confirmAndRequest() async {
        phase = .requesting
        do {
            try await authorizer.requestReadAuthorization(for: metrics)
            // Answered, not necessarily granted — see the note on this type.
            phase = .ready
        } catch {
            failureDetail = error.localizedDescription
            phase = .denied
        }
    }
}
