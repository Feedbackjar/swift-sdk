#if canImport(SwiftUI)
import SwiftUI

/// Up-chevron drawn with a `Path` — no SF Symbol dependency, no asset.
private struct FJChevronUp: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// Up-chevron + count. Filled/accent when voted, hairline outline otherwise.
/// Toggles optimistically and rolls back on failure.
struct FJVotePill: View {
    let postId: String
    let upvotes: Int
    let hasVoted: Bool
    /// The authoritative count/state after a successful toggle.
    var onChange: ((Int, Bool) -> Void)?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.fjAccent) private var accent

    @State private var localUpvotes: Int
    @State private var localVoted: Bool
    @State private var busy = false

    init(postId: String, upvotes: Int, hasVoted: Bool, onChange: ((Int, Bool) -> Void)? = nil) {
        self.postId = postId
        self.upvotes = upvotes
        self.hasVoted = hasVoted
        self.onChange = onChange
        _localUpvotes = State(initialValue: upvotes)
        _localVoted = State(initialValue: hasVoted)
    }

    var body: some View {
        let palette = fjPalette(scheme, accent)
        Button(action: toggle) {
            VStack(spacing: 3) {
                FJChevronUp()
                    .stroke(
                        localVoted ? Color.white : palette.textDim,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 9, height: 6)
                Text("\(localUpvotes)")
                    .font(.system(size: FJFont.small, weight: .bold))
                    .foregroundColor(localVoted ? .white : palette.text)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(minWidth: 44)
            .background(
                RoundedRectangle(cornerRadius: fjRadius)
                    .fill(localVoted ? palette.accent : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: fjRadius)
                    .strokeBorder(localVoted ? palette.accent : palette.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("\(localVoted ? "Remove upvote" : "Upvote"), \(localUpvotes) votes")
        .onChange(of: upvotes) { new in if !busy { localUpvotes = new } }
        .onChange(of: hasVoted) { new in if !busy { localVoted = new } }
    }

    @MainActor
    private func toggle() {
        guard !busy else { return }
        let prevUpvotes = localUpvotes
        let prevVoted = localVoted

        if prevVoted {
            localUpvotes = max(0, prevUpvotes - 1)
            localVoted = false
        } else {
            localUpvotes = prevUpvotes + 1
            localVoted = true
        }
        busy = true

        Task { @MainActor in
            let result = prevVoted
                ? await FeedbackJar.shared.unvote(postId: postId)
                : await FeedbackJar.shared.vote(postId: postId)
            busy = false
            switch result {
            case .success(let state):
                localUpvotes = state.upvotes
                localVoted = state.hasVoted
                onChange?(state.upvotes, state.hasVoted)
            case .failure:
                localUpvotes = prevUpvotes
                localVoted = prevVoted
            }
        }
    }
}
#endif
