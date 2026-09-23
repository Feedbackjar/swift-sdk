import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
import Darwin
#endif

internal struct DeviceMetadata: Encodable {
    let os: OSInfo
    let device: DeviceInfo
    let screen: ScreenInfo
    let locale: LocaleInfo
    let app: [String: JSONValue]
    let sdk: String
    let sdkVersion: String
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
        let bundle = Bundle.main

        var app: [String: JSONValue] = [
            "bundleId": .string(bundle.bundleIdentifier ?? ""),
            "version": .string(bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"),
            "build": .string(bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"),
        ]
        properties?.forEach { key, value in app[key] = JSONValue(value) }

        return DeviceMetadata(
            os: osInfo,
            device: deviceInfo,
            screen: screenInfo,
            locale: .init(
                language: Locale.current.languageCode ?? "",
                region: Locale.current.regionCode ?? "",
                timezone: TimeZone.current.identifier
            ),
            app: app,
            sdk: SDKInfo.name,
            sdkVersion: SDKInfo.version,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    #if os(iOS)
    private static var osInfo: DeviceMetadata.OSInfo {
        .init(name: "iOS", version: UIDevice.current.systemVersion)
    }

    private static var deviceInfo: DeviceMetadata.DeviceInfo {
        .init(
            model: UIDevice.current.model,
            type: UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "mobile"
        )
    }

    private static var screenInfo: DeviceMetadata.ScreenInfo {
        let screen = UIScreen.main
        return .init(widthPt: screen.bounds.width, heightPt: screen.bounds.height, scale: screen.scale)
    }
    #elseif os(macOS)
    private static var osInfo: DeviceMetadata.OSInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return .init(
            name: "macOS",
            version: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        )
    }

    private static var deviceInfo: DeviceMetadata.DeviceInfo {
        .init(model: hardwareModel, type: "desktop")
    }

    private static var screenInfo: DeviceMetadata.ScreenInfo {
        guard let screen = NSScreen.main else {
            return .init(widthPt: 0, heightPt: 0, scale: 1)
        }
        return .init(
            widthPt: screen.frame.width,
            heightPt: screen.frame.height,
            scale: screen.backingScaleFactor
        )
    }

    /// e.g. "MacBookPro18,3" — read via `sysctl`, mirroring `UIDevice.model`'s role on iOS.
    private static var hardwareModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var raw = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &raw, &size, nil, 0)
        return String(cString: raw)
    }
    #endif
}
