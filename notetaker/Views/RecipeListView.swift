import SwiftUI
import os

/// Settings tab for managing AI Recipes (custom prompt templates).
struct RecipeListView: View {
    @State private var recipes: [AIRecipe] = []
    @State private var selectedRecipeID: UUID?
    @State private var isEditing = false

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "RecipeListView"
    )

    var body: some View {
        HSplitView {
            // Sidebar: recipe list
            VStack(spacing: 0) {
                List(selection: $selectedRecipeID) {
                    ForEach(recipes) { recipe in
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: recipe.icon)
                                .frame(width: 20)
                                .foregroundStyle(recipe.isBuiltIn ? .secondary : .primary)
                            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                                Text(recipe.name)
                                    .font(DS.Typography.body)
                                Text(recipe.description)
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if recipe.isBuiltIn {
                                Text("Built-in")
                                    .font(DS.Typography.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .tag(recipe.id)
                    }
                }
                .listStyle(.sidebar)

                // Bottom toolbar
                HStack(spacing: DS.Spacing.sm) {
                    Button {
                        addNewRecipe()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add new recipe")

                    if let selected = selectedRecipe {
                        Button {
                            duplicateRecipe(selected)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .help("Duplicate recipe")

                        Button {
                            deleteSelectedRecipe()
                        } label: {
                            Image(systemName: "minus")
                        }
                        .disabled(selected.isBuiltIn)
                        .help(selected.isBuiltIn ? "Built-in recipes cannot be deleted" : "Delete recipe")
                    }

                    Spacer()
                }
                .padding(DS.Spacing.sm)
                .buttonStyle(.plain)
            }
            .frame(minWidth: 200, idealWidth: 220)

            // Detail: recipe editor
            if let selected = selectedRecipe {
                RecipeEditorView(
                    recipe: Binding(
                        get: { selected },
                        set: { updated in
                            updateRecipe(updated)
                        }
                    )
                )
            } else {
                VStack {
                    Spacer()
                    Text("Select a recipe to edit")
                        .foregroundStyle(.secondary)
                        .font(DS.Typography.body)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            recipes = RecipeStore.loadRecipes()
            if selectedRecipeID == nil {
                selectedRecipeID = recipes.first?.id
            }
        }
    }

    // MARK: - Helpers

    private var selectedRecipe: AIRecipe? {
        recipes.first { $0.id == selectedRecipeID }
    }

    private func addNewRecipe() {
        let recipe = AIRecipe(
            name: "New Recipe",
            description: "Describe what this recipe does",
            icon: "doc.text",
            promptTemplate: "Summarize this transcript:\n\n{{transcript}}",
            outputSections: [],
            summaryStyle: "bullet"
        )
        recipes.append(recipe)
        selectedRecipeID = recipe.id
        save()
        Self.logger.info("Added new recipe: \(recipe.id)")
    }

    private func duplicateRecipe(_ recipe: AIRecipe) {
        let copy = RecipeStore.duplicate(recipe)
        recipes.append(copy)
        selectedRecipeID = copy.id
        save()
        Self.logger.info("Duplicated recipe \(recipe.name) as \(copy.id)")
    }

    private func deleteSelectedRecipe() {
        guard let id = selectedRecipeID else { return }
        RecipeStore.deleteRecipe(id: id, from: &recipes)
        selectedRecipeID = recipes.first?.id
        save()
    }

    private func updateRecipe(_ updated: AIRecipe) {
        if let index = recipes.firstIndex(where: { $0.id == updated.id }) {
            var modified = updated
            modified.updatedAt = Date()
            recipes[index] = modified
            save()
        }
    }

    private func save() {
        RecipeStore.saveRecipes(recipes)
    }
}

// MARK: - Recipe Editor

struct RecipeEditorView: View {
    @Binding var recipe: AIRecipe
    @State private var sectionsText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                // Name and icon
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: recipe.icon)
                        .font(.title2)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        TextField("Recipe Name", text: $recipe.name)
                            .font(DS.Typography.sectionHeader)
                            .textFieldStyle(.plain)

                        TextField("Description", text: $recipe.description)
                            .font(DS.Typography.callout)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(recipe.isBuiltIn)

                Divider()

                // Icon picker
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Icon (SF Symbol)")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                    TextField("SF Symbol name", text: $recipe.icon)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
                .disabled(recipe.isBuiltIn)

                // Summary style
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Summary Style")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $recipe.summaryStyle) {
                        Text("Bullet Points").tag("bullet")
                        Text("Paragraph").tag("paragraph")
                        Text("Action Items").tag("actionItems")
                        Text("Lecture Notes").tag("lectureNotes")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .disabled(recipe.isBuiltIn)

                // Output sections
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Output Sections (comma-separated)")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. Action Items, Decisions, Follow-ups", text: $sectionsText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: sectionsText) {
                            recipe.outputSections = sectionsText
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }
                }
                .disabled(recipe.isBuiltIn)

                // Prompt template
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Prompt Template")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)

                    Text("Variables: {{transcript}}, {{title}}, {{duration}}, {{date}}")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(.tertiary)

                    TextEditor(text: $recipe.promptTemplate)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                        .scrollContentBackground(.hidden)
                        .padding(DS.Spacing.xs)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                }
                .disabled(recipe.isBuiltIn)

                if recipe.isBuiltIn {
                    Text("Built-in recipes are read-only. Duplicate to customize.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(DS.Spacing.lg)
        }
        .onAppear {
            sectionsText = recipe.outputSections.joined(separator: ", ")
        }
        .onChange(of: recipe.id) {
            sectionsText = recipe.outputSections.joined(separator: ", ")
        }
    }
}
