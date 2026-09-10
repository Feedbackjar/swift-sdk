import Foundation

/// SDK identity, sent on every request as `X-FeedbackJar-SDK: <name>/<version>`
/// and mirrored into submission metadata (`sdk` / `sdkVersion`).
///
/// Keep `version` in sync with the `swift-v*` release tag / `Package.swift`.
internal enum SDKInfo {
    static let name = "swift"
    static let version = "1.3.0"
    static var identifier: String { "\(name)/\(version)" }
}
