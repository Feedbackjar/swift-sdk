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
    /// Whether this install's anonymous id has upvoted this post.
    public let hasVoted: Bool
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
    /// Whether guest upvoting is enabled for this project.
    public let allowVotes: Bool
    /// Whether guest commenting is enabled for this project.
    public let allowComments: Bool
}

/// Submitter identity remembered across `FeedbackJar` calls.
///
/// `userId`/`signature`/`timestamp` are set only via the **verified**
/// `setIdentity(userId:email:signature:timestamp:...)` overload — when present
/// (and not yet expired), `vote`, `addComment`, and `submit` all attach to this
/// real, server-verified user instead of the install's anonymous id.
public struct FeedbackIdentity: Sendable {
    public let name: String?
    public let email: String?
    public let userId: String?
    public let signature: String?
    /// Milliseconds since epoch — the exact value your backend signed.
    public let timestamp: Int?
    public let firstName: String?
    public let lastName: String?
    public let avatar: String?

    public init(
        name: String? = nil,
        email: String? = nil,
        userId: String? = nil,
        signature: String? = nil,
        timestamp: Int? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        avatar: String? = nil
    ) {
        self.name = name
        self.email = email
        self.userId = userId
        self.signature = signature
        self.timestamp = timestamp
        self.firstName = firstName
        self.lastName = lastName
        self.avatar = avatar
    }
}

/// Upvote state for a single post.
public struct VoteState: Sendable {
    /// Current upvote count.
    public let upvotes: Int
    /// Whether this install's anonymous id has upvoted.
    public let hasVoted: Bool
}

/// A public comment on a post. Threads are two levels deep — a root comment's
/// `replies` are its direct replies, and those replies never have replies of their own.
public struct FeedbackComment: Sendable {
    public let id: String
    public let content: String
    public let authorName: String
    /// Org role of the author when they're a team member (e.g. `owner`), else nil.
    public let authorRole: String?
    public let isBot: Bool
    public let parentId: String?
    public let createdAt: String
    public let replies: [FeedbackComment]
}

/// A page of public comments for a post.
public struct FeedbackCommentListResult: Sendable {
    public let comments: [FeedbackComment]
    /// Non-nil when more pages exist — pass it back as `cursor`.
    public let nextCursor: String?
}
