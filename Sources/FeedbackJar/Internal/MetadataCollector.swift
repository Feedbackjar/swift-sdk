import UIKit

internal struct DeviceMetadata: Encodable {
    let os: OSInfo
    let device: DeviceInfo
    let screen: ScreenInfo
    let locale: LocaleInfo
    let app: AppInfo
    let timestamp: String

    struct OSInfo: Encodable { let name: String; let version: String }
    struct DeviceInfo: Encodable { let model: String; let type: String }
    struct ScreenInfo: Encodable { let widthPt: Double; let heightPt: Double; let scale: Double }
    struct LocaleInfo: Encodable { let language: String; let region: String; let timezone: String }
    struct AppInfo: Encodable { let bundleId: String; let version: String; let build: String }
}

@MainActor
internal enum MetadataCollector {
    static func collect() -> DeviceMetadata {
        let device = UIDevice.current
        let screen = UIScreen.main
        let bundle = Bundle.main

        return DeviceMetadata(
            os: .init(name: "iOS", version: device.systemVersion),
            device: .init(
                model: device.model,
                type: device.userInterfaceIdiom == .pad ? "tablet" : "mobile"
            ),
            screen: .init(
                widthPt: screen.bounds.width,
                heightPt: screen.bounds.height,
                scale: screen.scale
            ),
            locale: .init(
                language: Locale.current.languageCode ?? "",
                region: Locale.current.regionCode ?? "",
                timezone: TimeZone.current.identifier
            ),
            app: .init(
                bundleId: bundle.bundleIdentifier ?? "",
                version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                build: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            ),
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }
}
