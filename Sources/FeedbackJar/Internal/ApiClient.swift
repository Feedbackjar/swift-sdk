import Foundation

private struct SubmitRequest: Encodable {
    let content: String
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
    let authorName: String?
    let createdAt: String
    let updatedAt: String
}

private struct ListResponseBody: Decodable {
    let posts: [PostBody]
    let nextCursor: String?
}

internal final class ApiClient: Sendable {
    private let session = URLSession.shared
    private let baseURL = URL(string: "https://api.feedbackjar.com")!
    private let decoder = JSONDecoder()

    func submit(widgetId: String, content: String, metadata: DeviceMetadata) async -> Result<FeedbackResponse, Error> {
        let url = baseURL.appendingPathComponent("widget/\(widgetId)/submit")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(SubmitRequest(content: content, metadata: metadata))
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

        do {
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse else {
                return .failure(FeedbackJarNetworkError.invalidResponse)
            }
            guard (200...299).contains(http.statusCode) else {
                return .failure(FeedbackJarNetworkError.httpError(http.statusCode))
            }
            let parsed = try decoder.decode(ListResponseBody.self, from: data)
            return .success(FeedbackListResult(
                posts: parsed.posts.map {
                    FeedbackPost(
                        id: $0.id, title: $0.title, content: $0.content,
                        type: $0.type, status: $0.status, slug: $0.slug,
                        boardId: $0.boardId, voteCount: $0.voteCount,
                        commentCount: $0.commentCount, upvotes: $0.upvotes,
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
}

internal enum FeedbackJarNetworkError: Error {
    case invalidResponse
    case httpError(Int)
}
