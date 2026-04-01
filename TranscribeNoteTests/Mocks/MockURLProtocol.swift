import Foundation

/// Base class for mock URL protocols. Each test suite should create its own subclass
/// to avoid shared state issues during parallel test execution.
class MockURLProtocolBase: URLProtocol {
    private static let httpBodyPropertyKey = "MockHTTPBody"

    override class func canInit(with request: URLRequest) -> Bool { true }

    /// Preserve httpBody before URLProtocol strips it during request processing.
    /// URLProtocol replaces httpBody with httpBodyStream, making it nil in startLoading().
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        if let body = request.httpBody {
            let mutable = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
            URLProtocol.setProperty(body, forKey: httpBodyPropertyKey, in: mutable)
            return mutable as URLRequest
        }
        return request
    }

    override func stopLoading() {}

    /// Returns the original httpBody, restored from the property saved in canonicalRequest.
    /// Falls back to reading httpBodyStream if the property is missing.
    func requestWithRestoredBody() -> URLRequest {
        var restored = request
        if restored.httpBody == nil {
            if let saved = URLProtocol.property(forKey: Self.httpBodyPropertyKey, in: request) as? Data {
                restored.httpBody = saved
            } else if let stream = request.httpBodyStream {
                restored.httpBody = Self.readStream(stream)
            }
        }
        return restored
    }

    private static func readStream(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            guard bytesRead > 0 else { break }
            data.append(buffer, count: bytesRead)
        }
        return data
    }
}

/// MockURLProtocol for Ollama engine tests
final class OllamaMockProtocol: MockURLProtocolBase {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(requestWithRestoredBody())
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

/// MockURLProtocol for OpenAI engine tests
final class OpenAIMockProtocol: MockURLProtocolBase {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(requestWithRestoredBody())
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

/// MockURLProtocol for Anthropic engine tests
final class AnthropicMockProtocol: MockURLProtocolBase {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(requestWithRestoredBody())
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
