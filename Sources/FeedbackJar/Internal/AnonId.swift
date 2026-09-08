import Foundation

/// A stable per-install anonymous id, persisted in `UserDefaults`.
///
/// Used to attribute guest votes/comments to the same install. Not a device id —
/// a fresh random `UUID` generated once on first use, reset on reinstall / clear-data.
/// The server HMACs it before storage, so it only needs to be unique, not unguessable.
/// Never derived from `identifierForVendor` or any device identifier.
internal enum AnonId {

    private static let defaultsKey = "com.feedbackjar.sdk.anonId"

    private static let lock = NSLock()
    private static var cached: String?

    /// The current install's anonymous id, generating and persisting one on first use.
    static var current: String {
        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }

        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            cached = existing
            return existing
        }

        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: defaultsKey)
        cached = fresh
        return fresh
    }
}
