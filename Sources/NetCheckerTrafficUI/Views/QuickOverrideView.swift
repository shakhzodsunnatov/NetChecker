import SwiftUI
import NetCheckerTrafficCore

/// View for quick URL override
public struct NetCheckerTrafficUI_QuickOverrideView: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = EnvironmentStore.shared

    @State private var urlString = ""
    @State private var selectedPreset: QuickPreset?
    @State private var showingHistory = false

    public init() {}

    enum QuickPreset: String, CaseIterable {
        case localhost = "Localhost"
        case localhost8080 = "Localhost:8080"
        case staging = "Staging"

        var url: String {
            switch self {
            case .localhost: return "http://localhost"
            case .localhost8080: return "http://localhost:8080"
            case .staging: return "https://staging."
            }
        }
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Current override
                if let currentOverride = store.quickOverrideURL {
                    Section("Current Override") {
                        HStack {
                            Text(currentOverride.absoluteString)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(2)

                            Spacer()

                            Button("Clear") {
                                store.clearQuickOverride()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                // URL Input
                Section {
                    #if os(iOS)
                    TextField("https://staging.api.example.com", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    #else
                    TextField("https://staging.api.example.com", text: $urlString)
                        .autocorrectionDisabled()
                    #endif
                } header: {
                    Text("Override URL")
                } footer: {
                    Text("All requests matching the original host will be redirected to this URL")
                }

                // Quick presets
                Section("Quick Presets") {
                    ForEach(QuickPreset.allCases, id: \.self) { preset in
                        Button {
                            urlString = preset.url
                            selectedPreset = preset
                        } label: {
                            HStack {
                                Text(preset.rawValue)
                                Spacer()
                                Text(preset.url)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Recent overrides
                if !store.quickOverrides.isEmpty {
                    Section("Recent") {
                        ForEach(Array(store.quickOverrides.values), id: \.sourceHost) { override in
                            Button {
                                urlString = override.targetHost
                            } label: {
                                Text(override.targetHost)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Quick Override")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyOverride()
                    }
                    .disabled(!isValidURL)
                }
            }
        }
    }

    private var isValidURL: Bool {
        URL(string: urlString) != nil
    }

    private func applyOverride() {
        guard let url = URL(string: urlString),
              let host = url.host else { return }
        store.addQuickOverride(from: host, to: urlString)
        dismiss()
    }
}

// MARK: - Quick Override Banner

public struct QuickOverrideBanner: View {
    @ObservedObject private var store = EnvironmentStore.shared

    public init() {}

    public var body: some View {
        if let override = store.quickOverrideURL {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Override Active")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(override.absoluteString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    store.clearQuickOverride()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
        }
    }
}

#Preview {
    NetCheckerTrafficUI_QuickOverrideView()
}
