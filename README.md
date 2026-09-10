# FeedbackJar iOS SDK

A lightweight iOS SDK for collecting user feedback. Drop in the prebuilt `FeedbackJarBoard` UI, or build your own form — the SDK handles submission (enriched with device metadata), fetching the public feedback list, and guest upvoting and commenting.

- **Min iOS:** 15.0
- **Package:** Swift Package Manager
- **License:** MIT

## Installation

In Xcode: **File → Add Package Dependencies**, enter the repository URL, and add `FeedbackJar` to your target.

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/feedbackjar/swift-sdk", from: "1.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: ["FeedbackJar"]),
]
```

## Setup

Configure once before use — typically in `AppDelegate` or your SwiftUI `App.init`. You need your **widget ID** from the FeedbackJar dashboard.

```swift
import FeedbackJar

@main
struct MyApp: App {
    init() {
        FeedbackJar.configure(widgetId: "your-widget-id")
    }
}
```

## Prebuilt UI

Don't want to build a form? Drop in `FeedbackJarBoard` — a complete feedback board
with list, upvoting, detail view, comment threads, and a submission screen. It is
part of the `FeedbackJar` product and adds **no dependency** (SwiftUI is a system
framework). Configure the SDK first, then:

```swift
import FeedbackJar
import SwiftUI

struct FeedbackTab: View {
    var body: some View {
        FeedbackJarBoard()
    }
}
```

### Accent colour

One colour drives the vote state, the primary button, and links. It defaults to
FeedbackJar red (`#e5484d`); override it and, optionally, restrict the feed to one
board:

```swift
FeedbackJarBoard(
    accentColor: Color(red: 0.11, green: 0.42, blue: 0.92),
    boardId: "board_123"
)
```

### UIKit

Use the `UIHostingController` subclass:

```swift
let vc = FeedbackJarViewController()                 // or (accentColor:boardId:)
navigationController?.pushViewController(vc, animated: true)
```

The board reads `getConfig()` on appear: it hides vote pills when guest voting is
off, hides the comment composer when guest commenting is off, and shows the
name/email fields on the submission screen only when the org asks for them
(prefilled from — and saved back to — the remembered identity). Every call goes
through the SDK's `Result` type, so the UI never throws; failures show an inline
message with the server's text and a retry where it makes sense. It follows the
system light/dark setting.

## Submitting feedback

Submissions can be anonymous, or include a submitter name/email if you collect them in your own form. Each submission automatically carries device metadata (iOS version, device model, screen size, app version, locale).

### async/await (recommended)

```swift
let result = await FeedbackJar.shared.submit(userText)
switch result {
case .success(let response):
    print("Submitted: \(response.postId) (\(response.type))")
case .failure(let error):
    print("Failed: \(error)")
}
```

### Callback (no async context needed)

Safe to call from the main thread — the network call runs off the main thread.

```swift
FeedbackJar.shared.submit(userText) { result in
    switch result {
    case .success(let response): // show success state
    case .failure(let error):    // show error state
    }
}
```

> Note: the server applies rate limiting (5 submissions per 15 minutes per IP). Handle the failure case in your UI.

## Custom properties

Attach your own key/value context to a submission — merged into the auto-collected `app` metadata (alongside `bundleId`, `version`, `build`). Values should be `String`, `Int`, `Double`, or `Bool`; nested structures aren't supported.

```swift
let result = await FeedbackJar.shared.submit(
    userText,
    properties: ["flavor": "foss", "plan": "pro"]
)
```

## Checking widget config

The organization's dashboard settings control what your UI should show. The SDK doesn't render any UI itself, so read this first:

```swift
let config = await FeedbackJar.shared.getConfig()
if case .success(let value) = config {
    showNameField  = value.collectName    // "Ask for Name"
    showEmailField = value.collectEmail   // "Ask for Email"
    showVoteButton = value.allowVotes     // guest upvoting enabled
    showComments   = value.allowComments  // guest commenting enabled
}
```

## Remembering submitter identity

Name/email passed to `submit` are automatically remembered and reused on later calls, so you only need to ask once. Manage this directly with `setIdentity` / `getIdentity` / `clearIdentity`:

```swift
FeedbackJar.shared.setIdentity(name: "Ada Lovelace", email: "ada@example.com")

let identity = FeedbackJar.shared.getIdentity()
print(identity.name ?? "")

// e.g. on logout
FeedbackJar.shared.clearIdentity()
```

## Listing feedback

