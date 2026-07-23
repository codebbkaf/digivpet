import SwiftUI

/// Copy about health data that more than one screen says, kept in one place so the screens cannot
/// drift apart. The onboarding screen promises this before the system prompt; Settings repeats it
/// afterwards, and a user who reads both must not find two different promises.
enum HealthCopy {
    /// The privacy promise. Said by `HealthOnboardingView` before the prompt and by `SettingsView`
    /// for the rest of the game's life — the app has no network code at all, so this is a fact
    /// about the build, not a policy.
    static let neverLeavesTheWatch = "Never leaves this watch."
}

/// What Settings says about health data collection (US-215).
///
/// A view of `HealthAuthorizationModel.Phase`, not a second source of truth: the phase is what the
/// gate already decided from the one `HealthAuthorizing` the app was built with, so this can only
/// ever agree with the screen the user was shown at launch.
///
/// **"Collecting" means the user has ANSWERED, not that they granted.** HealthKit deliberately
/// refuses to reveal read grants — a denial arrives later disguised as `HealthReading.noData` — so
/// the row is worded as what the app is doing (reading, and getting whatever it gets) rather than
/// as a permission the app cannot see. See the note on `HealthAuthorizationModel`.
enum HealthCollectionStatus: Equatable, CaseIterable {
    /// The app is reading health data: the user has answered the prompt.
    case collecting
    /// Nothing is being read — the prompt has not been answered, or the request failed outright.
    case notCollecting
    /// No HealthKit on this device at all. Nothing to fix.
    case unavailable
    /// The launch check has not come back yet. Only visible for the instant before it does.
    case checking

    init(phase: HealthAuthorizationModel.Phase) {
        switch phase {
        case .ready:
            self = .collecting
        // `.denied` is a request that FAILED, and `.explaining`/`.requesting` are a prompt not yet
        // answered. All three read the same to the player — nothing is coming in — and the reason
        // they differ is already the whole of the screen the gate shows for each.
        case .explaining, .requesting, .denied:
            self = .notCollecting
        case .unavailable:
            self = .unavailable
        case .checking:
            self = .checking
        }
    }

    /// The status row's headline.
    var title: String {
        switch self {
        case .collecting: return "Collecting health data"
        case .notCollecting: return "Not collecting"
        case .unavailable: return "Unavailable"
        case .checking: return "Checking…"
        }
    }

    /// One line under it, saying what that means for the Digimon rather than restating the
    /// permission. Kept short deliberately: measured on a 42mm screen, anything longer than about
    /// forty characters runs past the two lines the row allows and truncates mid-word — which is
    /// why this says "earning energy" instead of naming the four metrics the onboarding screen lists.
    var detail: String {
        switch self {
        case .collecting: return "Your Digimon is earning energy."
        case .notCollecting: return "Your Digimon can't earn energy without it."
        case .unavailable: return "This device has no Health data."
        case .checking: return "Reading the current setting."
        }
    }

    var symbolName: String {
        switch self {
        case .collecting: return "heart.fill"
        case .notCollecting: return "heart.slash"
        case .unavailable: return "exclamationmark.triangle"
        case .checking: return "ellipsis"
        }
    }

    var tint: Color {
        switch self {
        case .collecting: return .green
        case .notCollecting: return .orange
        case .unavailable, .checking: return .secondary
        }
    }
}

extension HealthAuthorizationModel {
    /// What Settings shows. A computed view of `phase`, so nothing has to be kept in step with it.
    var collectionStatus: HealthCollectionStatus { HealthCollectionStatus(phase: phase) }
}
