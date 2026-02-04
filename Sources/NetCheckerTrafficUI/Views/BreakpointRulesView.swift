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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NetCheckerTrafficUI_MethodBadge(methodString: paused.method)

                Text(paused.path)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()

                Text(formatDuration(paused.pausedDuration))
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Text(paused.host)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button {
                    engine.resume(id: paused.id, with: nil)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    engine.cancel(id: paused.id)
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        }
        return String(format: "%.1f s", duration)
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
