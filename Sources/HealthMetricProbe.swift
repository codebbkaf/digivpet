#if DEBUG
import Foundation
import HealthKit
import os

/// US-055 spike. Probes every HealthKit identifier US-061 might build an evolution criterion on,
/// and reports what HealthKit actually does with it on this watchOS.
///
/// DEBUG only, launch-argument driven, ships no user-facing feature. It exists to produce
/// `docs/health-metrics.md` and should be deleted once the evolution criteria are settled.
///
/// **Why it queries before it prompts.** The Simulator cannot grant health access — `simctl
/// privacy` has no `health` service (verified on Xcode 26.4.1), and nothing can script an answer
/// to the system sheet. But an un-prompted read is still informative, because HealthKit
/// distinguishes the two failures this spike needs to tell apart:
///
/// - `errorAuthorizationNotDetermined` (5) — a real, readable type nobody has answered for yet.
/// - `errorInvalidArgument` (3) — the type is not readable on this platform at all.
///
/// So "does this identifier exist for real on watchOS" is answerable with zero interaction, which
/// is the question US-061 actually has. Whether a type then *has data* is a separate question the
/// Simulator can never answer, and the doc records it as such.
enum HealthMetricProbe {
    /// Run the probe instead of the app. Both arguments are DEBUG-only.
    enum Mode: String {
        /// Query every candidate and log a verdict. No prompt, no interaction.
        case query = "-probeHealthMetrics"
        /// Raise the authorization sheet for every candidate, so it can be screenshotted.
        /// Blocks until the sheet is answered, which in the Simulator means forever.
        case authorize = "-probeHealthAuth"
    }

