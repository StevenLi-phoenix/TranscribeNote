import Foundation
import StoreKit
import os

nonisolated enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case foundationModels
    case ollama
    case openAI
    case anthropic
    case deepSeek
    case moonshot
    case zhipu
    case minimax
    case custom

    /// Default base URL for each provider.
    var defaultBaseURL: String {
        switch self {
        case .foundationModels: ""
        case .ollama: "http://localhost:11434"
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        case .deepSeek: "https://api.deepseek.com"
        case .moonshot: "https://api.moonshot.cn/v1"
        case .zhipu: "https://open.bigmodel.cn/api/paas/v4"
        case .minimax: "https://api.minimax.chat/v1"
        case .custom: "http://localhost:1234/v1"
        }
    }

    /// Default model name shown when switching to this provider.
    var defaultModel: String {
        switch self {
        case .foundationModels: "Apple Intelligence"
        case .ollama: "qwen3.5-9b-mlx"
        case .openAI: "gpt-4o"
        case .anthropic: "claude-sonnet-4-5-20250514"
        case .deepSeek: "deepseek-chat"
        case .moonshot: "moonshot-v1-auto"
        case .zhipu: "glm-4-plus"
        case .minimax: "MiniMax-Text-01"
        case .custom: "qwen3.5-9b-mlx"
        }
    }

    /// Approximate max input characters for transcript context (~4 chars per token).
    /// Used by ChatService and PromptBuilder to truncate long transcripts before sending.
    var maxInputCharacters: Int {
        switch self {
        case .foundationModels: 12_000   // ~3K tokens, small on-device model
        case .ollama: 24_000             // ~6K tokens, depends on local model
        case .openAI: 400_000            // ~100K tokens, GPT-4o has 128K context
        case .anthropic: 400_000         // ~100K tokens, Claude has 200K context
        case .deepSeek: 400_000          // ~100K tokens, DeepSeek-V3 has 128K context
        case .moonshot: 400_000          // ~100K tokens, moonshot-v1-128k
        case .zhipu: 400_000             // ~100K tokens, GLM-4 has 128K context
        case .minimax: 400_000           // ~100K tokens, MiniMax-Text-01 has 1M context
        case .custom: 60_000             // ~15K tokens, conservative default
        }
    }

    /// Sensible default max output tokens for each provider.
    var defaultMaxTokens: Int {
        switch self {
        case .foundationModels: 4096
        case .ollama: 4096
        case .openAI: 4096
        case .anthropic: 8192
        case .deepSeek: 8192
        case .moonshot: 4096
        case .zhipu: 4096
        case .minimax: 4096
        case .custom: 4096
        }
    }

    /// Human-readable display name for the settings UI.
    var displayName: String {
        switch self {
        case .foundationModels: String(localized: "Apple Intelligence (On-Device)")
        case .ollama: "Ollama"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .deepSeek: "DeepSeek (深度求索)"
        case .moonshot: "Moonshot AI (月之暗面)"
        case .zhipu: "Zhipu AI (智谱)"
        case .minimax: "MiniMax (稀宇科技)"
        case .custom: String(localized: "Custom (OpenAI-compatible)")
        }
    }

    /// Whether this provider requires an API key for authentication.
    var requiresAPIKey: Bool {
        switch self {
        case .foundationModels, .ollama: false
        default: true
        }
    }

    /// Whether this provider is available on the China App Store (has proper 备案/filing).
    var isAvailableInChina: Bool {
        switch self {
        case .ollama, .deepSeek, .moonshot, .zhipu, .minimax, .custom:
            true
        case .foundationModels, .openAI, .anthropic:
            false
        }
    }

    /// Filing/registration number (备案号) for Chinese providers.
    var filingNumber: String? {
        switch self {
        case .deepSeek: "浙ICP备2023025841号"
        case .moonshot: "网信算备110108896786101240015号"
        case .zhipu: "网信算备110108105858001230019号"
        case .minimax: "沪ICP备2023003282号"
        default: nil
        }
    }

    /// URL to the provider's official filing/registration page (备案信息), if applicable.
    var filingURL: URL? {
        switch self {
        case .deepSeek: URL(string: "https://www.deepseek.com/")
        case .moonshot: URL(string: "https://platform.moonshot.cn/")
        case .zhipu: URL(string: "https://open.bigmodel.cn/")
        case .minimax: URL(string: "https://platform.minimax.io/")
        default: nil
        }
    }

    /// Providers available in the current storefront region.
    /// - `CHINA_APPSTORE`: empty — all LLM features disabled per Guidelines 3.1.1 & 5.
    /// - `APPSTORE`: only Apple Intelligence (on-device) — third-party providers hidden.
    static var availableProviders: [LLMProvider] {
        #if CHINA_APPSTORE
        []
        #elseif APPSTORE
        FoundationModelsEngine.isModelAvailable ? [.foundationModels] : []
        #else
        if isChineseStorefront {
            allCases.filter(\.isAvailableInChina)
        } else {
            allCases
        }
        #endif
    }

    /// Detect if the device is configured for the Chinese storefront.
    /// Uses cached result from async SKStorefront lookup, with locale fallback.
    static var isChineseStorefront: Bool {
        if let cached = _cachedIsChineseStorefront {
            return cached
        }
        // Fallback to locale until async storefront check completes
        let region = Locale.current.region?.identifier ?? ""
        return region == "CN" || region == "CHN"
    }

    /// Cached storefront detection result, populated by `refreshStorefrontStatus()`.
    private(set) nonisolated(unsafe) static var _cachedIsChineseStorefront: Bool?

    /// Call once at app launch to asynchronously detect the App Store storefront.
    static func refreshStorefrontStatus() async {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TranscribeNote", category: "LLMProvider")
        do {
            if let storefront = try await Storefront.current {
                let isCN = storefront.countryCode == "CHN"
                _cachedIsChineseStorefront = isCN
                logger.info("Storefront detected: \(storefront.countryCode, privacy: .public), isChina=\(isCN)")
            } else {
                logger.info("No storefront available, falling back to locale")
            }
        } catch {
            logger.warning("Failed to fetch storefront: \(error.localizedDescription, privacy: .public)")
        }
    }
}
