import AppIntents
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Everything the face's Clean button does, with no `AppIntent` around it.
///
/// Split out for one reason: `AppIntent.perform()` takes no arguments, so an intent that reached
/// straight for the real app group and the real notification centre could not be run in a test at
/// all. This can, against a temp directory and a spy.
///
/// Note what is NOT here: any rule about poop. Nothing decides how much mess there is, when it
/// accrues or what cleaning costs — that all stays in `PoopClock` and `MainScreenModel.clean()`,
/// which this asks for by way of `CleanRequestStore`.
enum ComplicationCleanRequest {
    /// Records the tap, withdraws the mess notice, and updates what the face is drawing.
    ///
    /// - Parameter cancelNotice: how the "time to clean up" notification is withdrawn. Injected so
    ///   a test can observe it; the default is the same `UserNotificationDeliverer` the app cleans
    ///   through, so this is not a second implementation of cancelling.
    /// - Returns: whether the request was recorded. False means no app group container, in which
    ///   case nothing else is attempted either — a face that cannot record the tap must not go on
    ///   to draw the mess as gone.
    @MainActor
    @discardableResult
    static func record(
        now: Date = Date(),
        in directory: URL? = ComplicationSnapshotStore.sharedDirectory(),
        // `@MainActor` on the closure and not just on `record`: a default argument is evaluated in
        // its own nonisolated context, so an unannotated one cannot touch the main-actor deliverer.
        cancelNotice: @MainActor () -> Void = { UserNotificationDeliverer().cancel(.poop) }
    ) -> Bool {
        guard CleanRequestStore.record(at: now, in: directory) else { return false }

        // Immediately, not when the app next wakes. `clean()` cancels this too when it finally
        // runs, but a user who has just cleaned from the face should not be left with a
        // notification on their wrist telling them to go and do it — possibly for hours, since
        // nothing guarantees when the app runs next.
        cancelNotice()

        // Optimism, and strictly about the DRAWING. The durable count is still whatever the store
        // says until the app applies the request; this is so the face stops showing a mess the user
        // has already dealt with, which is the difference between a button that feels broken and
        // one that does not.
        if let snapshot = ComplicationSnapshotStore.read(from: directory) {
            ComplicationSnapshotStore.write(snapshot.cleaned(), to: directory)
        }
        return true
    }
}

/// The Clean button on the watch face (US-050).
///
/// `openAppWhenRun` is false and that is the entire point of the story: cleaning up is a two-second
/// errand, and making it launch an app would cost more than the mess does.
struct CleanPoopIntent: AppIntent {
    static var title: LocalizedStringResource = "Clean"
    static var description = IntentDescription("Clears the mess around your Digimon.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ComplicationCleanRequest.record()
        // WidgetKit reloads after an interactive intent on its own, but only for the widget that
        // was tapped. Asking explicitly is what makes every family agree — and it is what the
        // `-complicationDemo` screen, which is not a widget at all, needs to redraw.
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return .result()
    }
}
