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
public final class FeedbackJar: @unchecked Sendable {

    public static let shared = FeedbackJar()

    private var widgetId: String?
    private let client = ApiClient()

    private init() {}

    /// Configure the SDK. Call once before any other method.
    public static func configure(widgetId: String) {
        shared.widgetId = widgetId
    }

    /// Submit anonymous feedback. Device metadata is collected automatically.
    public func submit(_ content: String) async -> Result<FeedbackResponse, Error> {
        guard let id = widgetId else { return .failure(FeedbackJarError.notInitialized) }
        let metadata = await MainActor.run { MetadataCollector.collect() }
        return await client.submit(widgetId: id, content: content, metadata: metadata)
    }

    /// Callback variant. Safe to call from the main thread.
    public func submit(_ content: String, completion: @escaping @Sendable (Result<FeedbackResponse, Error>) -> Void) {
        Task { completion(await submit(content)) }
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
}

public enum FeedbackJarError: Error {
    case notInitialized
}
