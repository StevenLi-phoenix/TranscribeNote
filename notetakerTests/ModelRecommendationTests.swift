import Testing
@testable import notetaker

@Suite("ModelRecommendation")
struct ModelRecommendationTests {

    @Test func detectHardwareReturnsValidInfo() {
        let hw = ModelRecommendation.detectHardware()
        #expect(hw.totalMemoryGB > 0)
        #expect(!hw.processorDescription.isEmpty)
    }

    @Test func localModelsHaveRequiredFields() {
        for model in ModelRecommendation.localModels {
            #expect(!model.name.isEmpty)
            #expect(!model.description.isEmpty)
        }
    }

    @Test func cloudModelsHaveRequiredFields() {
        for model in ModelRecommendation.cloudModels {
            #expect(!model.name.isEmpty)
            #expect(!model.modelID.isEmpty)
            #expect(!model.description.isEmpty)
        }
    }

    @Test func recommendedModelsFiltersByMemory() {
        let models = ModelRecommendation.recommendedModels()
        // At least Apple Intelligence + cloud models should always be included
        #expect(!models.isEmpty)
    }

    @Test func bestLocalModelReturnsValid() {
        let best = ModelRecommendation.bestLocalModel()
        #expect(!best.name.isEmpty)
    }

    @Test func cloudModelsIncluded() {
        let all = ModelRecommendation.recommendedModels()
        let hasCloud = all.contains { $0.provider == .anthropic || $0.provider == .openAI }
        #expect(hasCloud)
    }

    @Test func tierComparison() {
        #expect(ModelRecommendation.RecommendedModel.Tier.onDevice < .efficient)
        #expect(ModelRecommendation.RecommendedModel.Tier.efficient < .balanced)
        #expect(ModelRecommendation.RecommendedModel.Tier.balanced < .premium)
    }

    @Test func modelsForSmallMemory() {
        let filtered = ModelRecommendation.modelsForMemory(8)
        // 8GB * 0.7 = 5.6GB headroom — should include Apple Intelligence (0GB) but not 9B (6.6GB)
        let has9B = filtered.contains { $0.modelID == "qwen3.5-9b-mlx" }
        #expect(!has9B)
        let has35B = filtered.contains { $0.modelID == "qwen3.5-35b-mlx" }
        #expect(!has35B)
        // Apple Intelligence always fits
        let hasApple = filtered.contains { $0.provider == .foundationModels }
        #expect(hasApple)
    }

    @Test func modelsFor16GBMemory() {
        let filtered = ModelRecommendation.modelsForMemory(16)
        // 16GB * 0.7 = 11.2GB headroom — should include 9B (6.6GB) but not 27B (18GB)
        let has9B = filtered.contains { $0.modelID == "qwen3.5-9b-mlx" }
        #expect(has9B)
        let has27B = filtered.contains { $0.modelID == "qwen3.5-27b-mlx" }
        #expect(!has27B)
    }

    @Test func modelsForLargeMemory() {
        let filtered = ModelRecommendation.modelsForMemory(128)
        // Should include all models
        let has35B = filtered.contains { $0.modelID == "qwen3.5-35b-mlx" }
        #expect(has35B)
        let has9B = filtered.contains { $0.modelID == "qwen3.5-9b-mlx" }
        #expect(has9B)
    }

    @Test func bestLocalModelFor16GB() {
        let best = ModelRecommendation.bestLocalModel(forMemoryGB: 16)
        // Should pick highest tier that fits: 9B (efficient)
        #expect(best.modelID == "qwen3.5-9b-mlx")
    }

    @Test func bestLocalModelFor64GB() {
        let best = ModelRecommendation.bestLocalModel(forMemoryGB: 64)
        // Should pick highest tier: 35B (premium) since 24 <= 64*0.7=44.8
        #expect(best.modelID == "qwen3.5-35b-mlx")
    }

    @Test func bestLocalModelFor8GBFallsBackToApple() {
        let best = ModelRecommendation.bestLocalModel(forMemoryGB: 8)
        // Only Apple Intelligence fits (0GB required)
        #expect(best.provider == .foundationModels)
    }

    @Test func modelsForMemorySortedByTierDescending() {
        let filtered = ModelRecommendation.modelsForMemory(128)
        // Local models should come first, sorted by tier descending (premium first)
        let localModels = filtered.filter { $0.provider != .anthropic && $0.provider != .openAI }
        guard localModels.count >= 2 else { return }
        for i in 0..<(localModels.count - 1) {
            #expect(localModels[i].tier >= localModels[i + 1].tier)
        }
    }
}