    static func mode(
        _ arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Mode? {
        arguments.compactMap(Mode.init(rawValue:)).first
    }

    /// One identifier under test.
    struct Candidate {
        let name: String
        let type: HKObjectType
        /// The four the app already has an answer for. Recorded so the log shows the contrast
        /// between "never asked" and "asked" rather than leaving it to be assumed.
        let alreadyRequested: Bool

        init(_ name: String, _ type: HKObjectType, alreadyRequested: Bool = false) {
            self.name = name
            self.type = type
            self.alreadyRequested = alreadyRequested
        }
    }

    static let candidates: [Candidate] = quantities + categories + [
        Candidate("HKWorkoutType.workoutType()", HKWorkoutType.workoutType())
    ]

    private static let quantities: [Candidate] = [
        Candidate("stepCount", HKQuantityType(.stepCount), alreadyRequested: true),
        Candidate("distanceWalkingRunning", HKQuantityType(.distanceWalkingRunning)),
        Candidate("flightsClimbed", HKQuantityType(.flightsClimbed)),
        Candidate("appleExerciseTime", HKQuantityType(.appleExerciseTime), alreadyRequested: true),
        Candidate("appleStandTime", HKQuantityType(.appleStandTime)),
        Candidate("activeEnergyBurned", HKQuantityType(.activeEnergyBurned), alreadyRequested: true),
        Candidate("basalEnergyBurned", HKQuantityType(.basalEnergyBurned)),
        Candidate("vo2Max", HKQuantityType(.vo2Max)),
        Candidate("restingHeartRate", HKQuantityType(.restingHeartRate)),
        Candidate("heartRateVariabilitySDNN", HKQuantityType(.heartRateVariabilitySDNN)),
        Candidate("respiratoryRate", HKQuantityType(.respiratoryRate)),
        Candidate("oxygenSaturation", HKQuantityType(.oxygenSaturation)),
        Candidate("distanceSwimming", HKQuantityType(.distanceSwimming)),
        Candidate("distanceCycling", HKQuantityType(.distanceCycling)),
        Candidate("dietaryWater", HKQuantityType(.dietaryWater)),
        Candidate("timeInDaylight", HKQuantityType(.timeInDaylight)),
        Candidate("physicalEffort", HKQuantityType(.physicalEffort)),
        Candidate("environmentalAudioExposure", HKQuantityType(.environmentalAudioExposure))
    ]

    private static let categories: [Candidate] = [
        Candidate("handwashingEvent", HKCategoryType(.handwashingEvent)),
        Candidate("mindfulSession", HKCategoryType(.mindfulSession)),
        Candidate("appleStandHour", HKCategoryType(.appleStandHour)),
        Candidate("toothbrushingEvent", HKCategoryType(.toothbrushingEvent)),
        Candidate("sleepAnalysis", HKCategoryType(.sleepAnalysis), alreadyRequested: true),
        Candidate("highHeartRateEvent", HKCategoryType(.highHeartRateEvent)),
        Candidate("lowCardioFitnessEvent", HKCategoryType(.lowCardioFitnessEvent)),
        Candidate("appleWalkingSteadinessEvent", HKCategoryType(.appleWalkingSteadinessEvent))
    ]

    private static let log = Logger(subsystem: "com.digivpet.DigiVPet", category: "HealthProbe")
    private static let store = HKHealthStore()

    static func run(mode: Mode) async {
        log.notice("PROBE begin mode=\(mode.rawValue, privacy: .public)")
        log.notice("PROBE healthDataAvailable=\(HKHealthStore.isHealthDataAvailable(), privacy: .public)")
        switch mode {
        case .query: await queryAll()
        case .authorize: await raiseSheet()
        }
        log.notice("PROBE end")
    }

    private static func queryAll() async {
        for candidate in candidates {
            let status = await requestStatus(for: candidate.type)
            let read = await readOne(candidate.type)
            log.notice("""
                PROBE \(candidate.name, privacy: .public) \
                asked=\(candidate.alreadyRequested, privacy: .public) \
                status=\(status, privacy: .public) \
                read=\(read, privacy: .public)
                """)
        }
    }

    /// Requests every candidate at once so the sheet's contents can be screenshotted.
    private static func raiseSheet() async {
        let read = Set(candidates.map(\.type))
        do {
            try await store.requestAuthorization(toShare: [], read: read)
            log.notice("PROBE sheet answered for \(read.count, privacy: .public) types")
        } catch {
            // The interesting failure: HealthKit rejects the whole request if ANY type in it is
            // not a valid readable type on this platform, so a throw here names the bad one.
            log.error("PROBE sheet FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func requestStatus(for type: HKObjectType) async -> String {
        await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: [type]) { status, error in
                if let error {
                    continuation.resume(returning: "ERROR(\(describe(error)))")
                    return
                }
                switch status {
                case .shouldRequest: continuation.resume(returning: "shouldRequest")
                case .unnecessary: continuation.resume(returning: "unnecessary")
                case .unknown: continuation.resume(returning: "unknown")
                @unknown default: continuation.resume(returning: "unknownDefault")
                }
            }
        }
    }

    /// Reads up to one sample from the last 30 days. The window is generous on purpose: this asks
    /// "can this be read at all", not "what is today's total".
    private static func readOne(_ type: HKObjectType) async -> String {
        guard let sampleType = type as? HKSampleType else {
            return "notASampleType"
        }
        let end = Date()
        let start = end.addingTimeInterval(-30 * 24 * 60 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(returning: "ERROR(\(describe(error)))")
                } else {
                    continuation.resume(returning: "ok(samples=\(samples?.count ?? 0))")
                }
            }
            store.execute(query)
        }
    }

    /// HKError codes are the whole point of this spike, so report the number, not just the prose.
    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == HKErrorDomain,
              let code = HKError.Code(rawValue: nsError.code) else {
            return "\(nsError.domain):\(nsError.code)"
        }
        let name: String
        switch code {
        case .errorAuthorizationDenied: name = "authorizationDenied"
        case .errorAuthorizationNotDetermined: name = "authorizationNotDetermined"
        case .errorInvalidArgument: name = "invalidArgument"
        case .errorHealthDataUnavailable: name = "healthDataUnavailable"
        case .errorHealthDataRestricted: name = "healthDataRestricted"
        case .errorDatabaseInaccessible: name = "databaseInaccessible"
        case .errorRequiredAuthorizationDenied: name = "requiredAuthorizationDenied"
        default: name = "code\(nsError.code)"
        }
        return "\(name)/\(nsError.code)"
    }
}
#endif
