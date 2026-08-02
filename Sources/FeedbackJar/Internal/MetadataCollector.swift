import UIKit

internal struct DeviceMetadata: Encodable {
    let os: OSInfo
    let device: DeviceInfo
    let screen: ScreenInfo
    let locale: LocaleInfo
    let app: [String: JSONValue]
    let timestamp: String

    struct OSInfo: Encodable { let name: String; let version: String }
    struct DeviceInfo: Encodable { let model: String; let type: String }
    struct ScreenInfo: Encodable { let widthPt: Double; let heightPt: Double; let scale: Double }
    struct LocaleInfo: Encodable { let language: String; let region: String; let timezone: String }
}

@MainActor
internal enum MetadataCollector {
    /// - Parameter properties: custom key/value pairs (e.g. `["flavor": "foss"]`) merged into
    ///   `app`. Values should be String, Int, Double, or Bool — nested structures aren't supported.
    static func collect(properties: [String: Any]? = nil) -> DeviceMetadata {
        let device = UIDevice.current
        let screen = UIScreen.main
        let bundle = Bundle.main

        var app: [String: JSONValue] = [
            "bundleId": .string(bundle.bundleIdentifier ?? ""),
            "version": .string(bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"),
            "build": .string(bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"),
        ]
        properties?.forEach { key, value in app[key] = JSONValue(value) }

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
            app: app,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }
}