Fetch the public feedback feed for your organization. Supports pagination via a cursor.

### async/await

```swift
let result = await FeedbackJar.shared.listFeedback(limit: 20)
if case .success(let page) = result {
    for post in page.posts {
        print("\(post.title) — \(post.upvotes) upvotes, \(post.status)")
    }
    // page.nextCursor is non-nil when more pages exist
}
```

### Pagination

```swift
var cursor: String? = nil

func loadNextPage() async {
    let result = await FeedbackJar.shared.listFeedback(limit: 20, cursor: cursor)
    if case .success(let page) = result {
        render(page.posts)
        cursor = page.nextCursor
    }
}
```

### Callback

```swift
FeedbackJar.shared.listFeedback(limit: 20) { result in
    if case .success(let page) = result { /* ... */ }
}
```

## Voting

Each install gets a random anonymous id (persisted in `UserDefaults`, reset on reinstall — never a device id). It's sent automatically on every vote, comment, and `listFeedback` call, so `FeedbackPost.hasVoted` and `VoteState.hasVoted` reflect this install.

Voting requires guest voting to be enabled for the project (`WidgetConfig.allowVotes`). All calls are idempotent.

```swift
// Upvote
let result = await FeedbackJar.shared.vote(postId: post.id)
if case .success(let state) = result {
    print("\(state.upvotes) upvotes, voted: \(state.hasVoted)")
}

// Remove the upvote
_ = await FeedbackJar.shared.unvote(postId: post.id)

// Read current state
let state = await FeedbackJar.shared.voteState(postId: post.id)
```

Callback variants exist for all three (`vote(postId:completion:)`, etc.).

> Rate limits: 60 vote/unvote calls per minute per IP.

## Comments

Comments are public two-level threads — a root comment's `replies` are its direct replies, and replies never have replies of their own. Listing needs no identity; posting sends the anonymous id.

```swift
// List (paginated)
let result = await FeedbackJar.shared.listComments(postId: post.id, limit: 20)
if case .success(let page) = result {
    for comment in page.comments {
        print("\(comment.authorName): \(comment.content)")
        for reply in comment.replies {
            print("  ↳ \(reply.authorName): \(reply.content)")
        }
    }
    // page.nextCursor is non-nil when more pages exist
}
```

Posting a comment requires guest comments to be enabled (`WidgetConfig.allowComments`). `name`/`email` fall back to the remembered identity; `email` is used only for reply notifications and is never linked to a real account.

```swift
// Top-level comment
let result = await FeedbackJar.shared.addComment(postId: post.id, content: "Please add dark mode!")
if case .success(let commentId) = result { print("Posted: \(commentId)") }

// Reply to a root comment
_ = await FeedbackJar.shared.addComment(
    postId: post.id,
    content: "Agreed",
    parentId: rootComment.id
)
```

Callback variants exist for both (`listComments(postId:limit:cursor:completion:)`, `addComment(postId:content:parentId:name:email:completion:)`).

> Rate limits: 10 comment posts per minute per IP.

## Rich text

Post and comment content can contain light Markdown (**bold**, *italic*, `code`,
`[links](url)`, headings, lists, quotes, fenced code) and FeedbackJar mention
tokens — `#[Post title](postId)` and `@[Name](user:id)`. `FeedbackJarBoard`
renders all of this; list previews are flattened to plain text, and tapping a
`#[…]` reference opens that post's detail screen (fetched via `getPost` when it
isn't already loaded).

Building your own UI? The renderer and flattener are public — no dependency:

```swift
FJRichText(post.content) { postId in
    Task {
        if case .success(let post) = await FeedbackJar.shared.getPost(postId) {
            open(post)
        }
    }
}

let preview = fjPlainText(post.content) // for a truncated row
```

Links (and `[text](url)`) open via the environment's `openURL`; `@[…]` mentions
are styled but not linked.

## API reference

### `FeedbackJar`

