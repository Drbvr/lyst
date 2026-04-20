import Foundation

// Export all models from the Core module
public struct Core {
    public static let version = "1.0.0"
}

public enum ItemTypeNormalizer {

    public static func canonicalType(from rawType: String, knownTypes: [String]) -> String {
        let cleaned = rawType.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return cleaned }

        let normalisedKnownTypes = Set(
            knownTypes.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        )
        guard !normalisedKnownTypes.isEmpty else { return cleaned }

        if normalisedKnownTypes.contains(cleaned) {
            return cleaned
        }

        for knownType in normalisedKnownTypes {
            if cleaned == pluralForm(of: knownType) {
                return knownType
            }
        }

        return cleaned
    }

    private static func pluralForm(of singular: String) -> String {
        guard !singular.isEmpty else { return singular }

        if singular.hasSuffix("y"), singular.count > 1 {
            let beforeY = singular.dropLast().last
            let vowels = Set(["a", "e", "i", "o", "u"])
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
}
