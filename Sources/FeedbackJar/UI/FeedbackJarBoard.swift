#if canImport(SwiftUI)
import SwiftUI

/// A complete, drop-in feedback board: list + upvote + detail + comments +
/// submission. Built only on SwiftUI — a system framework, not a dependency.
///
/// ```swift
/// import FeedbackJar
/// import SwiftUI
///
/// FeedbackJarBoard()
/// FeedbackJarBoard(accentColor: .blue, boardId: "board_123")
/// ```
///
/// Configure the SDK once first: `FeedbackJar.configure(widgetId:)`.
public struct FeedbackJarBoard: View {
    private let accentColor: Color
    private let boardId: String?

    /// - Parameters:
    ///   - accentColor: the vote state, primary button and links. Defaults to
    ///     FeedbackJar red (`#e5484d`).
    ///   - boardId: restrict the feed to a single board.
    public init(
        accentColor: Color = Color(red: 229.0 / 255.0, green: 72.0 / 255.0, blue: 77.0 / 255.0),
        boardId: String? = nil
    ) {
        self.accentColor = accentColor
        self.boardId = boardId
    }

    public var body: some View {
        FJBoardScreen(boardId: boardId)
            .environment(\.fjAccent, accentColor)
    }
}

// MARK: - Internal screen machine (board -> detail -> new)

private enum FJRoute {
    case board
    case detail(FeedbackPost)
    case new
}

private struct FJBoardScreen: View {
    let boardId: String?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.fjAccent) private var accent

    @State private var route: FJRoute = .board
    @State private var config = WidgetConfig(
        collectName: false, collectEmail: false, allowVotes: false, allowComments: false
    )
    @State private var posts: [FeedbackPost] = []
    @State private var cursor: String?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var loaded = false
    @State private var error = ""

    var body: some View {
        let palette = fjPalette(scheme, accent)
        Group {
            switch route {
            case .new:
                FJNewFeedback(
                    config: config,
                    onDone: {
                        route = .board
                        Task { @MainActor in await load(reset: true) }
                    },
                    onCancel: { route = .board }
                )
            case .detail(let post):
                FJFeedbackDetail(
                    post: posts.first(where: { $0.id == post.id }) ?? post,
                    config: config,
                    onBack: { route = .board },
                    onVoteChange: { upvotes, voted in patch(post.id, upvotes: upvotes, voted: voted) },
                    onPostPress: openPost
                )
            case .board:
                boardList(palette)
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            if case .success(let value) = await FeedbackJar.shared.getConfig() {
                config = value
            }
            await load(reset: true)
            loading = false
        }
    }

    private func boardList(_ palette: FJPalette) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack {
                    Text("Feedback")
                        .font(.system(size: FJFont.body, weight: .bold))
                        .foregroundColor(palette.text)
                    Spacer()
                    Button("New") { route = .new }
                        .font(.system(size: FJFont.body, weight: .bold))
                        .foregroundColor(palette.accent)
                        .buttonStyle(.plain)
                }
                .padding(.vertical, 16)

                if loading {
                    ProgressView().tint(palette.accent).padding(.top, 40)
                } else if posts.isEmpty {
                    Text(error.isEmpty ? "No feedback yet." : error)
                        .font(.system(size: FJFont.small))
                        .foregroundColor(error.isEmpty ? palette.textDim : palette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ForEach(posts, id: \.id) { post in
                        Button {
                            route = .detail(post)
                        } label: {
                            row(post, palette)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if post.id == posts.last?.id { loadMore() }
                        }
                        Rectangle().fill(palette.divider).frame(height: 0.5)
                    }
                    if loadingMore {
                        ProgressView().tint(palette.accent).padding(16)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .background(palette.bg.ignoresSafeArea())
        .refreshable { await load(reset: true) }
    }

    private func row(_ post: FeedbackPost, _ palette: FJPalette) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title)
                    .font(.system(size: FJFont.body, weight: .bold))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                Text(fjPlainText(post.content))
                    .font(.system(size: FJFont.body))
                    .foregroundColor(palette.textDim)
                    .lineLimit(2)
                Text("\(fjHumanStatus(post.status)) · \(post.commentCount) comments")
                    .font(.system(size: FJFont.small))
                    .foregroundColor(palette.textDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if config.allowVotes {
                FJVotePill(
                    postId: post.id,
                    upvotes: post.upvotes,
                    hasVoted: post.hasVoted,
                    onChange: { upvotes, voted in patch(post.id, upvotes: upvotes, voted: voted) }
                )
            }
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    // MARK: Data

    @MainActor
    private func load(reset: Bool) async {
        let result = await FeedbackJar.shared.listFeedback(
            boardId: boardId,
            limit: 20,
            cursor: reset ? nil : cursor
        )
        switch result {
        case .success(let page):
            error = ""
            posts = reset ? page.posts : posts + page.posts
            cursor = page.nextCursor
        case .failure(let err):
            error = fjMessage(err)
        }
    }

    /// Jump to a post referenced by a `#[title](postId)` mention — use the
    /// loaded copy if we have it, otherwise fetch it.
    @MainActor
    private func openPost(_ postId: String) {
        if let known = posts.first(where: { $0.id == postId }) {
            route = .detail(known)
            return
        }
        Task { @MainActor in
            if case .success(let post) = await FeedbackJar.shared.getPost(postId) {
                route = .detail(post)
            }
        }
    }

    @MainActor
    private func loadMore() {
        guard cursor != nil, !loadingMore, !loading else { return }
        loadingMore = true
        Task { @MainActor in
            await load(reset: false)
            loadingMore = false
        }
    }

    @MainActor
    private func patch(_ id: String, upvotes: Int, voted: Bool) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        let existing = posts[index]
        posts[index] = FeedbackPost(
            id: existing.id,
            title: existing.title,
            content: existing.content,
            type: existing.type,
            status: existing.status,
            slug: existing.slug,
            boardId: existing.boardId,
            voteCount: existing.voteCount,
            commentCount: existing.commentCount,
            upvotes: upvotes,
            hasVoted: voted,
            authorName: existing.authorName,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt
        )
    }
}

// MARK: - UIKit

#if canImport(UIKit)
import UIKit

/// UIKit entry point — a `UIHostingController` wrapping ``FeedbackJarBoard``.
///
/// ```swift
/// let vc = FeedbackJarViewController()
/// navigationController?.pushViewController(vc, animated: true)
/// ```
public final class FeedbackJarViewController: UIHostingController<FeedbackJarBoard> {
    /// - Parameters:
    ///   - accentColor: the accent colour. Defaults to FeedbackJar red (`#e5484d`).
    ///   - boardId: restrict the feed to a single board.
    public init(
        accentColor: Color = Color(red: 229.0 / 255.0, green: 72.0 / 255.0, blue: 77.0 / 255.0),
        boardId: String? = nil
    ) {
        super.init(rootView: FeedbackJarBoard(accentColor: accentColor, boardId: boardId))
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
#endif
