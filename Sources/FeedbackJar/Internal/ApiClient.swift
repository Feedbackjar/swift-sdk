import Foundation

private struct SubmitRequest: Encodable {
    let content: String
    let email: String?
    let userName: String?
    let metadata: DeviceMetadata
}

private struct SubmitResponseBody: Decodable {
    let success: Bool
    let postId: String
    let title: String
    let type: String
    let boardId: String
}

private struct PostBody: Decodable {
    let id: String
    let title: String
    let content: String
    let type: String
    let status: String
    let slug: String
    let boardId: String
    let voteCount: Int
    let commentCount: Int
    let upvotes: Int
    let hasVoted: Bool?
    let authorName: String?
    let createdAt: String
    let updatedAt: String
}

private struct ListResponseBody: Decodable {
    let posts: [PostBody]
    let nextCursor: String?
}

private struct ConfigResponseBody: Decodable {
    let collectName: Bool?
    let collectEmail: Bool?
    let allowVotes: Bool?
    let allowComments: Bool?
}

private struct ErrorResponseBody: Decodable {
    let error: String?
}

private struct VoteStateBody: Decodable {
    let upvotes: Int
    let hasVoted: Bool
}

private struct CommentBody: Decodable {
    let id: String
    let content: String
    let authorName: String
    let authorRole: String?
    let isBot: Bool?
    let parentId: String?
    let createdAt: String
    let replies: [CommentBody]?
}

private struct CommentListResponseBody: Decodable {
    let comments: [CommentBody]
    let nextCursor: String?
}

private struct CreateCommentRequest: Encodable {
    let content: String
    let parentId: String?
    let name: String?
    let email: String?
}

private struct CreateCommentResponseBody: Decodable {
    let id: String
}

private struct IdentifyRequest: Encodable {
    let name: String?
    let email: String?
}

private extension CommentBody {
    func toModel() -> FeedbackComment {
        FeedbackComment(
            id: id,
            content: content,
            authorName: authorName,
            authorRole: authorRole,
            isBot: isBot ?? false,
            parentId: parentId,
            createdAt: createdAt,
            replies: (replies ?? []).map { $0.toModel() }
        )
    }
}

internal final class ApiClient: Sendable {
    private let session = URLSession.shared
    private let baseURL = URL(string: "https://api.feedbackjar.com")!
    private let decoder = JSONDecoder()
    private let appId: String?

    init(appId: String? = nil) {
        self.appId = appId
    }

    private func applyAppIdHeader(to request: inout URLRequest) {
        if let appId, !appId.isEmpty {
            request.setValue(appId, forHTTPHeaderField: "X-FeedbackJar-App-Id")
        }
    }

    /// Attach this install's anonymous id — sent on every mutating call so the
    /// server can attribute guest votes/comments and populate `hasVoted`.
    private func applyAnonIdHeader(to request: inout URLRequest) {
        request.setValue(AnonId.current, forHTTPHeaderField: "X-FeedbackJar-Anon-Id")
    }

    /// Build the error for a non-2xx response, surfacing the server's `{ "error": ... }`
    /// message verbatim when present, else falling back to the status code.
    private func error(from data: Data, status: Int) -> Error {
        if let body = try? decoder.decode(ErrorResponseBody.self, from: data),
           let message = body.error, !message.isEmpty {
            return FeedbackJarNetworkError.server(message)
        }
        return FeedbackJarNetworkError.httpError(status)
    }

