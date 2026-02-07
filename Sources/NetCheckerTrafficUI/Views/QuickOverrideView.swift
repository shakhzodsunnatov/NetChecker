import SwiftUI
import NetCheckerTrafficCore

/// View for quick URL override
public struct NetCheckerTrafficUI_QuickOverrideView: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = EnvironmentStore.shared

    @State private var sourceHost = ""
    @State private var targetURL = ""
    @State private var selectedPreset: QuickPreset?
    @State private var autoDisable = false
    @State private var autoDisableMinutes = 30

    public init() {}

    enum QuickPreset: String, CaseIterable {
        case localhost = "Localhost"
        case localhost8080 = "Localhost:8080"
        case localhost3000 = "Localhost:3000"

        var url: String {
            switch self {
            case .localhost: return "http://localhost"
            case .localhost8080: return "http://localhost:8080"
            case .localhost3000: return "http://localhost:3000"
            }
        }
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Current overrides section
                if !store.quickOverrides.isEmpty {
                    Section("Active Overrides") {
                        ForEach(Array(store.quickOverrides.values), id: \.sourceHost) { override in
                            OverrideRow(override: override) {
                                store.removeQuickOverride(for: override.sourceHost)
                            }
                        }
                    }
                }

                // Source host section
                Section {
                    #if os(iOS)
                    TextField("api.example.com", text: $sourceHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    #else
                    TextField("api.example.com", text: $sourceHost)
                        .autocorrectionDisabled()
                    #endif
                } header: {
                    Text("Source Host")
                } footer: {
                    Text("The host to intercept and redirect")
                }

                // Target URL section
                Section {
                    #if os(iOS)
                    TextField("http://localhost:8080", text: $targetURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    #else
                    TextField("http://localhost:8080", text: $targetURL)
                        .autocorrectionDisabled()
                    #endif
                } header: {
                    Text("Target URL")
                } footer: {
                    Text("All requests to source host will be redirected here")
                }

                // Auto-disable section
                Section {
                    Toggle("Auto-disable", isOn: $autoDisable)

                    if autoDisable {
                        Picker("After", selection: $autoDisableMinutes) {
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("1 hour").tag(60)
                            Text("2 hours").tag(120)
                        }
                    }
                } footer: {
                    if autoDisable {
                        Text("Override will automatically be removed after \(autoDisableMinutes) minutes")
                    }
                }

                // Quick presets section
                Section("Quick Presets") {
                    ForEach(QuickPreset.allCases, id: \.self) { preset in
                        Button {
                            targetURL = preset.url
                            selectedPreset = preset
                        } label: {
                            HStack {
                                Text(preset.rawValue)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(preset.url)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if selectedPreset == preset {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Quick Override")
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
                    Button("Apply") {
                        applyOverride()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !sourceHost.trimmingCharacters(in: .whitespaces).isEmpty &&
        !targetURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        URL(string: targetURL) != nil
    }

    private func applyOverride() {
        let timeout: TimeInterval? = autoDisable ? TimeInterval(autoDisableMinutes * 60) : nil
        store.addQuickOverride(from: sourceHost, to: targetURL, autoDisableAfter: timeout)
        dismiss()
    }
}

// MARK: - Override Row

struct OverrideRow: View {
    let override: QuickOverride
    let onRemove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(override.sourceHost)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(override.targetHost)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let expiresAt = override.expiresAt {
                    Text("Expires: \(expiresAt, style: .relative)")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Quick Override Banner

public struct QuickOverrideBanner: View {
    @ObservedObject private var store = EnvironmentStore.shared

    public init() {}

    public var body: some View {
        if let override = store.quickOverrides.values.first {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Override Active")
                        .font(.caption)
                        .fontWeight(.medium)

                    Text("\(override.sourceHost) -> \(override.targetHost)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    store.clearQuickOverrides()
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
