import SwiftData
import SwiftUI

struct FilterRulesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\FilterRuleRecord.createdAt)]) private var rules: [FilterRuleRecord]

    @State private var draftForEditing: FilterRuleDraft?

    var body: some View {
        NavigationStack {
            List {
                if rules.isEmpty {
                    ContentUnavailableView(
                        "No Filter Rules",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Add your first regex rule to include or exclude events.")
                    )
                } else {
                    ForEach(rules, id: \.id) { rule in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(rule.name)
                                    .font(.headline)
                                Spacer()
                                Toggle(
                                    "Enabled",
                                    isOn: Binding(
                                        get: { rule.isEnabled },
                                        set: { newValue in
                                            rule.isEnabled = newValue
                                            saveContext()
                                        }
                                    )
                                )
                                .labelsHidden()
                            }

                            Text("`\(rule.pattern)`")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(metadataText(for: rule))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Edit") {
                                draftForEditing = FilterRuleDraft(rule: rule.asFilterRule)
                            }
                            .tint(.blue)

                            Button("Delete", role: .destructive) {
                                modelContext.delete(rule)
                                saveContext()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter Rules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        draftForEditing = FilterRuleDraft()
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $draftForEditing) { draft in
            RuleEditorView(
                initialDraft: draft,
                onSave: { savedDraft in
                    upsertRule(savedDraft)
                    draftForEditing = nil
                },
                onCancel: {
                    draftForEditing = nil
                }
            )
        }
    }

    private func upsertRule(_ draft: FilterRuleDraft) {
        if let existing = rules.first(where: { $0.id == draft.id }) {
            existing.apply(draft.asFilterRule)
        } else {
            modelContext.insert(FilterRuleRecord(rule: draft.asFilterRule))
        }

        saveContext()
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save filter rules: \(error)")
        }
    }

    private func metadataText(for rule: FilterRuleRecord) -> String {
        let mode = rule.mode == .exclude ? "Exclude" : "Include"
        let sensitivity = rule.isCaseSensitive ? "Case sensitive" : "Case insensitive"
        let targets = rule.targets
            .sorted { $0.rawValue < $1.rawValue }
            .map { $0.rawValue.capitalized }
            .joined(separator: ", ")

        return "\(mode) • \(sensitivity) • \(targets)"
    }
}

private struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: FilterRuleDraft
    let onSave: (FilterRuleDraft) -> Void
    let onCancel: () -> Void

    init(initialDraft: FilterRuleDraft, onSave: @escaping (FilterRuleDraft) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: initialDraft)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rule") {
                    TextField("Name", text: $draft.name)
                    TextField("Regex pattern", text: $draft.pattern)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let errorMessage = regexValidationError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Behavior") {
                    Picker("Mode", selection: $draft.mode) {
                        Text("Exclude matches").tag(FilterMode.exclude)
                        Text("Include matches").tag(FilterMode.include)
                    }

                    Toggle("Enabled", isOn: $draft.isEnabled)
                    Toggle("Case sensitive", isOn: $draft.isCaseSensitive)
                }

                Section("Apply to fields") {
                    targetToggle(.title, label: "Title")
                    targetToggle(.notes, label: "Notes")
                    targetToggle(.location, label: "Location")
                    targetToggle(.calendar, label: "Calendar name")
                }
            }
            .navigationTitle(draft.isNew ? "New Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.pattern.isEmpty
            && regexValidationError == nil
            && !draft.targets.isEmpty
    }

    private var regexValidationError: String? {
        guard !draft.pattern.isEmpty else {
            return "Pattern cannot be empty."
        }

        let options: NSRegularExpression.Options = draft.isCaseSensitive ? [] : [.caseInsensitive]
        if (try? NSRegularExpression(pattern: draft.pattern, options: options)) == nil {
            return "Invalid regular expression pattern."
        }

        return nil
    }

    private func targetToggle(_ target: FilterTarget, label: String) -> some View {
        Toggle(
            label,
            isOn: Binding(
                get: { draft.targets.contains(target) },
                set: { isOn in
                    if isOn {
                        draft.targets.insert(target)
                    } else if draft.targets.count > 1 {
                        draft.targets.remove(target)
                    }
                }
            )
        )
    }
}

private struct FilterRuleDraft: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var pattern: String = ""
    var isEnabled: Bool = true
    var mode: FilterMode = .exclude
    var isCaseSensitive: Bool = false
    var targets: Set<FilterTarget> = [.title]

    var isNew: Bool = true

    init() {}

    init(rule: FilterRule) {
        id = rule.id
        name = rule.name
        pattern = rule.pattern
        isEnabled = rule.isEnabled
        mode = rule.mode
        isCaseSensitive = rule.isCaseSensitive
        targets = rule.targets
        isNew = false
    }

    var asFilterRule: FilterRule {
        FilterRule(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            pattern: pattern,
            isEnabled: isEnabled,
            mode: mode,
            isCaseSensitive: isCaseSensitive,
            targets: targets
        )
    }
}
