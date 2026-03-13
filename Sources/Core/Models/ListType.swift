import Foundation

/// Represents a type of list with field definitions
public struct ListType: Codable, Hashable {
    public let name: String
    public var fields: [FieldDefinition]
    public var llmExtractionPrompt: String?

    public init(
        name: String,
        fields: [FieldDefinition] = [],
        llmExtractionPrompt: String? = nil
    ) {
        self.name = name
        self.fields = fields
        self.llmExtractionPrompt = llmExtractionPrompt
    }
}

/// Represents a field definition in a ListType
public struct FieldDefinition: Codable, Hashable {
    public let name: String
    public let type: FieldType
    public let required: Bool
    public var min: Double?  // For number validation
    public var max: Double?

    public init(
        name: String,
        type: FieldType,
        required: Bool = false,
        min: Double? = nil,
        max: Double? = nil
    ) {
        self.name = name
        self.type = type
        self.required = required
        self.min = min
        self.max = max
    }
}

/// Represents the type of a field
public enum FieldType: String, Codable {
    case text
    case number
    case date
}
