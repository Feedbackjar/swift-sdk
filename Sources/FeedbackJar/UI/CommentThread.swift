#if canImport(SwiftUI)
import SwiftUI

/// One comment row. Replies are indented one step under a hairline rule.
private struct FJCommentRow: View {
    let comment: FeedbackComment
    let indented: Bool
    let onReply: (() -> Void)?
    var onPostPress: ((String) -> Void)?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.fjAccent) private var accent

    var body: some View {
        let palette = fjPalette(scheme, accent)
        let content = VStack(alignment: .leading, spacing: 4) {
            metaLine(palette)
            FJRichText(comment.content, onPostPress: onPostPress)
            if let onReply {
                Button("Reply", action: onReply)
                    .font(.system(size: FJFont.small, weight: .bold))
                    .foregroundColor(palette.accent)
                    .buttonStyle(.plain)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if indented {
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(palette.divider).frame(width: 1)
                content
            }
            .padding(.leading, 16)
        } else {
            content
        }
    }

    private func metaLine(_ palette: FJPalette) -> Text {
        var line = Text(comment.authorName)
            .font(.system(size: FJFont.small, weight: .bold))
            .foregroundColor(palette.text)
        if comment.authorRole != nil {
            line = line + Text("  TEAM")
                .font(.system(size: FJFont.small - 1, weight: .bold))
                .foregroundColor(palette.accent)
        }
        line = line + Text("  \(fjRelativeTime(comment.createdAt))")
            .font(.system(size: FJFont.small))
            .foregroundColor(palette.textDim)
        return line
    }
}

/// Two-level thread: root comments, each with its direct replies indented.
struct FJCommentThread: View {
    let comments: [FeedbackComment]
    /// Non-nil enables a "Reply" action on root comments.
    var onReply: ((FeedbackComment) -> Void)?
    /// Open a post referenced by a `#[…]` mention in a comment.
    var onPostPress: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(comments, id: \.id) { comment in
                VStack(alignment: .leading, spacing: 14) {
                    FJCommentRow(
                        comment: comment,
                        indented: false,
                        onReply: onReply.map { handler in { handler(comment) } },
                        onPostPress: onPostPress
                    )
                    ForEach(comment.replies, id: \.id) { reply in
                        FJCommentRow(
                            comment: reply,
                            indented: true,
                            onReply: nil,
                            onPostPress: onPostPress
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