| Method | Description |
| --- | --- |
| `configure(widgetId:)` | Configure the SDK. Call once before anything else. |
| `submit(_ content:, email:, name:, properties:) async -> Result<FeedbackResponse, Error>` | Submit feedback, optionally with custom properties merged into `app` metadata. |
| `submit(_ content:, email:, name:, properties:, completion:)` | Callback variant, main-thread safe. |
| `listFeedback(boardId:limit:cursor:) async -> Result<FeedbackListResult, Error>` | List public feedback. `limit` is clamped to 1–50. |
| `listFeedback(boardId:limit:cursor:completion:)` | Callback variant. |
| `getPost(_ postId:) async -> Result<FeedbackPost, Error>` | Fetch one public post — resolves `#[…]` mention jump-links. |
| `getPost(_ postId:completion:)` | Callback variant. |
| `getConfig() async -> Result<WidgetConfig, Error>` | Fetch org config (name/email prompts, voting, commenting). |
| `getConfig(completion:)` | Callback variant. |
| `vote(postId:) async -> Result<VoteState, Error>` | Upvote a post as this install's guest. Idempotent. |
| `unvote(postId:) async -> Result<VoteState, Error>` | Remove this install's upvote. Idempotent. |
| `voteState(postId:) async -> Result<VoteState, Error>` | Current upvote count and whether this install voted. |
| `listComments(postId:limit:cursor:) async -> Result<FeedbackCommentListResult, Error>` | List public comment threads. `limit` clamped to 1–50. |
| `addComment(postId:content:parentId:name:email:) async -> Result<String, Error>` | Post a comment or reply as this install's guest. Returns the comment id. |
| `vote` / `unvote` / `voteState` / `listComments` / `addComment` `(…completion:)` | Callback variants. |
| `setIdentity(name:email:)` | Remember a submitter's name/email for future `submit` calls; best-effort synced to the server. |
| `getIdentity() -> FeedbackIdentity` | The currently remembered identity, if any. |
| `clearIdentity()` | Forget the remembered identity. |

### `FeedbackResponse`

```swift
public struct FeedbackResponse {
    let postId: String
    let title: String    // AI-generated title for the submission
    let type: String     // e.g. FEEDBACK, BUG, FEATURE_REQUEST
    let boardId: String
}
```

### `FeedbackPost`

```swift
public struct FeedbackPost {
    let id: String
    let title: String
    let content: String
    let type: String
    let status: String       // OPEN, IN_PROGRESS, COMPLETED, ...
    let slug: String
    let boardId: String
    let voteCount: Int
    let commentCount: Int
    let upvotes: Int
    let hasVoted: Bool        // whether this install's anon id upvoted this post
    let authorName: String?
    let createdAt: String    // ISO-8601
    let updatedAt: String    // ISO-8601
}
```

### `FeedbackListResult`

```swift
public struct FeedbackListResult {
    let posts: [FeedbackPost]
    let nextCursor: String?  // nil when there are no more pages
}
```

### `WidgetConfig`

```swift
public struct WidgetConfig {
    let collectName: Bool     // org asks for the submitter's name
    let collectEmail: Bool    // org asks for the submitter's email
    let allowVotes: Bool      // guest upvoting enabled for this project
    let allowComments: Bool   // guest commenting enabled for this project
}
```

### `FeedbackIdentity`

```swift
public struct FeedbackIdentity {
    let name: String?
    let email: String?
}
```

### `VoteState`

```swift
public struct VoteState {
    let upvotes: Int
    let hasVoted: Bool  // whether this install's anon id upvoted
}
```

### `FeedbackComment`

```swift
public struct FeedbackComment {
    let id: String
    let content: String
    let authorName: String
    let authorRole: String?   // "owner" / "admin" / "member" for team members, else nil
    let isBot: Bool
    let parentId: String?     // nil for root comments
    let createdAt: String     // ISO-8601
    let replies: [FeedbackComment]  // direct replies (empty for a reply)
}
```

### `FeedbackCommentListResult`

```swift
public struct FeedbackCommentListResult {
    let comments: [FeedbackComment]
    let nextCursor: String?   // nil when there are no more pages
}
```

## Notes

- Feedback can be submitted anonymously, or with a name/email — the SDK never requires either.
- Name/email are persisted in `UserDefaults` on-device (no extra dependency) so they survive app restarts.
- Voting and commenting are anonymous. Each install generates one random id (`UserDefaults` key `com.feedbackjar.sdk.anonId`), reset on reinstall. It is not a device id and no IDFV / advertising id is ever sent.
- Private boards and non-public posts are never returned by `listFeedback` or `getPost`.
- Every request carries an `X-FeedbackJar-SDK: swift/<version>` header; submissions also include `sdk` / `sdkVersion` in metadata.
- All methods return a Swift `Result`; nothing throws on network/HTTP errors.
- No dependencies beyond the Swift standard library and `Foundation`/`UIKit`. The prebuilt UI uses `SwiftUI`, a system framework — still no third-party dependency.
