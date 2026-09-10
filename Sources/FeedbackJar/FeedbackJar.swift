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
    ///
    /// When the SDK is configured, the name/email are also best-effort synced to the
    /// server against this install's anonymous id (fire-and-forget), so guest
    /// votes/comments show the right name and can be reconciled if the user later
    /// signs into the web portal with that email.
    public func setIdentity(name: String? = nil, email: String? = nil) {
        let defaults = UserDefaults.standard
        if let name { defaults.set(name, forKey: Self.nameDefaultsKey) }
        if let email { defaults.set(email, forKey: Self.emailDefaultsKey) }

        guard name != nil || email != nil, let id = widgetId, let client else { return }
        Task { _ = await client.identify(widgetId: id, name: name, email: email) }
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
    ///   - properties: Optional custom key/value pairs (e.g. `["flavor": "foss"]`) merged into
    ///     the auto-collected `app` metadata. Values should be String, Int, Double, or Bool —
    ///     nested structures aren't supported.
    public func submit(_ content: String, email: String? = nil, name: String? = nil, properties: [String: Any]? = nil) async -> Result<FeedbackResponse, Error> {
        guard let id = widgetId else { return .failure(FeedbackJarError.notInitialized) }
        guard let client else { return .failure(FeedbackJarError.notInitialized) }
        if email != nil || name != nil {
            setIdentity(name: name, email: email)
        }
        let identity = getIdentity()
        let metadata = await MainActor.run { MetadataCollector.collect(properties: properties) }
        return await client.submit(widgetId: id, content: content, email: email ?? identity.email, name: name ?? identity.name, metadata: metadata)
    }

    /// Callback variant. Safe to call from the main thread.
    public func submit(_ content: String, email: String? = nil, name: String? = nil, properties: [String: Any]? = nil, completion: @escaping @Sendable (Result<FeedbackResponse, Error>) -> Void) {
        Task { completion(await submit(content, email: email, name: name, properties: properties)) }
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

    /// Fetch a single public post by id — used to resolve `#[title](postId)`
    /// mention jump-links. Same visibility rules as `listFeedback`.
    public func getPost(_ postId: String) async -> Result<FeedbackPost, Error> {
        guard let id = widgetId, let client else { return .failure(FeedbackJarError.notInitialized) }
        return await client.getPost(widgetId: id, postId: postId)
    }

    /// Callback variant. Safe to call from the main thread.
    public func getPost(_ postId: String, completion: @escaping @Sendable (Result<FeedbackPost, Error>) -> Void) {
        Task { completion(await getPost(postId)) }
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

    // MARK: - Voting

    /// Upvote a post as this install's anonymous guest. Idempotent — voting twice
    /// is a no-op. Requires guest voting to be enabled for the project
    /// (`WidgetConfig.allowVotes`). Returns the new count and vote state.
    public func vote(postId: String) async -> Result<VoteState, Error> {
        guard let id = widgetId, let client else { return .failure(FeedbackJarError.notInitialized) }
        return await client.vote(widgetId: id, postId: postId)
    }

    /// Callback variant. Safe to call from the main thread.
    public func vote(postId: String, completion: @escaping @Sendable (Result<VoteState, Error>) -> Void) {
        Task { completion(await vote(postId: postId)) }
    }

    /// Remove this install's upvote from a post. Idempotent.
    public func unvote(postId: String) async -> Result<VoteState, Error> {
        guard let id = widgetId, let client else { return .failure(FeedbackJarError.notInitialized) }
        return await client.unvote(widgetId: id, postId: postId)
    }

    /// Callback variant. Safe to call from the main thread.
    public func unvote(postId: String, completion: @escaping @Sendable (Result<VoteState, Error>) -> Void) {
        Task { completion(await unvote(postId: postId)) }
    }

    /// Current upvote count and whether this install has voted on the post.
    public func voteState(postId: String) async -> Result<VoteState, Error> {
        guard let id = widgetId, let client else { return .failure(FeedbackJarError.notInitialized) }
        return await client.getVoteState(widgetId: id, postId: postId)
    }

    /// Callback variant. Safe to call from the main thread.
    public func voteState(postId: String, completion: @escaping @Sendable (Result<VoteState, Error>) -> Void) {
        Task { completion(await voteState(postId: postId)) }
    }

    // MARK: - Comments

    /// List public comments for a post (two-level threads). Anonymous — no identity required.
    ///
    /// - Parameters:
    ///   - postId: the post to read comments for
    ///   - limit: max root comments per page (1–50, default 20)
    ///   - cursor: pagination cursor from a previous `FeedbackCommentListResult.nextCursor`
    public func listComments(
        postId: String,
        limit: Int = 20,
        cursor: String? = nil
    ) async -> Result<FeedbackCommentListResult, Error> {
        guard let id = widgetId, let client else { return .failure(FeedbackJarError.notInitialized) }
        return await client.listComments(widgetId: id, postId: postId, limit: min(max(limit, 1), 50), cursor: cursor)
    }

    /// Callback variant. Safe to call from the main thread.
    public func listComments(
        postId: String,
        limit: Int = 20,
        cursor: String? = nil,
        completion: @escaping @Sendable (Result<FeedbackCommentListResult, Error>) -> Void
    ) {
        Task { completion(await listComments(postId: postId, limit: limit, cursor: cursor)) }
    }

    /// Add a public comment (or reply, via `parentId`) as this install's anonymous
    /// guest. `name`/`email` fall back to the remembered identity; `email` is used
    /// only for reply notifications and is never auto-linked to a real account.
    /// Requires guest comments to be enabled (`WidgetConfig.allowComments`).
    /// Returns the new comment's id.
    ///
    /// - Parameters:
    ///   - postId: the post to comment on
    ///   - content: the comment text (≤ 20000 chars)
    ///   - parentId: the root comment to reply to, or nil for a top-level comment
    ///   - name: submitter name — defaults to the remembered identity
    ///   - email: submitter email — defaults to the remembered identity
    public func addComment(
        postId: String,
        content: String,
        parentId: String? = nil,
        name: String? = nil,
        email: String? = nil
    ) async -> Result<String, Error> {
        guard let id = widgetId, let client else { return .failure(FeedbackJarError.notInitialized) }
        let identity = getIdentity()
        return await client.createComment(
            widgetId: id,
            postId: postId,
            content: content,
            parentId: parentId,
            name: name ?? identity.name,
            email: email ?? identity.email
        )
    }

    /// Callback variant. Safe to call from the main thread.
    public func addComment(
        postId: String,
        content: String,
        parentId: String? = nil,
        name: String? = nil,
        email: String? = nil,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        Task { completion(await addComment(postId: postId, content: content, parentId: parentId, name: name, email: email)) }
    }
}

public enum FeedbackJarError: Error {
    case notInitialized
}
