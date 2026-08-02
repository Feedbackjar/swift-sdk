# FeedbackJar iOS SDK

A lightweight iOS SDK for collecting user feedback. You build your own form — the SDK handles submission (enriched with device metadata) and fetching the public feedback list.

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

## Checking whether to ask for name/email

The organization's dashboard settings ("Ask for Name" / "Ask for Email") control whether submitters should be prompted. The SDK doesn't render any UI itself, so read this before building your own form:

```swift
let config = await FeedbackJar.shared.getConfig()
if case .success(let value) = config {
    showNameField = value.collectName
    showEmailField = value.collectEmail
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

## API reference

### `FeedbackJar`

| Method | Description |
| --- | --- |
| `configure(widgetId:)` | Configure the SDK. Call once before anything else. |
| `submit(_ content:, email:, name:, properties:) async -> Result<FeedbackResponse, Error>` | Submit feedback, optionally with custom properties merged into `app` metadata. |
| `submit(_ content:, email:, name:, properties:, completion:)` | Callback variant, main-thread safe. |
| `listFeedback(boardId:limit:cursor:) async -> Result<FeedbackListResult, Error>` | List public feedback. `limit` is clamped to 1–50. |
| `listFeedback(boardId:limit:cursor:completion:)` | Callback variant. |
| `getConfig() async -> Result<WidgetConfig, Error>` | Fetch whether the org asks for name/email. |
| `getConfig(completion:)` | Callback variant. |
| `setIdentity(name:email:)` | Remember a submitter's name/email for future `submit` calls. |
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
    let collectName: Bool   // org asks for the submitter's name
    let collectEmail: Bool  // org asks for the submitter's email
}
```

### `FeedbackIdentity`

```swift
public struct FeedbackIdentity {
    let name: String?
    let email: String?
}
```

## Notes

- Feedback can be submitted anonymously, or with a name/email — the SDK never requires either.
- Name/email are persisted in `UserDefaults` on-device (no extra dependency) so they survive app restarts.
- Private boards and non-public posts are never returned by `listFeedback`.
- All methods return a Swift `Result`; nothing throws on network/HTTP errors.
- No dependencies beyond the Swift standard library and `Foundation`/`UIKit`.
