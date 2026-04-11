import SwiftUI
import NetCheckerTrafficCore

/// Детальный просмотр MCP-потока — timeline, нарушения, генерация тестов
public struct MCPFlowDetailView: View {
    let flow: MCPFlow

    @ObservedObject private var store = TrafficStore.shared
    @State private var showingExportSheet = false
    @State private var exportedCode = ""
    @State private var showingCodeSheet = false
    @State private var mockRulesApplied = false

    public init(flow: MCPFlow) {
        self.flow = flow
    }

    public var body: some View {
        List {
            overviewSection
            if !flow.violations.isEmpty { violationsSection }
            timelineSection
            actionsSection
        }
        .navigationTitle(flow.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showingCodeSheet) {
            codeSheet
        }
    }

    // MARK: - Секции

    private var overviewSection: some View {
        Section {
            HStack {
                Label("Источник", systemImage: "cpu")
                Spacer()
                MCPSourceBadge(source: flow.source)
            }

            HStack {
                Label("Статус", systemImage: "info.circle")
                Spacer()
                statusBadge
            }

            HStack {
                Label("Операций", systemImage: "list.number")
                Spacer()
                Text("\(flow.entries.count)")
                    .foregroundColor(.secondary)
            }

            if let duration = flow.duration {
                HStack {
                    Label("Длительность", systemImage: "clock")
                    Spacer()
                    Text(formatDuration(duration))
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Label("Начало", systemImage: "calendar")
                Spacer()
                Text(flow.startedAt, style: .time)
                    .foregroundColor(.secondary)
            }

            if !flow.violations.isEmpty {
                HStack {
                    Label("Нарушений", systemImage: "exclamationmark.triangle")
                    Spacer()
                    Text("\(flow.violations.count)")
                        .foregroundColor(.orange)
                }
            }
        } header: {
            Text("Обзор")
        }
    }

    private var violationsSection: some View {
        Section {
            ForEach(Array(flow.violations.enumerated()), id: \.offset) { _, violation in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        MCPSeverityBadge(severity: violation.severity)
                        Text(violation.field)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ожидалось")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(violation.expected)
                                .font(.caption)
                                .foregroundColor(.green)
                        }

                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Получено")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(violation.actual)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Нарушения")
            }
        }
    }

    private var timelineSection: some View {
        Section {
            ForEach(Array(flow.entries.sorted { $0.sequenceNumber < $1.sequenceNumber }.enumerated()), id: \.element.id) { index, entry in
                timelineRow(index: index, entry: entry)
            }
        } header: {
            Text("Timeline")
        }
    }

    private func timelineRow(index: Int, entry: MCPFlowEntry) -> some View {
        HStack(spacing: 12) {
            // Номер шага
            ZStack {
                Circle()
                    .fill(entryColor(entry).opacity(0.2))
                    .frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(entryColor(entry))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    MCPOperationBadge(operationType: entry.operationType)

                    if !entry.violations.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                if let record = store.record(for: entry.id) {
                    Text(record.url.path.isEmpty ? record.url.absoluteString : record.url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let record = store.record(for: entry.id),
               let status = record.statusCode {
                Text("\(status)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(TrafficTheme.statusColor(for: status))
            }
        }
        .padding(.vertical, 4)
    }

    private var actionsSection: some View {
        Section {
            Button {
                let count = MCPTestGenerator.applyMockRules(from: flow)
                mockRulesApplied = true
                print("[NetChecker MCP] Добавлено \(count) MockRules")
            } label: {
                Label(
                    mockRulesApplied ? "MockRules добавлены ✓" : "Добавить MockRules",
                    systemImage: "theatermasks"
                )
                .foregroundColor(mockRulesApplied ? .green : .blue)
            }

            Button {
                exportedCode = MCPTestGenerator.generateTestCode(from: flow)
                showingCodeSheet = true
            } label: {
                Label("Сгенерировать Swift тест", systemImage: "swift")
            }

            if let harData = MCPTestGenerator.exportFlow(flow, format: .har),
               let harString = String(data: harData, encoding: .utf8) {
                ShareLink(
                    item: harString,
                    preview: SharePreview("Flow: \(flow.name).har")
                ) {
                    Label("Экспорт как HAR", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Генерация тестов")
        }
    }

    // MARK: - Code Sheet

    private var codeSheet: some View {
        NavigationStack {
            ScrollView {
                Text(exportedCode)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Swift Test Code")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        showingCodeSheet = false
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copyToClipboard(exportedCode)
                    } label: {
                        Label("Копировать", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }

    // MARK: - Badges & Helpers

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
            Text(flow.status.rawValue.capitalized)
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(statusColor)
    }

    private var statusIcon: String {
        switch flow.status {
        case .active: return "circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch flow.status {
        case .active: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func entryColor(_ entry: MCPFlowEntry) -> Color {
        if !entry.violations.isEmpty { return .orange }
        switch entry.severity {
        case .error, .critical: return .red
        default: return Color(entry.operationType.colorName)
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        if t < 1 { return String(format: "%.0f мс", t * 1000) }
        return String(format: "%.1f с", t)
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
