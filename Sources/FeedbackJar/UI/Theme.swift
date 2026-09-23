#if canImport(SwiftUI)
import SwiftUI

// MARK: - Design tokens
//
// Deliberately cheap (see UI-SPEC.md): two font sizes, three greys plus a
// surface, one accent colour, one corner radius, no shadows, no cards.

enum FJFont {
    /// Body text — titles, comment bodies, inputs.
    static let body: CGFloat = 15
    /// Small text — counts, meta rows, tags.
    static let small: CGFloat = 13
}

/// The one corner radius — buttons and inputs only.
let fjRadius: CGFloat = 8

/// FeedbackJar red — the default accent when the caller passes none.
let fjDefaultAccent = Color(red: 229.0 / 255.0, green: 72.0 / 255.0, blue: 77.0 / 255.0)

// MARK: - Palette

/// Resolved colours for the current colour scheme. Exactly three greys
/// (`text`, `textDim`, `divider`) plus a surface `bg` and a `field` fill.
struct FJPalette {
    let accent: Color
    let bg: Color
    let text: Color
    let textDim: Color
    let divider: Color
    let field: Color

    static func resolve(_ scheme: ColorScheme, accent: Color) -> FJPalette {
        if scheme == .dark {
            return FJPalette(
                accent: accent,
                bg: Color(red: 0x15 / 255.0, green: 0x15 / 255.0, blue: 0x15 / 255.0),
                text: Color(red: 0xF2 / 255.0, green: 0xF2 / 255.0, blue: 0xF2 / 255.0),
                textDim: Color(red: 0x9A / 255.0, green: 0x9A / 255.0, blue: 0x9A / 255.0),
                divider: Color(red: 0x2C / 255.0, green: 0x2C / 255.0, blue: 0x2C / 255.0),
                field: Color(red: 0x24 / 255.0, green: 0x24 / 255.0, blue: 0x24 / 255.0)
            )
        }
        return FJPalette(
            accent: accent,
            bg: .white,
            text: Color(red: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x1A / 255.0),
            textDim: Color(red: 0x76 / 255.0, green: 0x76 / 255.0, blue: 0x76 / 255.0),
            divider: Color(red: 0xE6 / 255.0, green: 0xE6 / 255.0, blue: 0xE6 / 255.0),
            field: Color(red: 0xF4 / 255.0, green: 0xF4 / 255.0, blue: 0xF4 / 255.0)
        )
    }
}

// MARK: - Accent propagation

private struct FJAccentKey: EnvironmentKey {
    static let defaultValue: Color = fjDefaultAccent
}

extension EnvironmentValues {
    /// The caller-overridable accent colour, injected by `FeedbackJarBoard`.
    var fjAccent: Color {
        get { self[FJAccentKey.self] }
        set { self[FJAccentKey.self] = newValue }
    }
}

/// Convenience: read `colorScheme` + `fjAccent` and get a resolved palette.
extension View {
    func fjPalette(_ scheme: ColorScheme, _ accent: Color) -> FJPalette {
        FJPalette.resolve(scheme, accent: accent)
    }
}

// MARK: - Helpers

private let fjISOFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let fjISOPlain = ISO8601DateFormatter()

func fjParseDate(_ iso: String) -> Date? {
    fjISOFractional.date(from: iso) ?? fjISOPlain.date(from: iso)
}

/// Compact relative time: "just now", "3m", "5h", "2d", "4w".
func fjRelativeTime(_ iso: String) -> String {
    guard let date = fjParseDate(iso) else { return "" }
    let s = max(0, Date().timeIntervalSince(date))
    if s < 60 { return "just now" }
    if s < 3600 { return "\(Int(s / 60))m" }
    if s < 86_400 { return "\(Int(s / 3600))h" }
    if s < 604_800 { return "\(Int(s / 86_400))d" }
    return "\(Int(s / 604_800))w"
}

/// `OPEN` -> "Open", `IN_PROGRESS` -> "In progress".
func fjHumanStatus(_ status: String) -> String {
    let s = status.replacingOccurrences(of: "_", with: " ").lowercased()
    guard let first = s.first else { return s }
    return first.uppercased() + s.dropFirst()
}

/// The verbatim server message when present, else a generic description.
/// Every SDK call returns a `Result`; nothing throws.
func fjMessage(_ error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    return error.localizedDescription
}

func fjTrimmedOrNil(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// iOS 16+ can clear the `TextEditor` background; iOS 15 keeps the default.
struct FJClearEditorBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}
#endif
