import Foundation

nonisolated enum LLMEngineError: Error, LocalizedError {
    case invalidURL(String)
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case networkError(Error)
    case emptyResponse
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): "Invalid URL: \(url)"
        case .httpError(let code, let body): "HTTP \(code): \(body)"
        case .decodingError(let msg): "Decoding error: \(msg)"
        case .networkError(let err): "Network error: \(err.localizedDescription)"
        case .emptyResponse: "Empty response from LLM"
        case .notConfigured: "LLM not configured"
        }
    }
}

nonisolated protocol LLMEngine: AnyObject, Sendable {
    func generate(prompt: String, config: LLMConfig) async throws -> String
    func isAvailable(config: LLMConfig) async -> Bool
}

/// Shared HTTP helpers for LLM engine implementations.
nonisolated enum LLMHTTPHelpers {
    static func performRequest(_ request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw LLMEngineError.networkError(error)
        }
    }

    static func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMEngineError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
    }

    static func decodeResponse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LLMEngineError.decodingError(error.localizedDescription)
        }
    }
}
