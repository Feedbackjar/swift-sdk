import UIKit

/// FeedbackJar iOS SDK.
///
/// Configure once before use — typically in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`
/// or your SwiftUI `App.init`:
/// ```swift
/// FeedbackJar.configure(widgetId: "your-widget-id")
/// ```
///
/// async/await submission:
/// ```swift
/// let result = await FeedbackJar.shared.submit("Love the dark mode!")
/// result.onSuccess { response in print("Posted: \(response.postId)") }
/// ```
///
/// Callback submission (main-thread safe):
/// ```swift
/// FeedbackJar.shared.submit("Love the dark mode!") { result in
///     switch result {
///     case .success(let r): print("Posted: \(r.postId)")
///     case .failure(let e): print("Failed: \(e)")
///     }
/// }
/// ```
///
/// Name/email passed to `submit` are remembered automatically and reused on later
/// calls. Manage them directly with `setIdentity`, `getIdentity`, and `clearIdentity`.
public final class FeedbackJar: @unchecked Sendable {

    public static let shared = FeedbackJar()

    private static let nameDefaultsKey = "com.feedbackjar.sdk.identity.name"
    private static let emailDefaultsKey = "com.feedbackjar.sdk.identity.email"

    private var widgetId: String?
    private var client: ApiClient?

    private init() {}

    /// Configure the SDK. Call once before any other method.
    public static func configure(widgetId: String) {
        shared.widgetId = widgetId
        shared.client = ApiClient(appId: Bundle.main.bundleIdentifier)
    }

    /// Remember a submitter's name/email so future `submit` calls reuse them automatically.
    /// Pass `nil` for a field to leave it unchanged; use `clearIdentity()` to remove both.
    public func setIdentity(name: String? = nil, email: String? = nil) {
        let defaults = UserDefaults.standard
        if let name { defaults.set(name, forKey: Self.nameDefaultsKey) }
        if let email { defaults.set(email, forKey: Self.emailDefaultsKey) }
    }

    /// The currently remembered submitter identity, if any.
    public func getIdentity() -> FeedbackIdentity {
        let defaults = UserDefaults.standard
        return FeedbackIdentity(
            name: defaults.string(forKey: Self.nameDefaultsKey),
            email: defaults.string(forKey: Self.emailDefaultsKey)
        )
    }

    /// Forget the remembered submitter identity (e.g. on user logout).
    public func clearIdentity() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.nameDefaultsKey)
        defaults.removeObject(forKey: Self.emailDefaultsKey)
    }

    /// Submit feedback. Device metadata is collected automatically.
    /// - Parameters:
    ///   - content: The feedback text.
    ///   - email: Optional submitter email (for headless/anonymous submissions).
    ///   - name: Optional submitter name (for headless/anonymous submissions).
    public func submit(_ content: String, email: String? = nil, name: String? = nil) async -> Result<FeedbackResponse, Error> {
        guard let id = widgetId else { return .failure(FeedbackJarError.notInitialized) }
        guard let client else { return .failure(FeedbackJarError.notInitialized) }
        if email != nil || name != nil {
            setIdentity(name: name, email: email)
        }
        let identity = getIdentity()
        let metadata = await MainActor.run { MetadataCollector.collect() }
        return await client.submit(widgetId: id, content: content, email: email ?? identity.email, name: name ?? identity.name, metadata: metadata)
    }

    /// Callback variant. Safe to call from the main thread.
    public func submit(_ content: String, email: String? = nil, name: String? = nil, completion: @escaping @Sendable (Result<FeedbackResponse, Error>) -> Void) {
        Task { completion(await submit(content, email: email, name: name)) }
    }

    /// List public feedback for this widget's organization.
    ///
    /// - Parameters:
    ///   - boardId: optional — filter to a specific board
    ///   - limit: max items per page (1–50, default 20)
    ///   - cursor: pagination cursor from a previous `FeedbackListResult.nextCursor`
    public func listFeedback(
        boardId: String? = nil,
        limit: Int = 20,
        cursor: String? = nil
    ) async -> Result<FeedbackListResult, Error> {
        guard let id = widgetId else { return .failure(FeedbackJarError.notInitialized) }
        guard let client else { return .failure(FeedbackJarError.notInitialized) }
        return await client.listFeedback(widgetId: id, boardId: boardId, limit: min(max(limit, 1), 50), cursor: cursor)
    }

    /// Callback variant. Safe to call from the main thread.
    public func listFeedback(
        boardId: String? = nil,
        limit: Int = 20,
        cursor: String? = nil,
        completion: @escaping @Sendable (Result<FeedbackListResult, Error>) -> Void
    ) {
        Task { completion(await listFeedback(boardId: boardId, limit: limit, cursor: cursor)) }
    }

    /// Fetch this widget's organization config, including whether it asks submitters
    /// for their name/email ("Ask for Name" / "Ask for Email" in the dashboard).
    ///
    /// Use this to decide whether your own submission UI should show those fields —
    /// the SDK does not render any UI itself.
    public func getConfig() async -> Result<WidgetConfig, Error> {
        guard let id = widgetId else { return .failure(FeedbackJarError.notInitialized) }
        guard let client else { return .failure(FeedbackJarError.notInitialized) }
        return await client.getConfig(widgetId: id)
    }

    /// Callback variant. Safe to call from the main thread.
    public func getConfig(completion: @escaping @Sendable (Result<WidgetConfig, Error>) -> Void) {
        Task { completion(await getConfig()) }
    }
}

public enum FeedbackJarError: Error {
    case notInitialized
}
