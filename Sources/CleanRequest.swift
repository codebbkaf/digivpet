import Foundation

/// A Clean tapped on the WATCH FACE, waiting for the app to apply it.
///
/// This exists because of one hard fact about the two processes: the saved game lives in the app's
/// OWN container (`GameStore.defaultStoreURL`, and the comment there says why it must stay there),
/// and the widget extension has a different container. The extension cannot open the store — not
/// "should not", cannot — so the complication's button has no way to zero `poopCount` itself.
///
/// So the button does not clean. It RECORDS that the user asked to clean, into the same app group
/// the snapshot crosses, and `MainScreenModel.applyPendingCleanRequest` picks it up on the next
/// refresh and runs the one real `clean()`. The button is a remote control for the in-app action,
/// not a second copy of it — which is what keeps the model rule in exactly one place.
///
/// What the user sees in the meantime is not deferred: the intent rewrites the published snapshot
/// so the mess disappears from the face immediately (`ComplicationSnapshot.cleaned`). Only the
/// durable game state waits.
enum CleanRequestStore {
    static let fileName = "clean-request.json"

    /// One field, but a JSON object rather than a bare date, so a later field can be added without
    /// the old file failing to decode.
    private struct Request: Codable {
        var requestedAt: Date
    }

    private static func url(in directory: URL?) -> URL? {
        directory?.appendingPathComponent(fileName)
    }

    /// Notes that the user tapped Clean at `date`.
    ///
    /// Last write wins. Two taps before the app next runs are one clean, which is also what two
    /// taps of the in-app button would be — the second finds nothing to clear.
    ///
    /// - Returns: whether it landed. A missing container is not fatal; it means the tap is lost,
    ///   and the in-app button still works.
    @discardableResult
    static func record(
        at date: Date,
        in directory: URL? = ComplicationSnapshotStore.sharedDirectory()
    ) -> Bool {
        guard let url = url(in: directory),
              let data = try? JSONEncoder().encode(Request(requestedAt: date))
        else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// When Clean was tapped on the face, or nil if it has not been since the last apply.
    static func pending(in directory: URL? = ComplicationSnapshotStore.sharedDirectory()) -> Date? {
        guard let url = url(in: directory),
              let data = try? Data(contentsOf: url),
              let request = try? JSONDecoder().decode(Request.self, from: data)
        else { return nil }
        return request.requestedAt
    }

    /// Reads the pending request and clears it in one go.
    ///
    /// Cleared BEFORE the caller acts on it, deliberately: a request left on disk because the clean
    /// that followed it failed would be retried on every refresh forever. A tap is worth one
    /// attempt.
    static func take(in directory: URL? = ComplicationSnapshotStore.sharedDirectory()) -> Date? {
        let requested = pending(in: directory)
        clear(in: directory)
        return requested
    }

    static func clear(in directory: URL? = ComplicationSnapshotStore.sharedDirectory()) {
        guard let url = url(in: directory) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
