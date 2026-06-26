// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FeedbackJar",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "FeedbackJar", targets: ["FeedbackJar"]),
    ],
    targets: [
        .target(name: "FeedbackJar", path: "Sources/FeedbackJar"),
    ]
)
