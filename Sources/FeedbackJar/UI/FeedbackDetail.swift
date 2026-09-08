#if canImport(SwiftUI)
import SwiftUI

/// The detail screen: title + content + vote pill + comments + bottom composer.
struct FJFeedbackDetail: View {
    let post: FeedbackPost
    let config: WidgetConfig
    var onBack: () -> Void
    var onVoteChange: ((Int, Bool) -> Void)?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.fjAccent) private var accent

    @State private var comments: [FeedbackComment] = []
    @State private var nextCursor: String?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var loaded = false
    @State private var error = ""

    @State private var draft = ""
    @State private var sending = false
    @State private var replyTarget: FeedbackComment?

    var body: some View {
        let palette = fjPalette(scheme, accent)
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Text("‹ Back")
                        .font(.system(size: FJFont.body))
                        .foregroundColor(palette.accent)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(post.title)
                            .font(.system(size: FJFont.body, weight: .bold))
                            .foregroundColor(palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if config.allowVotes {
                            FJVotePill(
                                postId: post.id,
                                upvotes: post.upvotes,
                                hasVoted: post.hasVoted,
                                onChange: onVoteChange
                            )
                        }
                    }

                    Text(metaLine)
                        .font(.system(size: FJFont.small))
                        .foregroundColor(palette.textDim)

                    Text(post.content)
                        .font(.system(size: FJFont.body))
                        .foregroundColor(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)

                    Rectangle().fill(palette.divider).frame(height: 0.5).padding(.vertical, 20)

                    Text("Comments")
                        .font(.system(size: FJFont.body, weight: .bold))
                        .foregroundColor(palette.text)
                        .padding(.bottom, 12)

                    if loading {
                        ProgressView().tint(palette.accent).padding(.top, 12)
                    } else if comments.isEmpty {
                        Text(error.isEmpty ? "No comments yet." : error)
                            .font(.system(size: FJFont.small))
                            .foregroundColor(error.isEmpty ? palette.textDim : palette.accent)
                            .padding(.top, 8)
                    } else {
                        FJCommentThread(
                            comments: comments,
                            onReply: config.allowComments ? { replyTarget = $0 } : nil
                        )
                        if nextCursor != nil {
                            Button(action: loadMore) {
                                if loadingMore {
                                    ProgressView().tint(palette.accent)
                                } else {
                                    Text("Load more")
                                        .font(.system(size: FJFont.small, weight: .bold))
                                        .foregroundColor(palette.accent)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 12)
                        }
                        if !error.isEmpty {
                            Text(error)
                                .font(.system(size: FJFont.small))
                                .foregroundColor(palette.accent)
                                .padding(.top, 8)
                        }
                    }
                }
                .padding(20)
                .padding(.top, -4)
            }

            if config.allowComments {
                composer(palette)
            }
        }
        .background(palette.bg.ignoresSafeArea())
        .task {
            guard !loaded else { return }
            loaded = true
            await load(reset: true)
        }
    }

    private var metaLine: String {
        var parts = [fjHumanStatus(post.status)]
        if let author = post.authorName, !author.isEmpty { parts.append(author) }
        let relative = fjRelativeTime(post.createdAt)
        if !relative.isEmpty { parts.append(relative) }
        return parts.joined(separator: " · ")
    }

    private func composer(_ palette: FJPalette) -> some View {
        VStack(spacing: 8) {
            if let target = replyTarget {
                HStack {
                    Text("Replying to \(target.authorName)")
                        .font(.system(size: FJFont.small))
                        .foregroundColor(palette.textDim)
                    Spacer()
                    Button {
                        replyTarget = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: FJFont.small, weight: .bold))
                            .foregroundColor(palette.textDim)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel reply")
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Add a comment…", text: $draft)
                    .font(.system(size: FJFont.body))
                    .foregroundColor(palette.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: fjRadius).fill(palette.field))

                Button(action: send) {
                    Group {
                        if sending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold))
                        }
                    }
                    .frame(width: 40, height: 40)
                    .foregroundColor(.white)
                    .background(RoundedRectangle(cornerRadius: fjRadius).fill(palette.accent))
                    .opacity(canSend ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send comment")
            }
        }
        .padding(12)
        .background(palette.bg)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.divider).frame(height: 0.5)
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending
    }

    @MainActor
    private func load(reset: Bool) async {
        let result = await FeedbackJar.shared.listComments(
            postId: post.id,
            limit: 50,
            cursor: reset ? nil : nextCursor
        )
        switch result {
        case .success(let page):
            comments = reset ? page.comments : comments + page.comments
            nextCursor = page.nextCursor
            error = ""
        case .failure(let err):
            error = fjMessage(err)
        }
        loading = false
    }

    @MainActor
    private func loadMore() {
        guard nextCursor != nil, !loadingMore else { return }
        loadingMore = true
        Task { @MainActor in
            await load(reset: false)
            loadingMore = false
        }
    }

    @MainActor
    private func send() {
        guard let content = fjTrimmedOrNil(draft), !sending else { return }
        sending = true
        let parentId = replyTarget?.id
        Task { @MainActor in
            let result = await FeedbackJar.shared.addComment(
                postId: post.id,
                content: content,
                parentId: parentId
            )
            sending = false
            switch result {
            case .success:
                draft = ""
                replyTarget = nil
                await load(reset: true)
            case .failure(let err):
                error = fjMessage(err)
            }
        }
    }
}
#endif
