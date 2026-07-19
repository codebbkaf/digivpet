import Foundation
import OSLog
#if canImport(UserNotifications)
import UserNotifications
#endif

/// The three things the game will interrupt a user for.
///
/// The raw value is the persisted spelling — it is half of the `UserDefaults` key each toggle is
/// saved under — so renaming a case silently resets that toggle to its default. Change
/// `displayName` instead if the wording needs to shift.
enum NotificationKind: String, CaseIterable, Identifiable {
    /// The Digimon became something new. Covers hatching too: `MainScreenModel.advance` is the one
    /// path both take, and both are the same "you are now something new" moment.
    case evolution
    /// The Digimon has just fallen ill. Fires on the TRANSITION, not on being ill — a Digimon left
    /// sick for a day is not worth three identical notifications.
    case sickness
    /// Twenty-four hours of the illness left before it kills. The last chance to act.
    case deathWarning
    /// The screen has filled with mess. Fires when it FILLS, not while it is full — see
    /// `GameState.claimPoopNotification`.
    case poop

    var id: String { rawValue }

    /// What the settings screen calls this toggle.
    var displayName: String {
        switch self {
        case .evolution: return "Evolution"
        case .sickness: return "Sickness"
        case .deathWarning: return "Death Warning"
        case .poop: return "Mess"
        }
    }

    /// The one line under the toggle saying what turning it off costs.
    var settingsDetail: String {
        switch self {
        // Kept to roughly two short lines: a 41mm row truncates anything longer, and a detail
        // ending in "…" says less than no detail at all.
        case .evolution: return "Becoming something new."
        case .sickness: return "When neglect makes it ill."
        case .deathWarning: return "24 hours before it dies."
        case .poop: return "When the screen needs cleaning."
        }
    }

    /// Whether this kind is still delivered while the Digimon is in its sleep window.
    ///
    /// FALSE for everything but the death warning, per AC4. The Digimon's sleep window is the
    /// user's own — it is inferred from when they actually slept (US-026) — so a notification sent
    /// inside it is a notification sent at 3am. The death warning is the one exception because
    /// holding it until morning can cost the user the Digimon: the warning already IS the last
    /// 24 hours, and a night is a third of them.
    var firesWhileAsleep: Bool { self == .deathWarning }

    var title: String {
        switch self {
        case .evolution: return "Digivolution!"
        case .sickness: return "Your Digimon is sick"
        case .deathWarning: return "Your Digimon is dying"
        case .poop: return "Time to clean up"
        }
    }
}

/// One notification, decided but not yet handed to the system.
///
/// A value rather than a `UNNotificationRequest` so the rules can be tested without the
/// notification framework, and so a test can assert on what WOULD have been shown.
struct PetNotification: Equatable {
    let kind: NotificationKind
    let title: String
    let body: String
}

/// Whether each kind of notification is switched on. Default ON, per AC3.
///
/// Backed by `UserDefaults` rather than by `GameState`, and the difference is deliberate: this is a
/// preference about the person, not a fact about the Digimon, so it must survive a death and a
/// rebirth. `ObservableObject` so the settings screen's toggles redraw off it.
@MainActor
final class NotificationSettings: ObservableObject {
    private let defaults: UserDefaults

    /// - Parameter defaults: injected so a test gets its own suite rather than mutating the
    ///   simulator's real preferences, which would leak between test methods.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The key one kind's toggle is saved under. Namespaced, because `.standard` is shared with
    /// everything else the app might ever store.
    private static func key(for kind: NotificationKind) -> String {
        "notifications.\(kind.rawValue).enabled"
    }

    /// Whether `kind` will be delivered.
    ///
    /// Reads through `object(forKey:)` rather than `bool(forKey:)` because the latter returns
    /// `false` for a key that was never written — which would make every notification default OFF,
    /// the exact opposite of AC3, and would do it silently on a fresh install.
    func isEnabled(_ kind: NotificationKind) -> Bool {
        defaults.object(forKey: Self.key(for: kind)) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool, for kind: NotificationKind) {
        objectWillChange.send()
        defaults.set(enabled, forKey: Self.key(for: kind))
    }
}

