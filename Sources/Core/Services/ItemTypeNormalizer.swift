import Foundation

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

        if cleaned.hasSuffix("s"), cleaned.count > 1 {
            let singular = String(cleaned.dropLast())
            if normalisedKnownTypes.contains(singular) {
                return singular
            }
        }

        return cleaned
    }
}

