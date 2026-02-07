import SwiftUI
import NetCheckerTrafficCore

/// Table view displaying HTTP headers
public struct NetCheckerTrafficUI_HeadersTableView: View {
    let headers: [String: String]
    let title: String?
    let showSearch: Bool

    @State private var searchText = ""
    @State private var selectedHeader: String?

    public init(
        headers: [String: String],
        title: String? = nil,
        showSearch: Bool = true
    ) {
        self.headers = headers
        self.title = title
        self.showSearch = showSearch
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title)
                    .font(.headline)
            }

            if showSearch && headers.count > 5 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search headers", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(8)
            }

            if filteredHeaders.isEmpty {
                Text("No headers")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding()
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedKeys, id: \.self) { key in
                        HeaderRow(
                            key: key,
                            value: filteredHeaders[key] ?? "",
                            isSelected: selectedHeader == key
                        )
                        .onTapGesture {
                            withAnimation {
                                selectedHeader = selectedHeader == key ? nil : key
                            }
                        }

                        if key != sortedKeys.last {
                            Divider()
                        }
                    }
                }
                .background(Color.gray.opacity(0.15))
                .cornerRadius(8)
            }
        }
    }

    private var filteredHeaders: [String: String] {
        if searchText.isEmpty {
            return headers
        }
        return headers.filter { key, value in
            key.localizedCaseInsensitiveContains(searchText) ||
            value.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var sortedKeys: [String] {
        filteredHeaders.keys.sorted()
    }
}

// MARK: - Header Row

struct HeaderRow: View {
    let key: String
    let value: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(key)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(headerColor)
                    .lineLimit(1)

                Spacer()

                Text(displayValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(isSelected ? nil : 1)
                    .multilineTextAlignment(.trailing)
            }

            if isSelected && value.count > 50 {
                HStack {
                    Spacer()
                    NetCheckerTrafficUI_CopyButton(text: value)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    private var displayValue: String {
        if isSensitiveHeader {
            return "••••••••"
        }
        return value
    }

    private var isSensitiveHeader: Bool {
        let sensitiveHeaders = ["authorization", "cookie", "x-api-key", "x-auth-token"]
        return sensitiveHeaders.contains(key.lowercased())
    }

    private var headerColor: Color {
        let key = self.key.lowercased()

        if key.hasPrefix("content-") {
            return .orange
        } else if key.hasPrefix("x-") {
            return .purple
        } else if key.hasPrefix("cache-") {
            return .teal
        } else if ["authorization", "cookie", "set-cookie"].contains(key) {
            return .red
        } else if ["accept", "accept-encoding", "accept-language"].contains(key) {
            return .blue
        }

        return .primary
    }
}

// MARK: - Editable Headers

public struct EditableHeadersView: View {
    @Binding var headers: [String: String]

    @State private var showingAddHeader = false
    @State private var newKey = ""
    @State private var newValue = ""

    public init(headers: Binding<[String: String]>) {
        self._headers = headers
    }

    public var body: some View {
        ForEach(Array(headers.keys.sorted()), id: \.self) { key in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(key)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    Text(headers[key] ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    headers.removeValue(forKey: key)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }

        Button {
            showingAddHeader = true
        } label: {
            Label("Add Header", systemImage: "plus.circle")
        }
        .alert("Add Header", isPresented: $showingAddHeader) {
            TextField("Header Name", text: $newKey)
            TextField("Header Value", text: $newValue)
            Button("Cancel", role: .cancel) {
                newKey = ""
                newValue = ""
            }
            Button("Add") {
                if !newKey.isEmpty {
                    headers[newKey] = newValue
                    newKey = ""
                    newValue = ""
                }
            }
        }
    }
}

// MARK: - Header Presets

/// Common header presets for easy configuration
public struct HeaderPresets {
    public static let commonHeaders: [(name: String, key: String, placeholder: String)] = [
        ("Authorization", "Authorization", "Bearer <token>"),
        ("Content-Type", "Content-Type", "application/json"),
        ("Accept", "Accept", "application/json"),
        ("API Key", "X-API-Key", "<api-key>"),
        ("User Agent", "User-Agent", "MyApp/1.0"),
        ("Accept-Language", "Accept-Language", "en-US"),
    ]
}

/// View for adding headers from presets
public struct HeaderPresetsView: View {
    @Binding var headers: [String: String]
    @SwiftUI.Environment(\.dismiss) private var dismiss

    @State private var selectedPreset: (name: String, key: String, placeholder: String)?
    @State private var customValue = ""

    public init(headers: Binding<[String: String]>) {
        self._headers = headers
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Common Headers") {
                    ForEach(HeaderPresets.commonHeaders, id: \.key) { preset in
                        Button {
                            selectedPreset = preset
                            customValue = headers[preset.key] ?? ""
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Text(preset.key)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if headers[preset.key] != nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                }

                if let preset = selectedPreset {
                    Section("Set Value for \(preset.name)") {
                        TextField(preset.placeholder, text: $customValue)
                            .font(.system(.body, design: .monospaced))
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif

                        HStack {
                            Button("Remove") {
                                headers.removeValue(forKey: preset.key)
                                selectedPreset = nil
                                customValue = ""
                            }
                            .foregroundColor(.red)
                            .disabled(headers[preset.key] == nil)

                            Spacer()

                            Button("Apply") {
                                if !customValue.isEmpty {
                                    headers[preset.key] = customValue
                                }
                                selectedPreset = nil
                                customValue = ""
                            }
                            .disabled(customValue.isEmpty)
                        }
                    }
                }
            }
            .navigationTitle("Header Presets")
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
    ScrollView {
        NetCheckerTrafficUI_HeadersTableView(
            headers: [
                "Content-Type": "application/json",
                "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
                "Accept": "application/json",
                "User-Agent": "NetChecker/1.0",
                "Cache-Control": "no-cache",
                "X-Custom-Header": "custom-value"
            ],
            title: "Request Headers"
        )
        .padding()
    }
}
