import Foundation
import Testing
@testable import notetaker

@Suite("RecipeStore Tests")
struct RecipeStoreTests {

    // MARK: - Built-in Recipes

    @Test func builtInRecipesCount() {
        #expect(RecipeStore.builtInRecipes.count == 6)
    }

    @Test func builtInRecipesAreAllMarkedBuiltIn() {
        for recipe in RecipeStore.builtInRecipes {
            #expect(recipe.isBuiltIn == true, "Recipe \(recipe.name) should be built-in")
        }
    }

    @Test func builtInRecipesHaveUniqueIDs() {
        let ids = RecipeStore.builtInRecipes.map(\.id)
        #expect(Set(ids).count == ids.count, "Built-in recipe IDs should be unique")
    }

    @Test func builtInRecipesHaveNonEmptyFields() {
        for recipe in RecipeStore.builtInRecipes {
            #expect(!recipe.name.isEmpty)
            #expect(!recipe.description.isEmpty)
            #expect(!recipe.icon.isEmpty)
            #expect(!recipe.promptTemplate.isEmpty)
            #expect(!recipe.outputSections.isEmpty)
            #expect(!recipe.summaryStyle.isEmpty)
        }
    }

    // MARK: - Template Interpolation

    @Test func interpolateAllVariables() {
        let template = "Title: {{title}}, Duration: {{duration}}, Date: {{date}}\n{{transcript}}"
        let vars = [
            "title": "Test Meeting",
            "duration": "30m",
            "date": "2026-01-01",
            "transcript": "Hello world",
        ]
        let result = RecipeStore.interpolate(template: template, vars: vars)
        #expect(result == "Title: Test Meeting, Duration: 30m, Date: 2026-01-01\nHello world")
    }

    @Test func interpolateMissingVariablesLeftAsIs() {
        let template = "{{title}} and {{unknown}}"
        let result = RecipeStore.interpolate(template: template, vars: ["title": "Test"])
        #expect(result == "Test and {{unknown}}")
    }

    @Test func interpolateEmptyTemplate() {
        let result = RecipeStore.interpolate(template: "", vars: ["title": "Test"])
        #expect(result == "")
    }

    @Test func interpolateEmptyVars() {
        let template = "Hello {{name}}"
        let result = RecipeStore.interpolate(template: template, vars: [:])
        #expect(result == "Hello {{name}}")
    }

    @Test func interpolateMultipleOccurrences() {
        let template = "{{name}} said hi to {{name}}"
        let result = RecipeStore.interpolate(template: template, vars: ["name": "Alice"])
        #expect(result == "Alice said hi to Alice")
    }

    // MARK: - JSON Round-Trip

    @Test func jsonRoundTrip() throws {
        let recipe = AIRecipe(
            name: "Test",
            description: "A test recipe",
            icon: "star",
            promptTemplate: "{{transcript}}",
            outputSections: ["A", "B"],
            summaryStyle: "paragraph"
        )

        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(AIRecipe.self, from: data)

        #expect(decoded.id == recipe.id)
        #expect(decoded.name == recipe.name)
        #expect(decoded.description == recipe.description)
        #expect(decoded.icon == recipe.icon)
        #expect(decoded.promptTemplate == recipe.promptTemplate)
        #expect(decoded.outputSections == recipe.outputSections)
        #expect(decoded.summaryStyle == recipe.summaryStyle)
        #expect(decoded.isBuiltIn == recipe.isBuiltIn)
    }

    @Test func jsonRoundTripArray() throws {
        let recipes = RecipeStore.builtInRecipes
        let data = try JSONEncoder().encode(recipes)
        let decoded = try JSONDecoder().decode([AIRecipe].self, from: data)
        #expect(decoded.count == recipes.count)
        for (original, decoded) in zip(recipes, decoded) {
            #expect(original.id == decoded.id)
            #expect(original.name == decoded.name)
        }
    }

    // MARK: - Load/Save with Temp File

    @Test func loadRecipesReturnsBuiltInsOnFirstLoad() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_recipes_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let loaded = RecipeStore.loadRecipes(from: tempURL)
        #expect(loaded.count == RecipeStore.builtInRecipes.count)
        for recipe in loaded {
            #expect(recipe.isBuiltIn == true)
        }
    }

    @Test func saveAndLoadRoundTrip() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_recipes_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var recipes = RecipeStore.builtInRecipes
        let custom = AIRecipe(
            name: "Custom",
            description: "My recipe",
            icon: "star",
            promptTemplate: "{{transcript}}"
        )
        recipes.append(custom)

        RecipeStore.saveRecipes(recipes, to: tempURL)
        let loaded = RecipeStore.loadRecipes(from: tempURL)

        #expect(loaded.count == RecipeStore.builtInRecipes.count + 1)
        #expect(loaded.contains(where: { $0.id == custom.id }))
    }

    @Test func loadMergesMissingBuiltIns() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_recipes_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Save only one built-in
        let partial = [RecipeStore.builtInRecipes[0]]
        RecipeStore.saveRecipes(partial, to: tempURL)

        let loaded = RecipeStore.loadRecipes(from: tempURL)
        // All built-ins should be restored
        #expect(loaded.count == RecipeStore.builtInRecipes.count)
    }

    // MARK: - Delete

    @Test func deleteRecipeRemovesUserRecipe() {
        var recipes = RecipeStore.builtInRecipes
        let custom = AIRecipe(
            name: "Custom",
            description: "Deletable",
            icon: "star",
            promptTemplate: "{{transcript}}"
        )
        recipes.append(custom)

        RecipeStore.deleteRecipe(id: custom.id, from: &recipes)
        #expect(!recipes.contains(where: { $0.id == custom.id }))
    }

    @Test func deleteRecipeDoesNotDeleteBuiltIn() {
        var recipes = RecipeStore.builtInRecipes
        let builtInID = recipes[0].id
        RecipeStore.deleteRecipe(id: builtInID, from: &recipes)
        #expect(recipes.contains(where: { $0.id == builtInID }))
    }

    // MARK: - Duplicate

    @Test func duplicateCreatesUserOwnedCopy() {
        let original = RecipeStore.builtInRecipes[0]
        let copy = RecipeStore.duplicate(original)

        #expect(copy.id != original.id)
        #expect(copy.name == "\(original.name) (Copy)")
        #expect(copy.isBuiltIn == false)
        #expect(copy.promptTemplate == original.promptTemplate)
        #expect(copy.outputSections == original.outputSections)
    }

    // MARK: - Hashable / Equatable

    @Test func hashableConformance() {
        let recipe = RecipeStore.builtInRecipes[0]
        var set = Set<AIRecipe>()
        set.insert(recipe)
        #expect(set.contains(recipe))
    }

    // MARK: - AIRecipe Defaults

    @Test func defaultInitValues() {
        let recipe = AIRecipe(
            name: "Test",
            description: "Desc",
            icon: "star",
            promptTemplate: "template"
        )
        #expect(recipe.outputSections.isEmpty)
        #expect(recipe.summaryStyle == "bullet")
        #expect(recipe.isBuiltIn == false)
    }
}
