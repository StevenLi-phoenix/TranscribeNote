import Foundation

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
        case .foundationModels: "Apple Intelligence (On-Device)"
        case .ollama: "Ollama"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .deepSeek: "DeepSeek (深度求索)"
        case .moonshot: "Moonshot AI (月之暗面)"
        case .zhipu: "Zhipu AI (智谱)"
        case .minimax: "MiniMax (稀宇科技)"
        case .custom: "Custom (OpenAI-compatible)"
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
        case .foundationModels, .ollama, .deepSeek, .moonshot, .zhipu, .minimax, .custom:
            true
        case .openAI, .anthropic:
            false
        }
    }

    /// URL to the provider's official filing/registration page (备案信息), if applicable.
    var filingURL: URL? {
        switch self {
        case .deepSeek:
            URL(string: "https://www.deepseek.com/")  // 浙ICP备2023025841号
        case .moonshot:
            URL(string: "https://platform.moonshot.cn/")  // 网信算备110108896786101240015号
        case .zhipu:
            URL(string: "https://open.bigmodel.cn/")  // Beijing-ChatGLM-20230821
        case .minimax:
            URL(string: "https://platform.minimax.io/")  // 沪ICP备2023003282号
        default:
            nil
        }
    }

    /// Providers available in the current storefront region.
    static var availableProviders: [LLMProvider] {
        if isChineseStorefront {
            allCases.filter(\.isAvailableInChina)
        } else {
            allCases
        }
    }

    /// Detect if the device is configured for the Chinese storefront.
    static var isChineseStorefront: Bool {
        // Check App Store storefront first (SKStorefront), fall back to locale region
        let region = Locale.current.region?.identifier ?? ""
        return region == "CN" || region == "CHN"
    }
}
