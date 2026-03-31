import SwiftUI
import SwiftData

/// Form for creating or editing a `ScheduledRecording`.
struct ScheduleEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var schedulerViewModel: SchedulerViewModel
    var existing: ScheduledRecording? = nil

    // Form state
    @State private var title: String = ""
    @State private var label: String = ""
    @State private var startTime: Date = Date().addingTimeInterval(3600) // 1 hour from now
    @State private var hasDuration: Bool = false
    @State private var durationMinutes: Int = 60
    @State private var repeatRule: RepeatRule = .once
    @State private var reminderMinutes: Int = 1
    @State private var isEnabled: Bool = true

    // Existing labels for suggestion
    @Query private var allRecordings: [ScheduledRecording]
    private var existingLabels: [String] {
        Array(Set(allRecordings.compactMap { $0.label.isEmpty ? nil : $0.label })).sorted()
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        Form {
            Section("Recording") {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                LabelPicker(label: $label, existingLabels: existingLabels)
            }

            Section("Schedule") {
                DatePicker("Start time", selection: $startTime, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                Picker("Repeat", selection: $repeatRule) {
                    ForEach(RepeatRule.allCases) { rule in
                        Text(rule.displayName).tag(rule)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Duration") {
                Toggle("Limit recording duration", isOn: $hasDuration)
                if hasDuration {
                    Stepper("\(durationMinutes) minutes", value: $durationMinutes, in: 1...480, step: 5)
                }
            }

            Section("Reminder") {
                Picker("Remind me", selection: $reminderMinutes) {
                    Text("None").tag(0)
                    Text("1 minute before").tag(1)
                    Text("5 minutes before").tag(5)
                    Text("10 minutes before").tag(10)
                    Text("15 minutes before").tag(15)
                }
                .pickerStyle(.menu)
            }

            Section {
                Toggle("Enabled", isOn: $isEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 340)
        .navigationTitle(isEditing ? "Edit Schedule" : "New Schedule")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Add") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { populateIfEditing() }
    }

    // MARK: - Private

    private func populateIfEditing() {
        guard let r = existing else { return }
        title = r.title
        label = r.label
        startTime = r.startTime
        hasDuration = r.durationMinutes != nil
        durationMinutes = r.durationMinutes ?? 60
        repeatRule = r.rule
        reminderMinutes = r.reminderMinutes
        isEnabled = r.isEnabled
    }

    private func save() {
        let recording = existing ?? ScheduledRecording()
        recording.title = title.trimmingCharacters(in: .whitespaces)
        recording.label = label.trimmingCharacters(in: .whitespaces)
        recording.startTime = startTime
        recording.durationMinutes = hasDuration ? durationMinutes : nil
        recording.repeatRule = repeatRule.rawValue
        recording.reminderMinutes = reminderMinutes
        recording.isEnabled = isEnabled

        schedulerViewModel.save(recording, context: modelContext)
        dismiss()
    }
}

// MARK: - Label Picker

private struct LabelPicker: View {
    @Binding var label: String
    let existingLabels: [String]
    @State private var showSuggestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                TextField("Group label (optional)", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: label) { _, _ in showSuggestions = !label.isEmpty }
                if !existingLabels.isEmpty {
                    Button {
                        showSuggestions.toggle()
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show label suggestions")
                }
            }
            if showSuggestions && !existingLabels.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    ForEach(existingLabels.filter { label.isEmpty || $0.localizedCaseInsensitiveContains(label) }, id: \.self) { suggestion in
                        Button {
                            label = suggestion
                            showSuggestions = false
                        } label: {
                            Text(suggestion)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, DS.Spacing.xxs)
                                .padding(.horizontal, DS.Spacing.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm).stroke(.separator, lineWidth: 1))
            }
        }
    }
}
