import SwiftUI
import NetCheckerTrafficCore

/// View for adding a new environment
public struct NetCheckerTrafficUI_AddEnvironmentView: View {
    let group: EnvironmentGroup

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = EnvironmentStore.shared

    @State private var name = ""
    @State private var emoji = "🌐"
    @State private var baseURL = ""
    @State private var selectedPreset: EnvironmentPresetType = .development
    @State private var headers: [String: String] = [:]
    @State private var variables: [String: String] = [:]
    @State private var sslMode: EnvironmentSSLMode = .strict
    @State private var isDefault = false
    @State private var notes = ""

    @State private var showingEmojiPicker = false
    @State private var showingHeaderPresets = false

    public init(group: EnvironmentGroup) {
        self.group = group
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

                Picker("Type", selection: $selectedPreset) {
                    ForEach(EnvironmentPresetType.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .onChange(of: selectedPreset) { newValue in
                    applyPreset(newValue)
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
                if !baseURL.isEmpty && !isValidURL {
                    Text("Please enter a valid URL")
                        .foregroundColor(.red)
                } else {
                    Text("e.g., https://staging.api.example.com")
                }
            }

            // SSL Mode section
            Section("SSL Trust Mode") {
                Picker("SSL Mode", selection: $sslMode) {
                    ForEach(EnvironmentSSLMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
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
            } footer: {
                Text("Headers will be added to all requests when this environment is active")
            }

            // Variables section
            Section {
                EditableVariablesView(variables: $variables)
            } header: {
                Text("Variables")
            } footer: {
                Text("Access via env(\"key\") in your code")
            }

            // Notes section
            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 60)
            }

            // Quick Setup section
            Section("Quick Setup") {
                ForEach(EnvironmentPresetType.allCases, id: \.self) { preset in
                    Button {
                        applyPreset(preset)
                    } label: {
                        HStack {
                            Text(preset.defaultEmoji)
                            Text(preset.displayName)
                            Spacer()
                            if selectedPreset == preset {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
        }
        .navigationTitle("Add Environment")
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
                Button("Add") {
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
        .onAppear {
            // Apply default preset
            applyPreset(.development)
        }
    }

    private var isValidURL: Bool {
        URL(string: baseURL) != nil
    }

    private var isValid: Bool {
        !name.isEmpty && !baseURL.isEmpty && isValidURL
    }

    private func applyPreset(_ preset: EnvironmentPresetType) {
        selectedPreset = preset
        emoji = preset.defaultEmoji
        sslMode = preset.defaultSSLMode

        switch preset {
        case .production:
            name = "Production"
            isDefault = true
        case .staging:
            name = "Staging"
            isDefault = false
        case .development:
            name = "Development"
            isDefault = false
        case .local:
            name = "Local"
            if baseURL.isEmpty {
                baseURL = "http://localhost:8080"
            }
            isDefault = false
        case .custom:
            name = "Custom"
            isDefault = false
        }
    }

    private func saveEnvironment() {
        guard let url = URL(string: baseURL) else { return }

        let environment = NetCheckerTrafficCore.Environment(
            name: name,
            emoji: emoji,
            baseURL: url,
            headers: headers,
            sslTrustMode: sslMode,
            isDefault: isDefault,
            variables: variables,
            notes: notes.isEmpty ? nil : notes
        )

        store.addEnvironment(environment, to: group.id)
        dismiss()
    }
}

// MARK: - Emoji Picker

struct EmojiPickerView: View {
    @Binding var selectedEmoji: String
    @SwiftUI.Environment(\.dismiss) private var dismiss

    private let environmentEmojis = [
        "🚀", "🔧", "💻", "🏠", "⚙️", "🌐",
        "🔥", "⭐️", "🎯", "📦", "🛠️", "🔬",
        "🧪", "🔒", "🌍", "☁️", "💾", "📱",
        "🟢", "🟡", "🔴", "🟠", "🔵", "🟣"
    ]

    var body: some View {
        NavigationStack {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 44))
            ], spacing: 12) {
                ForEach(environmentEmojis, id: \.self) { emoji in
                    Button {
                        selectedEmoji = emoji
                        dismiss()
                    } label: {
                        Text(emoji)
                            .font(.largeTitle)
                            .padding(8)
                            .background(
                                selectedEmoji == emoji
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear
                            )
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .navigationTitle("Choose Emoji")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        NetCheckerTrafficUI_AddEnvironmentView(
            group: EnvironmentGroup(name: "API", sourcePattern: "api.example.com")
        )
    }
}
