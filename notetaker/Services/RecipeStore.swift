import Foundation
import os

/// File-based JSON storage for AI recipes. Thread-safe via file system atomicity.
nonisolated enum RecipeStore {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "RecipeStore"
    )

    // MARK: - File Path

    static var storageURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("notetaker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("recipes.json")
    }

    // MARK: - CRUD

    /// Load recipes from disk, merging with built-ins to ensure they are always present.
    static func loadRecipes() -> [AIRecipe] {
        loadRecipes(from: storageURL)
    }

    /// Load recipes from a specific URL (testable).
    static func loadRecipes(from url: URL) -> [AIRecipe] {
        var userRecipes: [AIRecipe] = []

        if let data = try? Data(contentsOf: url) {
            do {
                userRecipes = try JSONDecoder().decode([AIRecipe].self, from: data)
                logger.debug("Loaded \(userRecipes.count) recipes from disk")
            } catch {
                logger.error("Failed to decode recipes: \(error.localizedDescription)")
            }
        } else {
            logger.info("No recipes file found, using built-ins only")
        }

        // Merge: keep user recipes, ensure all built-ins present
        let userIDs = Set(userRecipes.map(\.id))
        let missingBuiltIns = builtInRecipes.filter { !userIDs.contains($0.id) }
        if !missingBuiltIns.isEmpty {
            logger.info("Adding \(missingBuiltIns.count) missing built-in recipes")
        }

        return missingBuiltIns + userRecipes
    }

    /// Save recipes to disk.
    static func saveRecipes(_ recipes: [AIRecipe]) {
        saveRecipes(recipes, to: storageURL)
    }

    /// Save recipes to a specific URL (testable).
    static func saveRecipes(_ recipes: [AIRecipe], to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(recipes)
            try data.write(to: url, options: .atomic)
            logger.debug("Saved \(recipes.count) recipes to disk")
        } catch {
            logger.error("Failed to save recipes: \(error.localizedDescription)")
        }
    }

    /// Delete a recipe by ID. Built-in recipes cannot be deleted.
    static func deleteRecipe(id: UUID, from recipes: inout [AIRecipe]) {
        let countBefore = recipes.count
        recipes.removeAll { $0.id == id && !$0.isBuiltIn }
        let removed = countBefore - recipes.count
        if removed > 0 {
            logger.info("Deleted recipe \(id)")
        } else {
            logger.debug("Recipe \(id) not deleted (built-in or not found)")
        }
    }

    /// Duplicate a recipe, creating a user-owned copy.
    static func duplicate(_ recipe: AIRecipe) -> AIRecipe {
        let now = Date()
        return AIRecipe(
            name: "\(recipe.name) (Copy)",
            description: recipe.description,
            icon: recipe.icon,
            promptTemplate: recipe.promptTemplate,
            outputSections: recipe.outputSections,
            summaryStyle: recipe.summaryStyle,
            isBuiltIn: false,
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Template Interpolation

    /// Replace `{{key}}` placeholders in a template with provided values.
    /// Unknown placeholders are left as-is.
    static func interpolate(template: String, vars: [String: String]) -> String {
        var result = template
        for (key, value) in vars {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }

    // MARK: - Built-in Recipes

    // Stable UUIDs so built-ins survive round-trips
    private static let generalMeetingID = UUID(uuidString: "A0000001-0000-0000-0000-000000000001")!
    private static let retrospectiveID  = UUID(uuidString: "A0000001-0000-0000-0000-000000000002")!
    private static let oneOnOneID       = UUID(uuidString: "A0000001-0000-0000-0000-000000000003")!
    private static let salesCallID      = UUID(uuidString: "A0000001-0000-0000-0000-000000000004")!
    private static let brainstormID     = UUID(uuidString: "A0000001-0000-0000-0000-000000000005")!
    private static let productReviewID  = UUID(uuidString: "A0000001-0000-0000-0000-000000000006")!

    static let builtInRecipes: [AIRecipe] = [
        AIRecipe(
            id: generalMeetingID,
            name: "General Meeting",
            description: "Key discussion points, decisions, and action items",
            icon: "person.3",
            promptTemplate: """
            Summarize this meeting transcript. Focus on:
            1. Key discussion points
            2. Decisions made
            3. Action items with owners

            Transcript:
            {{transcript}}
            """,
            outputSections: ["Discussion Points", "Decisions", "Action Items"],
            summaryStyle: "bullet",
            isBuiltIn: true
        ),
        AIRecipe(
            id: retrospectiveID,
            name: "Sprint Retrospective",
            description: "What went well, improvements, and next sprint goals",
            icon: "arrow.trianglehead.counterclockwise",
            promptTemplate: """
            This is a sprint retrospective meeting. Organize the discussion into:
            1. What went well
            2. What needs improvement
            3. Action items for next sprint

            Transcript:
            {{transcript}}
            """,
            outputSections: ["Went Well", "Needs Improvement", "Next Sprint Actions"],
            summaryStyle: "bullet",
            isBuiltIn: true
        ),
        AIRecipe(
            id: oneOnOneID,
            name: "1-on-1",
            description: "Status updates, blockers, career development",
            icon: "person.2",
            promptTemplate: """
            This is a 1-on-1 meeting. Summarize:
            1. Status updates and progress
            2. Blockers and challenges
            3. Career development discussion
            4. Action items

            Transcript:
            {{transcript}}
            """,
            outputSections: ["Status", "Blockers", "Career Development", "Action Items"],
            summaryStyle: "bullet",
            isBuiltIn: true
        ),
        AIRecipe(
            id: salesCallID,
            name: "Sales Call",
            description: "Customer needs, objections, pricing, and next steps",
            icon: "phone.arrow.up.right",
            promptTemplate: """
            This is a sales call. Extract:
            1. Customer needs and pain points
            2. Objections raised
            3. Pricing discussion
            4. Agreed next steps

            Transcript:
            {{transcript}}
            """,
            outputSections: ["Customer Needs", "Objections", "Pricing", "Next Steps"],
            summaryStyle: "bullet",
            isBuiltIn: true
        ),
        AIRecipe(
            id: brainstormID,
            name: "Brainstorm",
            description: "Ideas proposed, initial screening, items to validate",
            icon: "lightbulb",
            promptTemplate: """
            This is a brainstorming session. Organize:
            1. All ideas proposed
            2. Initial screening/favorites
            3. Items needing validation
            4. Immediate next steps

            Transcript:
            {{transcript}}
            """,
            outputSections: ["Ideas", "Favorites", "To Validate", "Next Steps"],
            summaryStyle: "bullet",
            isBuiltIn: true
        ),
        AIRecipe(
            id: productReviewID,
            name: "Product Review",
            description: "Feature feedback, design opinions, technical issues, priority adjustments",
            icon: "macwindow.badge.plus",
            promptTemplate: """
            This is a product review meeting. Summarize:
            1. Feature demo feedback
            2. Design opinions
            3. Technical issues raised
            4. Priority adjustments

            Transcript:
            {{transcript}}
            """,
            outputSections: ["Feature Feedback", "Design Opinions", "Technical Issues", "Priority Changes"],
            summaryStyle: "bullet",
            isBuiltIn: true
        ),
    ]
}
