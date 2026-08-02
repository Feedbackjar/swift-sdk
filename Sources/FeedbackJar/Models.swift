public struct FeedbackResponse: Sendable {
    public let postId: String
    public let title: String
    public let type: String
    public let boardId: String
}

public struct FeedbackPost: Sendable {
    public let id: String
    public let title: String
    public let content: String
    public let type: String
    public let status: String
    public let slug: String
    public let boardId: String
    public let voteCount: Int
    public let commentCount: Int
    public let upvotes: Int
    public let authorName: String?
    public let createdAt: String
    public let updatedAt: String
}

public struct FeedbackListResult: Sendable {
    public let posts: [FeedbackPost]
    public let nextCursor: String?
}

/// Widget configuration for this organization, as set in the FeedbackJar dashboard.
public struct WidgetConfig: Sendable {
    /// Whether the org asks submitters for their name ("Ask for Name").
    public let collectName: Bool
    /// Whether the org asks submitters for their email ("Ask for Email").
    public let collectEmail: Bool
}

/// Submitter identity (name/email) remembered across `FeedbackJar.submit` calls.
public struct FeedbackIdentity: Sendable {
    public let name: String?
    public let email: String?
}
