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
    private let title: String?
    private let showNewButton: Bool
    private let showCancelButton: Bool
    private let showBackButton: Bool
    private let isPresentingNewFeedback: Binding<Bool>?
    private let isShowingDetail: Binding<Bool>?
    private let properties: (() -> [String: Any]?)?
    private let commentIdentity: (() -> (name: String?, email: String?))?
    private let resetIdentity: Binding<Bool>?
    private let openPostId: Binding<String?>?

    /// - Parameters:
    ///   - accentColor: the vote state, primary button and links. Defaults to
    ///     FeedbackJar red (`#e5484d`).
    ///   - boardId: restrict the feed to a single board.
    ///   - title: the board header's heading. Defaults to `"Feedback"`; pass
    ///     your own string to relabel it, or `nil` to hide the heading entirely
    ///     when the host already titles the surface itself (a window title, a
    ///     nav bar) and the board's own would just repeat it.
    ///   - showNewButton: whether the board's header shows a "New" button that
    ///     opens the submission screen. Defaults to `true`; set `false` when
    ///     the host drives submission itself (its own toolbar button, say) via
    ///     `isPresentingNewFeedback`.
    ///   - showCancelButton: whether the "New feedback" screen shows a Cancel
    ///     button. Defaults to `true`; set `false` when the host's own chrome
    ///     already offers a way to back out (e.g. a sheet's own close control).
    ///   - showBackButton: whether a post's detail screen shows its own "‹
    ///     Back" button. Defaults to `true`; set `false` when the host drives
    ///     it back to the list itself via `isShowingDetail`.
    ///   - isPresentingNewFeedback: an optional binding a host owns to open the
    ///     submission screen from its own button. The board flips it back to
    ///     `false` on cancel or successful send, so a host's button and the
    ///     board's own state always agree.
    ///   - isShowingDetail: an optional binding the board keeps in sync with
    ///     whether a post's detail screen is open — `true` the moment a row is
    ///     tapped, `false` again on its own Back. A host can also set it to
    ///     `false` itself (from its own Back button) to leave the detail screen.
    ///   - properties: called each time the board's own "New" screen sends
    ///     feedback, to get custom key/value pairs (e.g. `["supportId": "..."]`)
    ///     merged into the auto-collected metadata. Values should be String,
    ///     Int, Double, or Bool — nested structures aren't supported. Forwarded
    ///     verbatim to `FeedbackJar.shared.submit(_:properties:)`.
    ///   - commentIdentity: called each time a comment is sent from a post's
    ///     detail screen, to get the name/email to attach to it. Return `nil`
    ///     fields to fall back to the remembered identity (the default when
    ///     this is omitted entirely).
    ///   - resetIdentity: an optional binding a host flips to `true` to forget
    ///     the remembered submitter identity (e.g. on logout) and refresh the
    ///     board as a clean anonymous guest. The board clears
    ///     `FeedbackJar.shared`'s identity, reloads its feed, and flips the
    ///     binding back to `false`.
    ///   - openPostId: an optional binding a host sets to a post id to jump the
    ///     board straight to that post's detail screen (e.g. from a push
    ///     notification). The board clears it back to `nil` once handled.
    public init(
        accentColor: Color = Color(red: 229.0 / 255.0, green: 72.0 / 255.0, blue: 77.0 / 255.0),
        boardId: String? = nil,
        title: String? = "Feedback",
        showNewButton: Bool = true,
        showCancelButton: Bool = true,
        showBackButton: Bool = true,
        isPresentingNewFeedback: Binding<Bool>? = nil,
        isShowingDetail: Binding<Bool>? = nil,
        properties: (() -> [String: Any]?)? = nil,
        commentIdentity: (() -> (name: String?, email: String?))? = nil,
        resetIdentity: Binding<Bool>? = nil,
        openPostId: Binding<String?>? = nil
    ) {
        self.accentColor = accentColor
        self.boardId = boardId
        self.title = title
        self.showNewButton = showNewButton
        self.showCancelButton = showCancelButton
        self.showBackButton = showBackButton
        self.isPresentingNewFeedback = isPresentingNewFeedback
        self.isShowingDetail = isShowingDetail
        self.properties = properties
        self.commentIdentity = commentIdentity
        self.resetIdentity = resetIdentity
        self.openPostId = openPostId
    }

    public var body: some View {
        FJBoardScreen(
            boardId: boardId, title: title, showNewButton: showNewButton,
            showCancelButton: showCancelButton, showBackButton: showBackButton,
            isPresentingNewFeedback: isPresentingNewFeedback, isShowingDetail: isShowingDetail,
            properties: properties, commentIdentity: commentIdentity,
            resetIdentity: resetIdentity, openPostId: openPostId
        )
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
    let title: String?
    let showNewButton: Bool
    let showCancelButton: Bool
    let showBackButton: Bool
    var isPresentingNewFeedback: Binding<Bool>?
    var isShowingDetail: Binding<Bool>?
    var properties: (() -> [String: Any]?)?
    var commentIdentity: (() -> (name: String?, email: String?))?
    var resetIdentity: Binding<Bool>?
    var openPostId: Binding<String?>?

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
    /// Bumped on `resetIdentity` to force a fresh `FJNewFeedback` (fresh
    /// prefilled name/email) after the remembered identity is cleared.
    @State private var newFeedbackToken = 0

    var body: some View {
        let palette = fjPalette(scheme, accent)
        Group {
            switch route {
            case .new:
                FJNewFeedback(
                    config: config,
                    showCancelButton: showCancelButton,
                    properties: properties,
                    onDone: {
                        route = .board
                        isPresentingNewFeedback?.wrappedValue = false
                        Task { @MainActor in await load(reset: true) }
                    },
                    onCancel: {
                        route = .board
                        isPresentingNewFeedback?.wrappedValue = false
                    }
                )
                .id(newFeedbackToken)
            case .detail(let post):
                FJFeedbackDetail(
                    post: posts.first(where: { $0.id == post.id }) ?? post,
                    config: config,
                    showBackButton: showBackButton,
                    commentIdentity: commentIdentity,
                    onBack: {
                        route = .board
                        isShowingDetail?.wrappedValue = false
                    },
                    onVoteChange: { upvotes, voted in patch(post.id, upvotes: upvotes, voted: voted) },
                    onPostPress: openPost
                )
                // Fresh @State per post so a jump-link reloads the new post's
                // comments instead of keeping the previous screen's.
                .id(post.id)
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
        // The host's own button flips this; mirror it into `route` so its trigger and the
        // board's own "New" button (when both exist) land on the same screen.
        .onChange(of: isPresentingNewFeedback?.wrappedValue) { isPresenting in
            if isPresenting == true, case .board = route {
                route = .new
            } else if isPresenting == false, case .new = route {
                route = .board
            }
        }
        // A host's own Back button sets this false; mirror it into `route`. It never sets
        // this true itself — only the board opens a detail screen, by picking the post.
        .onChange(of: isShowingDetail?.wrappedValue) { isShowing in
            if isShowing == false, case .detail = route {
                route = .board
            }
        }
        // A host flips this true to log the submitter out — forget the remembered
        // identity, drop back to the board, and reload as a clean anonymous guest.
        .onChange(of: resetIdentity?.wrappedValue) { shouldReset in
            guard shouldReset == true else { return }
            FeedbackJar.shared.clearIdentity()
            newFeedbackToken += 1
            route = .board
            isPresentingNewFeedback?.wrappedValue = false
            isShowingDetail?.wrappedValue = false
            Task { @MainActor in await load(reset: true) }
            resetIdentity?.wrappedValue = false
        }
        // A host sets this to a post id to jump straight to its detail screen
        // (e.g. from a push notification); the board clears it back to nil once handled.
        .onChange(of: openPostId?.wrappedValue) { postId in
            guard let postId else { return }
            openPost(postId)
            openPostId?.wrappedValue = nil
        }
    }

    private func boardList(_ palette: FJPalette) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if title != nil || showNewButton {
                    HStack {
                        if let title {
                            Text(title)
                                .font(.system(size: FJFont.body, weight: .bold))
                                .foregroundColor(palette.text)
                        }
                        Spacer()
                        if showNewButton {
                            Button("New") { route = .new }
                                .font(.system(size: FJFont.body, weight: .bold))
                                .foregroundColor(palette.accent)
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 16)
                }

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
                            openDetail(post)
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
            openDetail(known)
            return
        }
        Task { @MainActor in
            if case .success(let post) = await FeedbackJar.shared.getPost(postId) {
                openDetail(post)
            }
        }
    }

    @MainActor
    private func openDetail(_ post: FeedbackPost) {
        route = .detail(post)
        isShowingDetail?.wrappedValue = true
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
    ///   - title: the board header's heading. `nil` hides it.
    ///   - showNewButton: whether the board's header shows its own "New" button.
    ///   - showCancelButton: whether the "New feedback" screen shows a Cancel button.
    ///   - showBackButton: whether a post's detail screen shows its own "‹ Back" button.
    ///   - properties: called on each submission to get custom metadata to attach.
    ///   - commentIdentity: called on each comment to get the name/email to attach.
    ///   - resetIdentity: a binding a host flips to `true` to forget the remembered
    ///     submitter identity and refresh the board as a clean anonymous guest.
    ///   - openPostId: a binding a host sets to a post id to jump straight to its
    ///     detail screen.
    public init(
        accentColor: Color = Color(red: 229.0 / 255.0, green: 72.0 / 255.0, blue: 77.0 / 255.0),
        boardId: String? = nil,
        title: String? = "Feedback",
        showNewButton: Bool = true,
        showCancelButton: Bool = true,
        showBackButton: Bool = true,
        properties: (() -> [String: Any]?)? = nil,
        commentIdentity: (() -> (name: String?, email: String?))? = nil,
        resetIdentity: Binding<Bool>? = nil,
        openPostId: Binding<String?>? = nil
    ) {
        super.init(
            rootView: FeedbackJarBoard(
                accentColor: accentColor, boardId: boardId, title: title,
                showNewButton: showNewButton, showCancelButton: showCancelButton,
                showBackButton: showBackButton, properties: properties,
                commentIdentity: commentIdentity, resetIdentity: resetIdentity,
                openPostId: openPostId))
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif

// MARK: - AppKit

#if canImport(AppKit)
import AppKit

/// AppKit entry point — an `NSHostingController` wrapping ``FeedbackJarBoard``.
///
/// ```swift
/// let vc = FeedbackJarViewController()
/// window.contentViewController = vc
/// ```
public final class FeedbackJarViewController: NSHostingController<FeedbackJarBoard> {
    /// - Parameters:
    ///   - accentColor: the accent colour. Defaults to FeedbackJar red (`#e5484d`).
    ///   - boardId: restrict the feed to a single board.
    ///   - title: the board header's heading. `nil` hides it.
    ///   - showNewButton: whether the board's header shows its own "New" button.
    ///   - showCancelButton: whether the "New feedback" screen shows a Cancel button.
    ///   - showBackButton: whether a post's detail screen shows its own "‹ Back" button.
    ///   - properties: called on each submission to get custom metadata to attach.
    ///   - commentIdentity: called on each comment to get the name/email to attach.
    ///   - resetIdentity: a binding a host flips to `true` to forget the remembered
    ///     submitter identity and refresh the board as a clean anonymous guest.
    ///   - openPostId: a binding a host sets to a post id to jump straight to its
    ///     detail screen.
    public init(
        accentColor: Color = Color(red: 229.0 / 255.0, green: 72.0 / 255.0, blue: 77.0 / 255.0),
        boardId: String? = nil,
        title: String? = "Feedback",
        showNewButton: Bool = true,
        showCancelButton: Bool = true,
        showBackButton: Bool = true,
        properties: (() -> [String: Any]?)? = nil,
        commentIdentity: (() -> (name: String?, email: String?))? = nil,
        resetIdentity: Binding<Bool>? = nil,
        openPostId: Binding<String?>? = nil
    ) {
        super.init(
            rootView: FeedbackJarBoard(
                accentColor: accentColor, boardId: boardId, title: title,
                showNewButton: showNewButton,
                showCancelButton: showCancelButton, showBackButton: showBackButton,
                properties: properties, commentIdentity: commentIdentity,
                resetIdentity: resetIdentity, openPostId: openPostId))
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
#endif
