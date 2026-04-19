import Foundation

/// Protocol for embedding a string into a Float vector.
public protocol EmbeddingProvider: Sendable {
    func embed(_ text: String) -> [Float]?
    var dimension: Int { get }
}

/// A no-op embedding provider for use in tests and on Linux.
public struct StubEmbeddingProvider: EmbeddingProvider, Sendable {
    public let dimension = 0
    public init() {}
    public func embed(_ text: String) -> [Float]? { nil }
}

#if canImport(NaturalLanguage)
import NaturalLanguage

/// On-device embedding via NLEmbedding (iOS 14+, zero network cost).
public final class NLEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    private let embedding: NLEmbedding
    public let dimension: Int

    public init?(language: NLLanguage = .english) {
        guard let emb = NLEmbedding.sentenceEmbedding(for: language) else { return nil }
        self.embedding = emb
        self.dimension = emb.dimension
    }

    public func embed(_ text: String) -> [Float]? {
        guard let vector = embedding.vector(for: text) else { return nil }
        return vector.map { Float($0) }
    }
}
#endif

/// Returns the cosine similarity between two equal-length Float vectors.
/// Returns 0 for zero vectors or mismatched lengths.
public func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot: Float = 0
    var normA: Float = 0
    var normB: Float = 0
    for i in 0..<a.count {
        dot += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }
    let denom = normA.squareRoot() * normB.squareRoot()
    guard denom > 0 else { return 0 }
    return dot / denom
}