/// Where a decided notification actually goes.
///
/// A protocol so the rules above can be driven in a test without `UNUserNotificationCenter`, which
/// needs an authorization the Simulator will not grant unattended and delivers asynchronously
/// through the system.
@MainActor
protocol PetNotificationDelivering: AnyObject {
    func deliver(_ notification: PetNotification)
    /// Asked once, at `MainScreenModel.start()`. Defaulted to nothing, because a test double has
    /// nobody to ask.
    func requestAuthorization()
    /// Withdraws a notification of `kind` that has already gone out, because the thing it asked for
    /// has been done. Only the poop notice uses this — a sickness or a death warning describes a
    /// moment that HAPPENED and stays true after the fact, but "there is a mess" stops being true
    /// the instant the user cleans, and a notice still sitting on the wrist telling them to do
    /// something they have already done is worse than no notice at all.
    func cancel(_ kind: NotificationKind)
}

extension PetNotificationDelivering {
    func requestAuthorization() {}
}

/// Delivers through `UNUserNotificationCenter`, immediately (a nil trigger).
///
/// Immediate rather than scheduled ahead, because every one of these is decided by a rule that has
/// just run: the game does not know at 09:00 that it will be ill at 14:00, so there is nothing to
/// schedule. `requestAuthorization` is fired once at start — an unauthorized `add` fails silently,
/// so the ask has to precede the first send rather than accompany it.
@MainActor
final class UserNotificationDeliverer: PetNotificationDelivering {
    private static let log = Logger(subsystem: "com.digivpet.DigiVPet", category: "notifications")

    func requestAuthorization() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Self.log.error("Notification authorization failed: \(String(describing: error))")
            } else {
                Self.log.info("Notification authorization granted: \(granted)")
            }
        }
        #endif
    }

    func deliver(_ notification: PetNotification) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        // The kind as the identifier, so a second notification of the same kind replaces the first
        // rather than stacking — a user who has not looked at their watch all day should find one
        // sickness notice, not the same one twice.
        let request = UNNotificationRequest(identifier: notification.kind.rawValue,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.log.error("Could not post \(notification.kind.rawValue): \(String(describing: error))")
            }
        }
        #endif
    }

    /// BOTH lists, and both are needed. `deliver` uses a nil trigger, so a notice is normally
    /// already delivered rather than pending by the time anything cancels it — but a notice posted
    /// in the same instant may not have left the pending list yet, and removing only the one it
    /// happens to be in leaves the other behind.
    func cancel(_ kind: NotificationKind) {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [kind.rawValue])
        center.removeDeliveredNotifications(withIdentifiers: [kind.rawValue])
        #endif
    }
}

/// Decides whether a notification goes out, and sends it if it does.
///
/// The two gates are the whole of the rule: the user's toggle (AC3), and the sleep window (AC4).
/// Kept separate from `MainScreenModel` so the decision can be tested without a store, a graph or
/// a health source — and so `sent` can record what a real delivery would have been.
@MainActor
final class NotificationDispatcher {
    private let settings: NotificationSettings
    private let deliverer: PetNotificationDelivering

    init(settings: NotificationSettings, deliverer: PetNotificationDelivering) {
        self.settings = settings
        self.deliverer = deliverer
    }

    /// Asks for permission to notify at all. Separate from the toggles: the toggles say what the
    /// user WANTS, this asks whether the system will let the app deliver it.
    func requestAuthorization() {
        deliverer.requestAuthorization()
    }

    /// Sends `kind` unless a toggle or the sleep window stops it.
    ///
    /// A suppressed notification is DROPPED, not queued for the morning: by the time the Digimon
    /// wakes, "your Digimon evolved" is news the user will have seen on the screen already, and a
    /// queue would deliver a burst of them at 07:00.
    ///
    /// - Returns: whether it was delivered, so a caller can log it and a test can assert on it.
    @discardableResult
    func send(_ kind: NotificationKind, body: String, isAsleep: Bool) -> Bool {
        guard settings.isEnabled(kind) else { return false }
        guard !isAsleep || kind.firesWhileAsleep else { return false }
        deliverer.deliver(PetNotification(kind: kind, title: kind.title, body: body))
        return true
    }

    /// Withdraws an already-sent `kind`.
    ///
    /// Deliberately NOT gated on the toggle. The toggle says whether the user wants to be
    /// interrupted, and a user who switches the mess notice off while one is already on their wrist
    /// wants it gone, not left there for the one path that could remove it to be switched off with
    /// it. Removing what was never posted is a no-op at the system level anyway.
    func cancel(_ kind: NotificationKind) {
        deliverer.cancel(kind)
    }
}
