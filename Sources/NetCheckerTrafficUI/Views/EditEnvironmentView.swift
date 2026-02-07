import SwiftUI
import NetCheckerTrafficCore

/// View for editing an existing environment
public struct EditEnvironmentView: View {
    let groupId: UUID
    let environment: NetCheckerTrafficCore.Environment

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = EnvironmentStore.shared

    @State private var name: String
    @State private var emoji: String
    @State private var baseURL: String
    @State private var headers: [String: String]
    @State private var variables: [String: String]
    @State private var sslMode: EnvironmentSSLMode
    @State private var isDefault: Bool
    @State private var notes: String

    @State private var showingEmojiPicker = false
    @State private var showingHeaderPresets = false
    @State private var showingDeleteConfirmation = false

    public init(groupId: UUID, environment: NetCheckerTrafficCore.Environment) {
        self.groupId = groupId
        self.environment = environment

        _name = State(initialValue: environment.name)
        _emoji = State(initialValue: environment.emoji)
        _baseURL = State(initialValue: environment.baseURL.absoluteString)
        _headers = State(initialValue: environment.headers)
        _variables = State(initialValue: environment.variables)
        _sslMode = State(initialValue: environment.sslTrustMode)
        _isDefault = State(initialValue: environment.isDefault)
        _notes = State(initialValue: environment.notes ?? "")
    }

    public var body: some View {
        Form {
            // Basic info section
            Section("Basic Info") {
                HStack {
                    Button {
                        showingEmojiPicker = true
                    } label: {
                        Text(emoji)
                            .font(.title)
                    }
                    .buttonStyle(.plain)

                    TextField("Environment Name", text: $name)
                }

                Toggle("Default Environment", isOn: $isDefault)
            }

            // URL Configuration section
            Section {
                #if os(iOS)
                TextField("Base URL", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                #else
                TextField("Base URL", text: $baseURL)
                    .autocorrectionDisabled()
                #endif
            } header: {
                Text("Base URL")
            } footer: {
                if !isValidURL {
                    Text("Please enter a valid URL")
                        .foregroundColor(.red)
                }
            }

            // SSL Mode section
            Section("SSL Trust Mode") {
                Picker("SSL Mode", selection: $sslMode) {
                    ForEach(EnvironmentSSLMode.allCases, id: \.self) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.displayName)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Text(sslMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Headers section
            Section {
                EditableHeadersView(headers: $headers)

                Button {
                    showingHeaderPresets = true
                } label: {
                    Label("Add from Presets", systemImage: "list.bullet")
                }
            } header: {
                HStack {
                    Text("Headers")
                    Spacer()
                    if !headers.isEmpty {
                        Text("\(headers.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Variables section
            Section {
                EditableVariablesView(variables: $variables)
            } header: {
                HStack {
                    Text("Variables")
                    Spacer()
                    if !variables.isEmpty {
                        Text("\(variables.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } footer: {
                Text("Variables can be accessed via env(\"key\") in your code")
            }

            // Notes section
            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 60)
            }

            // Info section
            Section("Info") {
                LabeledContent("Created") {
                    Text(environment.createdAt, style: .date)
                        .foregroundColor(.secondary)
                }
                LabeledContent("Modified") {
                    Text(environment.modifiedAt, style: .relative)
                        .foregroundColor(.secondary)
                }
            }

            // Delete section
            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Delete Environment")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Edit Environment")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveEnvironment()
                }
                .disabled(!isValid)
            }
        }
        .sheet(isPresented: $showingEmojiPicker) {
            EmojiPickerView(selectedEmoji: $emoji)
        }
        .sheet(isPresented: $showingHeaderPresets) {
            HeaderPresetsView(headers: $headers)
        }
        .alert("Delete Environment?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteEnvironment()
            }
        } message: {
            Text("This will permanently delete \"\(environment.name)\". This action cannot be undone.")
        }
    }

    private var isValidURL: Bool {
        URL(string: baseURL) != nil
    }

    private var isValid: Bool {
        !name.isEmpty && !baseURL.isEmpty && isValidURL
    }

    private func saveEnvironment() {
        guard let url = URL(string: baseURL) else { return }

        var updated = environment
        updated.name = name
        updated.emoji = emoji
        updated.baseURL = url
        updated.headers = headers
        updated.variables = variables
        updated.sslTrustMode = sslMode
        updated.isDefault = isDefault
        updated.notes = notes.isEmpty ? nil : notes

        store.updateEnvironment(updated, in: groupId)
        dismiss()
    }

    private func deleteEnvironment() {
        store.removeEnvironment(environment.id, from: groupId)
        dismiss()
    }
}

// MARK: - Editable Variables View

struct EditableVariablesView: View {
    @Binding var variables: [String: String]

    @State private var entries: [(id: UUID, key: String, value: String)] = []
    @State private var newKey = ""
    @State private var newValue = ""

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries, id: \.id) { entry in
                HStack(spacing: 8) {
                    Text(entry.key)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)

                    Text("=")
                        .foregroundColor(.secondary)

                    Text(entry.value)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        deleteEntry(id: entry.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }

            // Add new variable
            HStack(spacing: 8) {
                TextField("Key", text: $newKey)
                    .font(.system(.caption, design: .monospaced))
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                Text("=")
                    .foregroundColor(.secondary)

                TextField("Value", text: $newValue)
                    .font(.system(.caption, design: .monospaced))
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                Button {
                    addNewVariable()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.vertical, 4)
        }
        .onAppear {
            loadEntries()
        }
    }

    private func loadEntries() {
        entries = variables.map { (UUID(), $0.key, $0.value) }
            .sorted { $0.key < $1.key }
    }

    private func syncToVariables() {
        var result: [String: String] = [:]
        for entry in entries {
            let key = entry.key.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                result[key] = entry.value
            }
        }
        variables = result
    }

    private func addNewVariable() {
        let key = newKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }

        entries.append((UUID(), key, newValue))
        newKey = ""
        newValue = ""
        syncToVariables()
    }

    private func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        syncToVariables()
    }
}

#Preview {
    NavigationStack {
        EditEnvironmentView(
            groupId: UUID(),
            environment: NetCheckerTrafficCore.Environment(
                name: "Staging",
                emoji: "🔧",
                baseURL: URL(string: "https://staging.api.example.com")!,
                headers: ["Authorization": "Bearer token123"],
                variables: ["API_KEY": "test123"]
            )
        )
    }
}
