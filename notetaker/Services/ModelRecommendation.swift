import Foundation
import os

/// Hardware-aware model recommendation engine.
nonisolated enum ModelRecommendation {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "ModelRecommendation")

    struct SystemHardwareInfo: Sendable {
        let totalMemoryGB: Int
        let processorDescription: String
    }

    struct RecommendedModel: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let modelID: String
        let provider: LLMProvider
        let baseURL: String
        let memoryRequiredGB: Double
        let description: String
        let tier: Tier

        enum Tier: String, Sendable, Comparable {
            case onDevice = "On-Device"
            case efficient = "Efficient"
            case balanced = "Balanced"
            case premium = "Premium"

            private var sortOrder: Int {
                switch self {
                case .onDevice: 0
                case .efficient: 1
                case .balanced: 2
                case .premium: 3
                }
            }

            static func < (lhs: Tier, rhs: Tier) -> Bool {
                lhs.sortOrder < rhs.sortOrder
            }
        }
    }

    // MARK: - Hardware Detection

    /// Detect current hardware specs.
    static func detectHardware() -> SystemHardwareInfo {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalGB = Int(totalBytes / (1024 * 1024 * 1024))

        var processorDescription = "Unknown"
        var size: size_t = 0
        if sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 {
                processorDescription = String(cString: buffer)
            }
        }

        logger.debug("Detected hardware: \(processorDescription), \(totalGB)GB RAM")
        return SystemHardwareInfo(totalMemoryGB: totalGB, processorDescription: processorDescription)
    }

    // MARK: - Model Catalog

    /// All known local models with their requirements.
    static let localModels: [RecommendedModel] = [
        RecommendedModel(
            name: "Apple Intelligence", modelID: "", provider: .foundationModels, baseURL: "",
            memoryRequiredGB: 0, description: "Built-in on-device model. No setup needed.", tier: .onDevice
        ),
        RecommendedModel(
            name: "Qwen 3.5 9B", modelID: "qwen3.5-9b-mlx", provider: .custom, baseURL: "http://localhost:1234/v1",
            memoryRequiredGB: 6.6, description: "Best for 16GB Macs. Fast and capable.", tier: .efficient
        ),
        RecommendedModel(
            name: "Qwen 3.5 27B", modelID: "qwen3.5-27b-mlx", provider: .custom, baseURL: "http://localhost:1234/v1",
            memoryRequiredGB: 18, description: "Near GPT-4 quality. Great for 32GB+ Macs.", tier: .balanced
        ),
        RecommendedModel(
            name: "Qwen 3.5 35B", modelID: "qwen3.5-35b-mlx", provider: .custom, baseURL: "http://localhost:1234/v1",
            memoryRequiredGB: 24, description: "Best local model. Excellent structured output.", tier: .premium
        ),
    ]

    /// Cloud API models for reference.
    static let cloudModels: [RecommendedModel] = [
        RecommendedModel(
            name: "Claude Sonnet 4.6", modelID: "claude-sonnet-4-6-20250514", provider: .anthropic, baseURL: "https://api.anthropic.com",
            memoryRequiredGB: 0, description: "Best value cloud model.", tier: .balanced
        ),
        RecommendedModel(
            name: "GPT-4.1 mini", modelID: "gpt-4.1-mini", provider: .openAI, baseURL: "https://api.openai.com/v1",
            memoryRequiredGB: 0, description: "Fast and affordable.", tier: .efficient
        ),
    ]

    // MARK: - Recommendation

    /// Returns models compatible with the given memory (GB), sorted by quality tier.
    /// Local models filtered to those requiring <= 70% of available RAM; cloud always included.
    static func modelsForMemory(_ totalGB: Int) -> [RecommendedModel] {
        let headroom = Double(totalGB) * 0.7
        let compatible = localModels.filter { $0.memoryRequiredGB <= headroom }
        let sorted = compatible.sorted { $0.tier > $1.tier }
        return sorted + cloudModels
    }

    /// Returns models compatible with current hardware, sorted by quality tier.
    static func recommendedModels() -> [RecommendedModel] {
        let hw = detectHardware()
        let models = modelsForMemory(hw.totalMemoryGB)
        logger.info("Recommending \(models.count) models for \(hw.totalMemoryGB)GB RAM")
        return models
    }

    /// Returns the single best local model for this hardware.
    static func bestLocalModel() -> RecommendedModel {
        let hw = detectHardware()
        return bestLocalModel(forMemoryGB: hw.totalMemoryGB)
    }

    /// Returns the single best local model for a given memory size.
    static func bestLocalModel(forMemoryGB totalGB: Int) -> RecommendedModel {
        let headroom = Double(totalGB) * 0.7
        let compatible = localModels.filter { $0.memoryRequiredGB <= headroom }
        // Highest tier that fits
        return compatible.sorted { $0.tier > $1.tier }.first ?? localModels[0]
    }
}
