import Foundation
import HealthKit
import OSLog

/// File-level rather than a `static let` on the class below, because HealthKit calls its handlers on
/// its own queue: a logger isolated to the main actor cannot be read from inside one.
private let observerLog = Logger(subsystem: "com.digivpet.DigiVPet", category: "background")

/// The real observer: an `HKObserverQuery` per metric, with background delivery enabled so watchOS
/// wakes the app when new samples land rather than only when it is opened.
///
/// A class and not a struct because THE QUERIES MUST BE RETAINED. `HKHealthStore.execute` does not
/// keep a long-running query alive on the caller's behalf, so a struct that went out of scope after
/// `startObserving` would take its observers with it and the app would simply never be woken — a
/// failure with no error and no crash, which is the kind that ships.
@MainActor
final class HealthKitUpdateObserver: HealthUpdateObserving {
    private let store = HKHealthStore()
    private var queries: [HKObserverQuery] = []

    func startObserving(_ metrics: [HealthMetric], onUpdate: @escaping () -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        for metric in metrics {
            // Only a SAMPLE type can be observed. Every metric this app reads is one, so the guard
            // is unreachable in practice — but `HealthMetric.objectType` is typed as the wider
            // `HKObjectType`, and skipping beats force-casting a type nobody can observe.
            guard let sampleType = metric.objectType as? HKSampleType else { continue }

            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completion, error in
                if let error {
                    observerLog.error("Observer for \(metric.rawValue) failed: \(String(describing: error))")
                } else {
                    Task { @MainActor in onUpdate() }
                }
                // ALWAYS called, error or not. This is HealthKit's acknowledgement handshake: a
                // background delivery that is never acknowledged is retried and then throttled, so
                // an early return here would quietly cost the app its wakes.
                completion()
            }
            store.execute(query)
            queries.append(query)

            // Hourly rather than immediate: the app has nothing to show between wakes, and asking
            // for more than the game can use is how a watch app earns a throttle.
            store.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { _, error in
                if let error {
                    observerLog.error(
                        "No background delivery for \(metric.rawValue): \(String(describing: error))"
                    )
                }
            }
        }
    }
}
