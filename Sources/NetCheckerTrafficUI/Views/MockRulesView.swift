import SwiftUI
import NetCheckerTrafficCore

/// View for managing mock rules
public struct NetCheckerTrafficUI_MockRulesView: View {
    @ObservedObject private var mockEngine = MockEngine.shared
    @State private var showingAddRule = false
    @State private var editingRule: MockRule?

    public init() {}

    public var body: some View {
        List {
            // Engine toggle
            Section {
                Toggle("Enable Mocking", isOn: $mockEngine.isEnabled)
            }

            // Quick presets
            Section("Quick Presets") {
                Button {
                    mockEngine.addRule(.serverError(for: "*"))
                } label: {
                    Label("Add Server Error (500)", systemImage: "exclamationmark.triangle")
                }

                Button {
                    mockEngine.addRule(.timeout(for: "*"))
                } label: {
                    Label("Add Timeout", systemImage: "clock.badge.exclamationmark")
                }

                Button {
                    mockEngine.addRule(.noConnection(for: "*"))
                } label: {
                    Label("Add No Connection", systemImage: "wifi.slash")
                }

                Button {
                    mockEngine.addRule(.slow(for: "*", delay: 5.0))
                } label: {
                    Label("Add Slow Response (5s)", systemImage: "tortoise")
                }
            }

            // Active rules
            Section("Active Rules (\(mockEngine.rules.count))") {
                if mockEngine.rules.isEmpty {
                    Text("No mock rules configured")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(mockEngine.rules) { rule in
                        MockRuleRow(
                            rule: rule,
                            onToggle: { enabled in
                                mockEngine.setRuleEnabled(id: rule.id, enabled: enabled)
                            },
                            onEdit: {
                                editingRule = rule
                            }
                        )
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            mockEngine.removeRule(id: mockEngine.rules[index].id)
                        }
                    }
                }
            }

            // Statistics
            if !mockEngine.rules.isEmpty {
                Section("Statistics") {
                    HStack {
                        Text("Matched Requests")
                        Spacer()
                        Text("\(totalMatchCount)")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Clear all
            if !mockEngine.rules.isEmpty {
                Section {
                    Button(role: .destructive) {
                        mockEngine.clearRules()
                    } label: {
                        Label("Clear All Rules", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Mock Rules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddRule = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddRule) {
            NavigationStack {
                AddMockRuleView { rule in
                    mockEngine.addRule(rule)
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            NavigationStack {
                EditMockRuleView(rule: rule) { updatedRule in
                    mockEngine.updateRule(updatedRule)
                }
            }
        }
    }

    private var totalMatchCount: Int {
        mockEngine.rules.reduce(0) { $0 + $1.activationCount }
    }
}

// MARK: - Mock Rule Row

struct MockRuleRow: View {
    let rule: MockRule
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name.isEmpty ? "Unnamed Rule" : rule.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(ruleDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Text(actionDescription)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(actionColor.opacity(0.15))
                        .foregroundColor(actionColor)
                        .cornerRadius(4)

                    if rule.activationCount > 0 {
                        Text("\(rule.activationCount) matches")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }

    private var ruleDescription: String {
        if let pattern = rule.matching.urlPattern {
            return "URL: \(pattern)"
        } else if let host = rule.matching.host {
            return "Host: \(host)"
        } else if let method = rule.matching.method {
            return "Method: \(method.rawValue)"
        }
        return "All requests"
    }

    private var actionDescription: String {
        switch rule.action {
        case .respond(let response):
            return "Response \(response.statusCode)"
        case .error(let error):
            return error.nsError.localizedDescription
        case .delay(let seconds):
            return "Delay \(Int(seconds))s"
        case .passthrough:
            return "Passthrough"
        case .modifyResponse(let statusCode, _):
            if let status = statusCode {
                return "Modify to \(status)"
            }
            return "Modify Response"
        }
    }

    private var actionColor: Color {
        switch rule.action {
        case .respond(let response):
            return TrafficTheme.statusColor(for: response.statusCode)
        case .error:
            return .red
        case .delay:
            return .orange
        case .passthrough:
            return .green
        case .modifyResponse:
            return .purple
        }
    }
}

// MARK: - Add Mock Rule View

struct AddMockRuleView: View {
    let onSave: (MockRule) -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var urlPattern = ""
    @State private var selectedMethod: HTTPMethod?
    @State private var host = ""
    @State private var actionType = ActionType.respond
    @State private var statusCode = 200
    @State private var responseBody = ""
    @State private var delaySeconds: Double = 5.0
    @State private var errorType = MockError.noConnection

    enum ActionType: String, CaseIterable {
        case respond = "Respond"
        case error = "Error"
        case delay = "Delay"
        case passthrough = "Passthrough"
    }

    var body: some View {
        Form {
            Section("Rule Info") {
                TextField("Rule Name", text: $name)
            }

            Section("Matching") {
                TextField("URL Pattern (e.g., */api/*)", text: $urlPattern)
                TextField("Host (optional)", text: $host)

                Picker("Method", selection: $selectedMethod) {
                    Text("Any").tag(nil as HTTPMethod?)
                    ForEach(HTTPMethod.allCases, id: \.rawValue) { method in
                        Text(method.rawValue).tag(method as HTTPMethod?)
                    }
                }
            }

            Section("Action") {
                Picker("Action Type", selection: $actionType) {
                    ForEach(ActionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                switch actionType {
                case .respond:
                    Stepper("Status Code: \(statusCode)", value: $statusCode, in: 100...599)
                    TextField("Response Body (JSON)", text: $responseBody, axis: .vertical)
                        .lineLimit(5...10)

                case .error:
                    Picker("Error Type", selection: $errorType) {
                        Text("No Connection").tag(MockError.noConnection)
                        Text("Timeout").tag(MockError.timeout)
                        Text("DNS Failure").tag(MockError.dnsFailure)
                        Text("SSL Error").tag(MockError.sslError)
                    }

                case .delay:
                    Stepper("Delay: \(Int(delaySeconds))s", value: $delaySeconds, in: 1...60)

                case .passthrough:
                    Text("Request will pass through normally")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Add Mock Rule")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveRule()
                }
                .disabled(!isValid)
            }
        }
    }

    private var isValid: Bool {
        !urlPattern.isEmpty || !host.isEmpty || selectedMethod != nil
    }

    private func saveRule() {
        let matching = MockMatching(
            urlPattern: urlPattern.isEmpty ? nil : urlPattern,
            method: selectedMethod,
            host: host.isEmpty ? nil : host
        )

        let action: MockAction
        switch actionType {
        case .respond:
            let response = MockResponse(
                statusCode: statusCode,
                headers: ["Content-Type": "application/json"],
                body: responseBody.data(using: .utf8)
            )
            action = .respond(response)
        case .error:
            action = .error(errorType)
        case .delay:
            action = .delay(seconds: delaySeconds)
        case .passthrough:
            action = .passthrough
        }

        let rule = MockRule(
            name: name.isEmpty ? "Mock Rule" : name,
            matching: matching,
            action: action
        )

        onSave(rule)
        dismiss()
    }
}

// MARK: - Edit Mock Rule View

struct EditMockRuleView: View {
    let rule: MockRule
    let onSave: (MockRule) -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var mockEngine = MockEngine.shared

    @State private var name: String
    @State private var isEnabled: Bool
    @State private var urlPattern: String
    @State private var host: String
    @State private var selectedMethod: HTTPMethod?
    @State private var statusCode: Int
    @State private var responseBody: String
    @State private var delaySeconds: Double
    @State private var showDeleteConfirmation = false

    init(rule: MockRule, onSave: @escaping (MockRule) -> Void) {
        self.rule = rule
        self.onSave = onSave
        self._name = State(initialValue: rule.name)
        self._isEnabled = State(initialValue: rule.isEnabled)
        self._urlPattern = State(initialValue: rule.matching.urlPattern ?? "")
        self._host = State(initialValue: rule.matching.host ?? "")
        self._selectedMethod = State(initialValue: rule.matching.method)

        // Extract values from action
        switch rule.action {
        case .respond(let response):
            self._statusCode = State(initialValue: response.statusCode)
            let bodyString = response.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            self._responseBody = State(initialValue: bodyString)
            self._delaySeconds = State(initialValue: 0)
        case .delay(let seconds):
            self._statusCode = State(initialValue: 200)
            self._responseBody = State(initialValue: "")
            self._delaySeconds = State(initialValue: seconds)
        default:
            self._statusCode = State(initialValue: 200)
            self._responseBody = State(initialValue: "")
            self._delaySeconds = State(initialValue: 0)
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Rule Name", text: $name)
                Toggle("Enabled", isOn: $isEnabled)
            } header: {
                Text("Rule Info")
            }

            Section {
                TextField("URL Pattern", text: $urlPattern)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                TextField("Host (optional)", text: $host)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                Picker("Method", selection: $selectedMethod) {
                    Text("Any").tag(nil as HTTPMethod?)
                    ForEach(HTTPMethod.allCases, id: \.rawValue) { method in
                        Text(method.rawValue).tag(method as HTTPMethod?)
                    }
                }
            } header: {
                Text("Matching")
            } footer: {
                Text("Use * as wildcard, e.g., */api/users/*")
            }

            if case .respond = rule.action {
                Section("Response") {
                    Picker("Status Code", selection: $statusCode) {
                        Group {
                            Text("200 OK").tag(200)
                            Text("201 Created").tag(201)
                            Text("204 No Content").tag(204)
                        }
                        Divider()
                        Group {
                            Text("400 Bad Request").tag(400)
                            Text("401 Unauthorized").tag(401)
                            Text("403 Forbidden").tag(403)
                            Text("404 Not Found").tag(404)
                        }
                        Divider()
                        Group {
                            Text("500 Server Error").tag(500)
                            Text("502 Bad Gateway").tag(502)
                            Text("503 Unavailable").tag(503)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Response Body")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $responseBody)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 150)
                    }

                    Button("Format JSON") {
                        formatJSON()
                    }
                    .disabled(responseBody.isEmpty)
                }
            }

            if case .delay = rule.action {
                Section("Delay") {
                    Stepper("Delay: \(Int(delaySeconds)) seconds", value: $delaySeconds, in: 1...60)
                }
            }

            Section("Statistics") {
                HStack {
                    Text("Match Count")
                    Spacer()
                    Text("\(rule.activationCount)")
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Delete Rule", systemImage: "trash")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Edit Rule")
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
                    saveRule()
                }
                .disabled(urlPattern.isEmpty && host.isEmpty && selectedMethod == nil)
            }
        }
        .alert("Delete Rule?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                mockEngine.removeRule(id: rule.id)
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func formatJSON() {
        if let data = responseBody.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            responseBody = prettyString
        }
    }

    private func saveRule() {
        let matching = MockMatching(
            urlPattern: urlPattern.isEmpty ? nil : urlPattern,
            method: selectedMethod,
            host: host.isEmpty ? nil : host
        )

        var updatedRule = rule
        updatedRule.name = name
        updatedRule.isEnabled = isEnabled
        updatedRule.matching = matching

        // Update action based on original type
        switch rule.action {
        case .respond:
            let response = MockResponse(
                statusCode: statusCode,
                headers: ["Content-Type": "application/json"],
                body: responseBody.isEmpty ? nil : responseBody.data(using: .utf8)
            )
            updatedRule.action = .respond(response)
        case .delay:
            updatedRule.action = .delay(seconds: delaySeconds)
        default:
            break // Keep original action for other types
        }

        onSave(updatedRule)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        NetCheckerTrafficUI_MockRulesView()
    }
}
