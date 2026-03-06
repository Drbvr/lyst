import Foundation

/// Represents a flexible property value that can be different types
public enum PropertyValue: Codable, Equatable, Hashable {
    case text(String)
    case number(Double)
    case date(Date)
    case bool(Bool)

    enum CodingKeys: String, CodingKey {
        case text
        case number
        case date
        case bool
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(text)
        } else if let number = try container.decodeIfPresent(Double.self, forKey: .number) {
            self = .number(number)
        } else if let date = try container.decodeIfPresent(Date.self, forKey: .date) {
            self = .date(date)
        } else if let bool = try container.decodeIfPresent(Bool.self, forKey: .bool) {
            self = .bool(bool)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "PropertyValue must contain one of: text, number, date, bool"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let value):
            try container.encode(value, forKey: .text)
        case .number(let value):
            try container.encode(value, forKey: .number)
        case .date(let value):
            try container.encode(value, forKey: .date)
        case .bool(let value):
            try container.encode(value, forKey: .bool)
        }
    }
}
