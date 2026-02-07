import SwiftUI
import NetCheckerTrafficCore

/// View for managing breakpoint rules
public struct NetCheckerTrafficUI_BreakpointRulesView: View {
    @ObservedObject private var engine = BreakpointEngine.shared
    @State private var showingAddRule = false

    public init() {}

    public var body: some View {
        List {
            // Engine toggle
            Section {
                Toggle("Enable Breakpoints", isOn: $engine.isEnabled)
            }

            // Paused requests
            if !engine.pausedRequests.isEmpty {
                Section("Paused Requests (\(engine.pausedRequests.count))") {
                    ForEach(engine.pausedRequests) { paused in
                        PausedRequestRow(paused: paused)
                    }

                    HStack {
                        Button("Resume All") {
                            engine.resumeAll()
                        }

                        Spacer()

                        Button("Cancel All", role: .destructive) {
                            engine.cancelAll()
                        }
                    }
                }
            }

            // Rules
            Section("Breakpoint Rules (\(engine.rules.count))") {
                if engine.rules.isEmpty {
                    Text("No breakpoint rules configured")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(engine.rules) { rule in
                        BreakpointRuleRow(rule: rule) { enabled in
                            engine.setRuleEnabled(id: rule.id, enabled: enabled)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            engine.removeRule(id: engine.rules[index].id)
                        }
                    }
                }
            }

            // Quick add
            Section("Quick Add") {
                Button {
                    engine.breakpoint(url: "*", direction: .request)
                } label: {
                    Label("Break on All Requests", systemImage: "hand.raised")
                }

                Button {
                    engine.breakpoint(url: "*", direction: .response)
                } label: {
                    Label("Break on All Responses", systemImage: "arrow.down.circle")
                }
            }

            // Clear
            if !engine.rules.isEmpty {
                Section {
                    Button(role: .destructive) {
                        engine.clearRules()
                    } label: {
                        Label("Clear All Rules", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Breakpoints")
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
                AddBreakpointRuleView { rule in
                    engine.addRule(rule)
                }
            }
        }
    }
}

// MARK: - Paused Request Row

struct PausedRequestRow: View {
    let paused: PausedRequest

    @ObservedObject private var engine = BreakpointEngine.shared
    @ObservedObject private var mockEngine = MockEngine.shared
    @State private var showingEditor = false
    @State private var showingMockCreator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                NetCheckerTrafficUI_MethodBadge(methodString: paused.method)

                Text(paused.path)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()

                Text("Paused")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(4)
            }

            Text(paused.host)
                .font(.caption2)
                .foregroundColor(.secondary)

            // Compact action buttons - single row
            HStack(spacing: 6) {
                PausedActionButton(title: "Resume", icon: "play.fill", color: .green) {
                    engine.resume(id: paused.id, with: nil)
                }

                PausedActionButton(title: "Edit", icon: "pencil", color: .blue) {
                    showingEditor = true
                }

                PausedActionButton(title: "Mock", icon: "theatermasks", color: .purple) {
                    showingMockCreator = true
                }

                PausedActionButton(title: "Cancel", icon: "xmark", color: .red) {
                    engine.cancel(id: paused.id)
                }
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                PausedRequestEditorView(paused: paused)
            }
        }
        .sheet(isPresented: $showingMockCreator) {
            NavigationStack {
                QuickMockCreatorView(paused: paused)
            }
        }
    }

}

// MARK: - Paused Action Button

private struct PausedActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.12))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Paused Request Editor View

public struct PausedRequestEditorView: View {
    let paused: PausedRequest

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var engine = BreakpointEngine.shared

    @State private var url: String
    @State private var method: String
    @State private var headerItems: [EditableHeaderItem]
    @State private var requestBody: String
    @State private var showingAddHeader = false
    @State private var newHeaderKey = ""
    @State private var newHeaderValue = ""