    func submit(widgetId: String, content: String, email: String? = nil, name: String? = nil, metadata: DeviceMetadata) async -> Result<FeedbackResponse, Error> {
        let url = baseURL.appendingPathComponent("widget/\(widgetId)/submit")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAppIdHeader(to: &request)

        do {
            request.httpBody = try JSONEncoder().encode(SubmitRequest(content: content, email: email, userName: name, metadata: metadata))
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(FeedbackJarNetworkError.invalidResponse)
            }
            guard (200...299).contains(http.statusCode) else {
                return .failure(FeedbackJarNetworkError.httpError(http.statusCode))
            }
            let parsed = try decoder.decode(SubmitResponseBody.self, from: data)
            return .success(FeedbackResponse(
                postId: parsed.postId,
                title: parsed.title,
                type: parsed.type,
                boardId: parsed.boardId
            ))
        } catch {
            return .failure(error)
        }
    }

    func listFeedback(widgetId: String, boardId: String?, limit: Int, cursor: String?) async -> Result<FeedbackListResult, Error> {
        var components = URLComponents(url: baseURL.appendingPathComponent("widget/\(widgetId)/posts"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let boardId { queryItems.append(URLQueryItem(name: "boardId", value: boardId)) }
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = queryItems

        guard let url = components.url else { return .failure(FeedbackJarNetworkError.invalidResponse) }

        var request = URLRequest(url: url)
        applyAppIdHeader(to: &request)
        applyAnonIdHeader(to: &request)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(FeedbackJarNetworkError.invalidResponse)
            }
            guard (200...299).contains(http.statusCode) else {
                return .failure(error(from: data, status: http.statusCode))
            }
            let parsed = try decoder.decode(ListResponseBody.self, from: data)
            return .success(FeedbackListResult(
                posts: parsed.posts.map {
                    FeedbackPost(
                        id: $0.id, title: $0.title, content: $0.content,
                        type: $0.type, status: $0.status, slug: $0.slug,
                        boardId: $0.boardId, voteCount: $0.voteCount,
                        commentCount: $0.commentCount, upvotes: $0.upvotes,
                        hasVoted: $0.hasVoted ?? false,
                        authorName: $0.authorName, createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                },
                nextCursor: parsed.nextCursor
            ))
        } catch {
            return .failure(error)
        }
    }

    func getConfig(widgetId: String) async -> Result<WidgetConfig, Error> {
        let url = baseURL.appendingPathComponent("widget/\(widgetId)/config")
        var request = URLRequest(url: url)
        applyAppIdHeader(to: &request)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(FeedbackJarNetworkError.invalidResponse)
            }
            guard (200...299).contains(http.statusCode) else {
                return .failure(error(from: data, status: http.statusCode))
            }
            let parsed = try decoder.decode(ConfigResponseBody.self, from: data)
            return .success(WidgetConfig(
                collectName: parsed.collectName ?? false,
                collectEmail: parsed.collectEmail ?? false,
                allowVotes: parsed.allowVotes ?? false,
                allowComments: parsed.allowComments ?? false
            ))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Voting

    func vote(widgetId: String, postId: String) async -> Result<VoteState, Error> {
        await voteRequest(widgetId: widgetId, postId: postId, action: "vote")
    }

    func unvote(widgetId: String, postId: String) async -> Result<VoteState, Error> {
        await voteRequest(widgetId: widgetId, postId: postId, action: "unvote")
    }

    private func voteRequest(widgetId: String, postId: String, action: String) async -> Result<VoteState, Error> {
        let url = baseURL.appendingPathComponent("widget/\(widgetId)/posts/\(postId)/\(action)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyAppIdHeader(to: &request)
        applyAnonIdHeader(to: &request)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(FeedbackJarNetworkError.invalidResponse)
            }
            guard (200...299).contains(http.statusCode) else {
                return .failure(error(from: data, status: http.statusCode))
            }
            let parsed = try decoder.decode(VoteStateBody.self, from: data)
            return .success(VoteState(upvotes: parsed.upvotes, hasVoted: parsed.hasVoted))
        } catch {
            return .failure(error)
        }
    }

    func getVoteState(widgetId: String, postId: String) async -> Result<VoteState, Error> {
        let url = baseURL.appendingPathComponent("widget/\(widgetId)/posts/\(postId)/vote")
        var request = URLRequest(url: url)
        applyAppIdHeader(to: &request)
        applyAnonIdHeader(to: &request)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(FeedbackJarNetworkError.invalidResponse)
            }
            guard (200...299).contains(http.statusCode) else {
                return .failure(error(from: data, status: http.statusCode))
            }
            let parsed = try decoder.decode(VoteStateBody.self, from: data)
            return .success(VoteState(upvotes: parsed.upvotes, hasVoted: parsed.hasVoted))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Comments

    func listComments(widgetId: String, postId: String, limit: Int, cursor: String?) async -> Result<FeedbackCommentListResult, Error> {
        var components = URLComponents(url: baseURL.appendingPathComponent("widget/\(widgetId)/posts/\(postId)/comments"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = queryItems

        guard let url = components.url else { return .failure(FeedbackJarNetworkError.invalidResponse) }

        var request = URLRequest(url: url)
        applyAppIdHeader(to: &request)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(FeedbackJarNetworkError.invalidResponse)
            }
            guard (200...299).contains(http.statusCode) else {
                return .failure(error(from: data, status: http.statusCode))
            }
            let parsed = try decoder.decode(CommentListResponseBody.self, from: data)
            return .success(FeedbackCommentListResult(
                comments: parsed.comments.map { $0.toModel() },
                nextCursor: parsed.nextCursor
            ))
        } catch {
            return .failure(error)
        }
    }

    func createComment(widgetId: String, postId: String, content: String, parentId: String?, name: String?, email: String?) async -> Result<String, Error> {
        let url = baseURL.appendingPathComponent("widget/\(widgetId)/posts/\(postId)/comments")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAppIdHeader(to: &request)
        applyAnonIdHeader(to: &request)

        do {
            request.httpBody = try JSONEncoder().encode(CreateCommentRequest(content: content, parentId: parentId, name: name, email: email))
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(FeedbackJarNetworkError.invalidResponse)
            }
            guard (200...299).contains(http.statusCode) else {
                return .failure(error(from: data, status: http.statusCode))
            }
            let parsed = try decoder.decode(CreateCommentResponseBody.self, from: data)
            return .success(parsed.id)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Identify

    func identify(widgetId: String, name: String?, email: String?) async -> Result<Void, Error> {
        let url = baseURL.appendingPathComponent("widget/\(widgetId)/identify")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAppIdHeader(to: &request)
        applyAnonIdHeader(to: &request)

        do {
            request.httpBody = try JSONEncoder().encode(IdentifyRequest(name: name, email: email))
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(FeedbackJarNetworkError.invalidResponse)
            }
            guard (200...299).contains(http.statusCode) else {
                return .failure(error(from: data, status: http.statusCode))
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}

internal enum FeedbackJarNetworkError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    /// A `{ "error": "..." }` message returned verbatim by the server.
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server."
        case .httpError(let status): return "Request failed: HTTP \(status)."
        case .server(let message): return message
        }
    }
}
