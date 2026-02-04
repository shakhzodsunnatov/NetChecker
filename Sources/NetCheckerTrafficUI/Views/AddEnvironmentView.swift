import SwiftUI
import NetCheckerTrafficCore

/// Preset types for environment configuration
enum EnvironmentPreset: String, CaseIterable {
    case production
    case staging
    case development
    case local
    case custom
}

/// View for adding a new environment
public struct NetCheckerTrafficUI_AddEnvironmentView: View {
    let group: EnvironmentGroup

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = EnvironmentStore.shared

    @State private var name = ""
    @State private var emoji = "🌐"
    @State private var baseURL = ""
    @State private var selectedPreset: EnvironmentPreset = .development
    @State private var headers: [String: String] = [:]
    @State private var showingEmojiPicker = false

    public init(group: EnvironmentGroup) {
        self.group = group
    }

    public var body: some View {
        Form {
            // Basic info
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
                    ForEach(EnvironmentPreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue.capitalized).tag(preset)
                    }
                }
            }

            // URL Configuration
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
                Text("URL")
            } footer: {
                Text("e.g., https://staging.api.example.com")
            }

            // Headers
            Section("Custom Headers") {
                EditableHeadersView(headers: $headers)
            }

            // Presets
            Section("Quick Setup") {
                Button {
                    setupPreset(.production)
                } label: {
                    Label("Production", systemImage: "flame")
                }

                Button {
                    setupPreset(.staging)
                } label: {
                    Label("Staging", systemImage: "hammer")
                }

                Button {
                    setupPreset(.development)
                } label: {
                    Label("Development", systemImage: "wrench")
                }

                Button {
                    setupPreset(.local)
                } label: {
                    Label("Local", systemImage: "laptopcomputer")
                }
            }
        }
        .navigationTitle("Add Environment")
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
    }

    private var isValid: Bool {
        !name.isEmpty && !baseURL.isEmpty && URL(string: baseURL) != nil
    }

    private func setupPreset(_ preset: EnvironmentPreset) {
        selectedPreset = preset

        switch preset {
        case .production:
            name = "Production"
            emoji = "🚀"
        case .staging:
            name = "Staging"
            emoji = "🔧"
        case .development:
            name = "Development"
            emoji = "💻"
        case .local:
            name = "Local"
            emoji = "🏠"
            baseURL = "http://localhost:8080"
        case .custom:
            name = "Custom"
            emoji = "⚙️"
        }
    }

    private func saveEnvironment() {
        guard let url = URL(string: baseURL) else { return }

        let environment = NetCheckerTrafficCore.Environment(
            name: name,
            emoji: emoji,
            baseURL: url,
            headers: headers
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
        "🧪", "🔒", "🌍", "☁️", "💾", "📱"
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
