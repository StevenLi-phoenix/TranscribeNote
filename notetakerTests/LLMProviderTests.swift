import Testing
import Foundation
@testable import notetaker

@Suite("LLMProvider Tests")
struct LLMProviderTests {

    @Test func allCases() {
        #expect(LLMProvider.allCases.count == 5)
        #expect(LLMProvider.allCases.contains(.foundationModels))
        #expect(LLMProvider.allCases.contains(.ollama))
        #expect(LLMProvider.allCases.contains(.openAI))
        #expect(LLMProvider.allCases.contains(.anthropic))
        #expect(LLMProvider.allCases.contains(.custom))
    }

    @Test func rawValues() {
        #expect(LLMProvider.foundationModels.rawValue == "foundationModels")
        #expect(LLMProvider.ollama.rawValue == "ollama")
        #expect(LLMProvider.openAI.rawValue == "openAI")
        #expect(LLMProvider.anthropic.rawValue == "anthropic")
        #expect(LLMProvider.custom.rawValue == "custom")
    }

    @Test func defaultBaseURLs() {
        #expect(LLMProvider.foundationModels.defaultBaseURL == "")
        #expect(LLMProvider.ollama.defaultBaseURL == "http://localhost:11434")
        #expect(LLMProvider.openAI.defaultBaseURL == "https://api.openai.com/v1")
        #expect(LLMProvider.anthropic.defaultBaseURL == "https://api.anthropic.com")
        #expect(LLMProvider.custom.defaultBaseURL == "http://localhost:1234/v1")
    }

    @Test func codableRoundTrip() throws {
        for provider in LLMProvider.allCases {
            let data = try JSONEncoder().encode(provider)
            let decoded = try JSONDecoder().decode(LLMProvider.self, from: data)
            #expect(decoded == provider)
        }
    }

    @Test func decodingFromString() throws {
        let json = "\"openAI\""
        let decoded = try JSONDecoder().decode(LLMProvider.self, from: json.data(using: .utf8)!)
        #expect(decoded == .openAI)
    }
}
