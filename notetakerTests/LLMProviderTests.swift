import Testing
import Foundation
@testable import notetaker

@Suite("LLMProvider Tests")
struct LLMProviderTests {

    @Test func allCases() {
        #expect(LLMProvider.allCases.count == 9)
        #expect(LLMProvider.allCases.contains(.foundationModels))
        #expect(LLMProvider.allCases.contains(.ollama))
        #expect(LLMProvider.allCases.contains(.openAI))
        #expect(LLMProvider.allCases.contains(.anthropic))
        #expect(LLMProvider.allCases.contains(.deepSeek))
        #expect(LLMProvider.allCases.contains(.moonshot))
        #expect(LLMProvider.allCases.contains(.zhipu))
        #expect(LLMProvider.allCases.contains(.minimax))
        #expect(LLMProvider.allCases.contains(.custom))
    }

    @Test func rawValues() {
        #expect(LLMProvider.foundationModels.rawValue == "foundationModels")
        #expect(LLMProvider.ollama.rawValue == "ollama")
        #expect(LLMProvider.openAI.rawValue == "openAI")
        #expect(LLMProvider.anthropic.rawValue == "anthropic")
        #expect(LLMProvider.deepSeek.rawValue == "deepSeek")
        #expect(LLMProvider.moonshot.rawValue == "moonshot")
        #expect(LLMProvider.zhipu.rawValue == "zhipu")
        #expect(LLMProvider.minimax.rawValue == "minimax")
        #expect(LLMProvider.custom.rawValue == "custom")
    }

    @Test func defaultBaseURLs() {
        #expect(LLMProvider.foundationModels.defaultBaseURL == "")
        #expect(LLMProvider.ollama.defaultBaseURL == "http://localhost:11434")
        #expect(LLMProvider.openAI.defaultBaseURL == "https://api.openai.com/v1")
        #expect(LLMProvider.anthropic.defaultBaseURL == "https://api.anthropic.com")
        #expect(LLMProvider.deepSeek.defaultBaseURL == "https://api.deepseek.com")
        #expect(LLMProvider.moonshot.defaultBaseURL == "https://api.moonshot.cn/v1")
        #expect(LLMProvider.zhipu.defaultBaseURL == "https://open.bigmodel.cn/api/paas/v4")
        #expect(LLMProvider.minimax.defaultBaseURL == "https://api.minimax.chat/v1")
        #expect(LLMProvider.custom.defaultBaseURL == "http://localhost:1234/v1")
    }

    @Test func requiresAPIKey() {
        #expect(!LLMProvider.foundationModels.requiresAPIKey)
        #expect(!LLMProvider.ollama.requiresAPIKey)
        #expect(LLMProvider.openAI.requiresAPIKey)
        #expect(LLMProvider.anthropic.requiresAPIKey)
        #expect(LLMProvider.deepSeek.requiresAPIKey)
        #expect(LLMProvider.moonshot.requiresAPIKey)
        #expect(LLMProvider.zhipu.requiresAPIKey)
        #expect(LLMProvider.minimax.requiresAPIKey)
        #expect(LLMProvider.custom.requiresAPIKey)
    }

    @Test func chinaAvailability() {
        #expect(LLMProvider.foundationModels.isAvailableInChina)
        #expect(LLMProvider.ollama.isAvailableInChina)
        #expect(!LLMProvider.openAI.isAvailableInChina)
        #expect(!LLMProvider.anthropic.isAvailableInChina)
        #expect(LLMProvider.deepSeek.isAvailableInChina)
        #expect(LLMProvider.moonshot.isAvailableInChina)
        #expect(LLMProvider.zhipu.isAvailableInChina)
        #expect(LLMProvider.minimax.isAvailableInChina)
        #expect(LLMProvider.custom.isAvailableInChina)
    }

    @Test func filingURLs() {
        #expect(LLMProvider.deepSeek.filingURL != nil)
        #expect(LLMProvider.moonshot.filingURL != nil)
        #expect(LLMProvider.zhipu.filingURL != nil)
        #expect(LLMProvider.minimax.filingURL != nil)
        #expect(LLMProvider.openAI.filingURL == nil)
        #expect(LLMProvider.anthropic.filingURL == nil)
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