    public init(paused: PausedRequest) {
        self.paused = paused
        _url = State(initialValue: paused.originalRequest.url?.absoluteString ?? "")
        _method = State(initialValue: paused.originalRequest.httpMethod ?? "GET")
        let headersDict = paused.originalRequest.allHTTPHeaderFields ?? [:]
        _headerItems = State(initialValue: headersDict.map { EditableHeaderItem(key: $0.key, value: $0.value) })
        _requestBody = State(initialValue: String(data: paused.originalRequest.httpBody ?? Data(), encoding: .utf8) ?? "")
    }

    public var body: some View {
        Form {
            Section("URL") {
                TextField("URL", text: $url)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
            }

            Section("Method") {
                Picker("Method", selection: $method) {
                    ForEach(["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"], id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                ForEach($headerItems) { $item in
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Header Name", text: $item.key)
                            .font(.system(.body, design: .monospaced))
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()

                        TextField("Header Value", text: $item.value)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { indexSet in
                    headerItems.remove(atOffsets: indexSet)
                }

                Button {
                    showingAddHeader = true
                } label: {
                    Label("Add Header", systemImage: "plus.circle")
                }
            } header: {
                HStack {
                    Text("Headers")
                    Spacer()
                    Text("\(headerItems.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Body") {
                TextEditor(text: $requestBody)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 100)

                if !requestBody.isEmpty {
                    Button("Format JSON") {
                        formatJSON()
                    }
                }
            }
        }
        .navigationTitle("Edit Request")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Discard") {
                    // Just cancel the breakpoint without resuming
                    engine.cancel(id: paused.id)
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Resume with Changes") {
                    resumeWithModifiedRequest()
                }
            }
        }
        .alert("Add Header", isPresented: $showingAddHeader) {
            TextField("Header Name", text: $newHeaderKey)
            TextField("Header Value", text: $newHeaderValue)
            Button("Cancel", role: .cancel) {
                newHeaderKey = ""
                newHeaderValue = ""
            }
            Button("Add") {
                if !newHeaderKey.isEmpty {
                    headerItems.append(EditableHeaderItem(key: newHeaderKey, value: newHeaderValue))
                    newHeaderKey = ""
                    newHeaderValue = ""
                }
            }
        }
    }

    private func formatJSON() {
        if let data = requestBody.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            requestBody = prettyString
        }
    }

    private func resumeWithModifiedRequest() {
        guard let requestURL = URL(string: url) else {
            engine.resume(id: paused.id, with: nil)
            dismiss()
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method

        // Convert header items back to dictionary
        var headersDict: [String: String] = [:]
        for item in headerItems where !item.key.isEmpty {
            headersDict[item.key] = item.value
        }
        request.allHTTPHeaderFields = headersDict

        if !requestBody.isEmpty {
            request.httpBody = requestBody.data(using: .utf8)
        }

        engine.resume(id: paused.id, with: request)
        dismiss()
    }
}

// Helper struct for editable headers
struct EditableHeaderItem: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

// MARK: - Quick Mock Creator View

struct QuickMockCreatorView: View {
    let paused: PausedRequest

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var engine = BreakpointEngine.shared
    @ObservedObject private var mockEngine = MockEngine.shared

    @State private var statusCode = 200
    @State private var responseBody = ""
    @State private var contentType = "application/json"
    @State private var enableAfterCreate = true

