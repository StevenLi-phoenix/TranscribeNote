import SwiftUI
import os

// MARK: - Models

struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String  // SF Symbol
    let shortcut: String?  // Display string like "⌘R"
    let category: CommandCategory
    let action: () -> Void
}

enum CommandCategory: String, CaseIterable {
    case recording = "Recording"
    case playback = "Playback"
    case session = "Session"
    case export = "Export"
    case navigation = "Navigation"

    var displayName: String {
        switch self {
        case .recording: String(localized: "Recording")
        case .playback: String(localized: "Playback")
        case .session: String(localized: "Session")
        case .export: String(localized: "Export")
        case .navigation: String(localized: "Navigation")
        }
    }
}

// MARK: - Search Logic (testable)

enum CommandPaletteSearch {
    /// Fuzzy filter: case-insensitive, all query words must appear in title.
    static func filter(commands: [PaletteCommand], query: String) -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return commands }

        let queryWords = trimmed.lowercased().split(separator: " ").map(String.init)
        return commands.filter { command in
            let titleLower = command.title.lowercased()
            return queryWords.allSatisfy { titleLower.contains($0) }
        }
    }

    /// Group filtered commands by category, preserving `CaseIterable` order.
    static func grouped(commands: [PaletteCommand]) -> [(category: CommandCategory, commands: [PaletteCommand])] {
        var result: [(category: CommandCategory, commands: [PaletteCommand])] = []
        for category in CommandCategory.allCases {
            let matching = commands.filter { $0.category == category }
            if !matching.isEmpty {
                result.append((category: category, commands: matching))
            }
        }
        return result
    }
}

// MARK: - View

struct CommandPaletteView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "CommandPalette")

    let commands: [PaletteCommand]
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var filtered: [PaletteCommand] {
        CommandPaletteSearch.filter(commands: commands, query: query)
    }

    private var grouped: [(category: CommandCategory, commands: [PaletteCommand])] {
        CommandPaletteSearch.grouped(commands: filtered)
    }

    /// Flat list of commands in display order for keyboard navigation.
    private var flatCommands: [PaletteCommand] {
        grouped.flatMap(\.commands)
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
                .accessibilityLabel("Dismiss command palette")

            VStack(spacing: 0) {
                // Search field
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Type a command…", text: $query)
                        .textFieldStyle(.plain)
                        .font(DS.Typography.body)
                        .focused($isSearchFocused)
                        .accessibilityLabel("Command search")
                        .onSubmit { executeSelected() }
                }
                .padding(DS.Spacing.md)

                Divider()

                // Command list
                if flatCommands.isEmpty {
                    Text("No matching commands")
                        .font(DS.Typography.callout)
                        .foregroundStyle(.secondary)
                        .padding(DS.Spacing.lg)
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(grouped, id: \.category) { group in
                                    Text(group.category.displayName)
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, DS.Spacing.md)
                                        .padding(.top, DS.Spacing.sm)
                                        .padding(.bottom, DS.Spacing.xs)

                                    ForEach(group.commands) { command in
                                        commandRow(command)
                                    }
                                }
                            }
                            .padding(.bottom, DS.Spacing.sm)
                        }
                        .frame(maxHeight: 320)
                        .onChange(of: selectedIndex) { _, newIndex in
                            guard newIndex >= 0, newIndex < flatCommands.count else { return }
                            proxy.scrollTo(flatCommands[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            .frame(width: 480)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
            Self.logger.debug("Command palette opened with \(commands.count) commands")
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Subviews

    @ViewBuilder
    private func commandRow(_ command: PaletteCommand) -> some View {
        let isSelected = flatCommands.indices.contains(selectedIndex)
            && flatCommands[selectedIndex].id == command.id
        let iconColor: Color = isSelected ? .white : .secondary
        let subtitleColor: Color = isSelected ? .white.opacity(0.7) : .secondary
        let shortcutColor: Color = isSelected ? .white.opacity(0.7) : .gray
        let badgeFill: Color = isSelected ? .white.opacity(0.15) : .gray.opacity(0.1)
        let rowFill: Color = isSelected ? .accentColor : .clear
        let textColor: Color = isSelected ? .white : .primary
        let helpText: String = command.shortcut.map { "Shortcut: \($0)" } ?? command.title

        Button {
            execute(command)
        } label: {
            commandRowContent(command: command, iconColor: iconColor, subtitleColor: subtitleColor,
                              shortcutColor: shortcutColor, badgeFill: badgeFill)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(rowFill)
                    .padding(.horizontal, DS.Spacing.xs)
            )
            .foregroundStyle(textColor)
        }
        .buttonStyle(.plain)
        .id(command.id)
        .accessibilityLabel(command.title)
        .help(helpText)
    }

    @ViewBuilder
    private func commandRowContent(
        command: PaletteCommand,
        iconColor: Color,
        subtitleColor: Color,
        shortcutColor: Color,
        badgeFill: Color
    ) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: command.icon)
                .frame(width: 20)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(command.title)
                    .font(DS.Typography.body)
                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(subtitleColor)
                }
            }

            Spacer()

            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(DS.Typography.caption)
                    .foregroundStyle(shortcutColor)
                    .padding(.horizontal, DS.Spacing.xs)
                    .padding(.vertical, DS.Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.xs)
                            .fill(badgeFill)
                    )
            }
        }
    }

    // MARK: - Actions

    private func moveSelection(by delta: Int) {
        let count = flatCommands.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func executeSelected() {
        guard !flatCommands.isEmpty, selectedIndex >= 0, selectedIndex < flatCommands.count else { return }
        execute(flatCommands[selectedIndex])
    }

    private func execute(_ command: PaletteCommand) {
        Self.logger.info("Executing command: \(command.id)")
        dismiss()
        command.action()
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.15)) {
            isPresented = false
        }
    }
}
