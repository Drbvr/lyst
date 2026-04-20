import Foundation

// Export all models from the Core module
public struct Core {
    public static let version = "1.0.0"
}

public enum ItemTypeNormalizer {
    private static let vowels = Set(["a", "e", "i", "o", "u"])

    public static func canonicalType(from rawType: String, knownTypes: [String]) -> String {
        let cleaned = rawType.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return cleaned }

        let normalizedKnownTypes = knownTypes
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedKnownTypes.isEmpty else { return cleaned }

        var aliasesToKnownType: [String: String] = [:]
        for knownType in normalizedKnownTypes {
            let aliases = [
                knownType,
                pluralForm(of: knownType),
                formattedTypeKey(for: knownType),
                formattedTypeKey(for: pluralForm(of: knownType))
            ].filter { !$0.isEmpty }

            for alias in aliases where aliasesToKnownType[alias] == nil {
                aliasesToKnownType[alias] = knownType
            }
        }

        if let canonical = aliasesToKnownType[cleaned] {
            return canonical
        }

        let cleanedFormattedKey = formattedTypeKey(for: cleaned)
        if let canonical = aliasesToKnownType[cleanedFormattedKey] {
            return canonical
        }

        return cleaned
    }

    private static func pluralForm(of singular: String) -> String {
        guard !singular.isEmpty else { return singular }

        if singular.hasSuffix("y"), singular.count > 1 {
            let beforeY = singular.dropLast().last
            if let beforeY, !vowels.contains(String(beforeY).lowercased()) {
                return String(singular.dropLast()) + "ies"
            }
        }

        if singular.hasSuffix("s")
            || singular.hasSuffix("x")
            || singular.hasSuffix("z")
            || singular.hasSuffix("ch")
            || singular.hasSuffix("sh")
        {
            return singular + "es"
        }

        return singular + "s"
    }

    private static func formattedTypeKey(for value: String) -> String {
        value.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }
}
