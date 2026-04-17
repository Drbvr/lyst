import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking

// swift-corelibs-foundation on Linux exposes URLSession via FoundationNetworking
// but, as of Swift 5.10, does not ship the async `data(for:)` method that
// Darwin Foundation provides. Shim it with a continuation over the closure
// API so Core compiles on Linux for CI. Production network calls always run
// on iOS with the real Darwin implementation.
extension URLSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
            task.resume()
        }
    }
}
#endif