    var body: some View {
        Form {
            Section {
                Text(paused.url?.absoluteString ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            } header: {
                Text("URL to Mock")
            } footer: {
                Text("This will create a mock rule that returns your custom response for this URL")
            }

            Section("Response Status") {
                Picker("Status Code", selection: $statusCode) {
                    Text("200 OK").tag(200)
                    Text("201 Created").tag(201)
                    Text("204 No Content").tag(204)
                    Text("400 Bad Request").tag(400)
                    Text("401 Unauthorized").tag(401)
                    Text("403 Forbidden").tag(403)
                    Text("404 Not Found").tag(404)
                    Text("500 Server Error").tag(500)
                }
            }

            Section("Content Type") {
                Picker("Type", selection: $contentType) {
                    Text("JSON").tag("application/json")
                    Text("Plain Text").tag("text/plain")
                    Text("HTML").tag("text/html")
                    Text("XML").tag("application/xml")
                }
                .pickerStyle(.segmented)
            }

            Section("Response Body") {
                TextEditor(text: $responseBody)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 150)

                if contentType == "application/json" {
                    Button("Format JSON") {
                        formatJSON()
                    }
                    .disabled(responseBody.isEmpty)
                }
            }

            Section {
                Toggle("Enable mock after creating", isOn: $enableAfterCreate)
            }
        }
        .navigationTitle("Create Mock Response")
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
                Button("Create & Resume") {
                    createMockAndResume()
                }
            }
        }
        .onAppear {
            // Pre-fill with sample JSON
            if responseBody.isEmpty {
                responseBody = "{\n  \"message\": \"Mocked response\"\n}"
            }
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

    private func createMockAndResume() {
        // Create URL pattern from the request URL
        let urlPattern = paused.url?.absoluteString ?? "*"

        // Create mock response
        let response = MockResponse(
            statusCode: statusCode,
            headers: ["Content-Type": contentType],
            body: responseBody.data(using: .utf8)
        )

        // Create and add the rule
        let rule = MockRule(
            name: "Mock: \(paused.path)",
            isEnabled: enableAfterCreate,
            matching: MockMatching(urlPattern: urlPattern),
            action: .respond(response)
        )

        mockEngine.addRule(rule)

        // Enable mock engine if needed
        if enableAfterCreate && !mockEngine.isEnabled {
            mockEngine.isEnabled = true
        }

        // Cancel the paused request (it will be mocked on retry)
        engine.cancel(id: paused.id)

        dismiss()
    }
}

// MARK: - Breakpoint Rule Row

struct BreakpointRuleRow: View {
    let rule: BreakpointRule
    let onToggle: (Bool) -> Void

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
                    DirectionBadge(direction: rule.direction)

                    if let autoResume = rule.autoResume {
                        Text("Auto-resume: \(Int(autoResume))s")
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
}

// MARK: - Direction Badge

struct DirectionBadge: View {
    let direction: BreakpointDirection

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: direction.systemImage)
                .font(.caption2)
            Text(direction.displayName)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(directionColor.opacity(0.15))
        .foregroundColor(directionColor)
        .cornerRadius(4)
    }

    private var directionColor: Color {
        switch direction {
        case .request: return .blue
        case .response: return .green
        case .both: return .purple
        }
    }
}

// MARK: - Add Breakpoint Rule View

struct AddBreakpointRuleView: View {
    let onSave: (BreakpointRule) -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var urlPattern = ""
    @State private var selectedMethod: HTTPMethod?
    @State private var host = ""
    @State private var direction: BreakpointDirection = .request
    @State private var hasAutoResume = false
    @State private var autoResumeSeconds: Double = 5.0

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

            Section("Direction") {
                Picker("Break On", selection: $direction) {
                    ForEach(BreakpointDirection.allCases, id: \.self) { dir in
                        Label(dir.displayName, systemImage: dir.systemImage)
                            .tag(dir)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Auto Resume") {
                Toggle("Auto Resume After Delay", isOn: $hasAutoResume)

                if hasAutoResume {
                    Stepper(
                        "Resume after \(Int(autoResumeSeconds)) seconds",
                        value: $autoResumeSeconds,
                        in: 1...60
                    )
                }
            }
        }
        .navigationTitle("Add Breakpoint")
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
        let matching = BreakpointMatching(
            urlPattern: urlPattern.isEmpty ? nil : urlPattern,
            method: selectedMethod,
            host: host.isEmpty ? nil : host
        )

        let rule = BreakpointRule(
            name: name.isEmpty ? "Breakpoint" : name,
            matching: matching,
            direction: direction,
            autoResume: hasAutoResume ? autoResumeSeconds : nil
        )

        onSave(rule)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        NetCheckerTrafficUI_BreakpointRulesView()
    }
}
