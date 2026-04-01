import Testing
import Foundation
@testable import TranscribeNote

@Suite("LLMHTTPHelpers Tests", .serialized)
struct LLMHTTPHelpersTests {

    // MARK: - validateHTTPResponse

    @Test func validateHTTPResponseSuccess() throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.test.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let data = Data()
        // Should not throw
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)
    }

    @Test func validateHTTPResponseRange() throws {
        for code in [200, 201, 204, 299] {
            let response = HTTPURLResponse(
                url: URL(string: "https://api.test.com")!,
                statusCode: code,
                httpVersion: nil,
                headerFields: nil
            )!
            try LLMHTTPHelpers.validateHTTPResponse(response, data: Data())
        }
    }

    @Test func validateHTTPResponse400() {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.test.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!
        let body = "Bad Request".data(using: .utf8)!
        #expect(throws: LLMEngineError.self) {
            try LLMHTTPHelpers.validateHTTPResponse(response, data: body)
        }
    }

    @Test func validateHTTPResponse500() {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.test.com")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        let body = "Internal Server Error".data(using: .utf8)!
        #expect(throws: LLMEngineError.self) {
            try LLMHTTPHelpers.validateHTTPResponse(response, data: body)
        }
    }

    @Test func validateHTTPResponseNonHTTPIgnored() throws {
        let response = URLResponse(
            url: URL(string: "https://api.test.com")!,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )
        // Non-HTTP responses should pass without error
        try LLMHTTPHelpers.validateHTTPResponse(response, data: Data())
    }

    // MARK: - decodeResponse

    private struct TestResponse: Codable {
        let message: String
        let count: Int
    }

    @Test func decodeResponseSuccess() throws {
        let json = """
        {"message":"hello","count":42}
        """
        let result = try LLMHTTPHelpers.decodeResponse(TestResponse.self, from: json.data(using: .utf8)!)
        #expect(result.message == "hello")
        #expect(result.count == 42)
    }

    @Test func decodeResponseFailure() {
        let badJSON = "not json at all".data(using: .utf8)!
        #expect(throws: LLMEngineError.self) {
            try LLMHTTPHelpers.decodeResponse(TestResponse.self, from: badJSON)
        }
    }

    // MARK: - normalizeBaseURL

    @Test func normalizeBaseURLStripsTrailingSlash() {
        #expect(LLMHTTPHelpers.normalizeBaseURL("https://api.test.com/") == "https://api.test.com")
    }

    @Test func normalizeBaseURLStripsMultipleSlashes() {
        #expect(LLMHTTPHelpers.normalizeBaseURL("https://api.test.com///") == "https://api.test.com")
    }

    @Test func normalizeBaseURLNoChange() {
        #expect(LLMHTTPHelpers.normalizeBaseURL("https://api.test.com") == "https://api.test.com")
    }

    @Test func normalizeBaseURLStripV1() {
        #expect(LLMHTTPHelpers.normalizeBaseURL("https://api.anthropic.com/v1", stripV1: true) == "https://api.anthropic.com")
    }

    @Test func normalizeBaseURLStripV1WithTrailingSlash() {
        #expect(LLMHTTPHelpers.normalizeBaseURL("https://api.anthropic.com/v1/", stripV1: true) == "https://api.anthropic.com")
    }

    @Test func normalizeBaseURLDoesNotStripV1ByDefault() {
        #expect(LLMHTTPHelpers.normalizeBaseURL("https://api.openai.com/v1") == "https://api.openai.com/v1")
    }

    // MARK: - validateBaseURL

    @Test func validateBaseURLHttps() throws {
        let result = try LLMHTTPHelpers.validateBaseURL("https://api.test.com/v1/")
        #expect(result == "https://api.test.com/v1")
    }

    @Test func validateBaseURLHttp() throws {
        let result = try LLMHTTPHelpers.validateBaseURL("http://localhost:11434")
        #expect(result == "http://localhost:11434")
    }

    @Test func validateBaseURLInvalid() {
        #expect(throws: LLMEngineError.self) {
            try LLMHTTPHelpers.validateBaseURL("not-a-url")
        }
    }

    @Test func validateBaseURLFtp() {
        #expect(throws: LLMEngineError.self) {
            try LLMHTTPHelpers.validateBaseURL("ftp://files.test.com")
        }
    }

    // MARK: - stripThinking

    @Test func stripThinkingRemovesBlock() {
        let input = "<think>I need to think about this...</think>Here is my answer."
        let result = LLMHTTPHelpers.stripThinking(from: input)
        #expect(result == "Here is my answer.")
    }

    @Test func stripThinkingMultiLine() {
        let input = """
        <think>
        Step 1: Think
        Step 2: More thinking
        </think>
        The final answer is 42.
        """
        let result = LLMHTTPHelpers.stripThinking(from: input)
        #expect(result == "The final answer is 42.")
    }

    @Test func stripThinkingNoThinkBlock() {
        let input = "Just a normal response."
        let result = LLMHTTPHelpers.stripThinking(from: input)
        #expect(result == "Just a normal response.")
    }

    @Test func stripThinkingEmptyThinkBlock() {
        let input = "<think></think>Answer"
        let result = LLMHTTPHelpers.stripThinking(from: input)
        #expect(result == "Answer")
    }
}
