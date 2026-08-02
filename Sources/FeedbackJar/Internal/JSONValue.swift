import Foundation

/// Wraps a flat JSON-compatible scalar (String, Int, Double, Bool, or nil) so custom
/// submitter properties can be encoded without a fixed schema. Nested arrays/objects
/// aren't supported — non-scalar values are stringified.
internal enum JSONValue: Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(_ value: Any?) {
        switch value {
        case .none:
            self = .null
        case is NSNull:
            self = .null
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .int(value)
        case let value as Double:
            self = .double(value)
        case let value as String:
            self = .string(value)
        case .some(let value):
            self = .string(String(describing: value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
