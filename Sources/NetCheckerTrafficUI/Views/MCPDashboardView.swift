import SwiftUI
import NetCheckerTrafficCore

/// Дашборд MCP-сервера — статус, подключения, потоки
public struct MCPDashboardView: View {
    @ObservedObject private var server = MCPServer.shared
    @ObservedObject private var tracker = MCPFlowTracker.shared
    @ObservedObject private var store = TrafficStore.shared

    @State private var showingCopyAlert = false
    @State private var selectedFlow: MCPFlow?

    public init() {}

    public var body: some View {
        List {
            serverSection
            statsSection
            if !tracker.activeFlows.isEmpty { activeFlowsSection }
            if !tracker.completedFlows.isEmpty { completedFlowsSection }
            quickStartSection
        }
        .navigationTitle("MCP Server")
        .sheet(item: $selectedFlow) { flow in
            NavigationStack {
                MCPFlowDetailView(flow: flow)
            }
        }
    }

    // MARK: - Секции

    private var serverSection: some View {
        Section {
            HStack {
                Label("Статус", systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                if server.isRunning {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Запущен")
                            .foregroundColor(.green)
                    }
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 8, height: 8)
                        Text("Остановлен")
                            .foregroundColor(.secondary)
                    }
                }
            }

            if server.isRunning {
                HStack {
                    Label("URL", systemImage: "link")
                    Spacer()
                    HStack(spacing: 4) {
                        Text(server.connectionURL)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        Button {
                            copyToClipboard(server.connectionURL)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Label("Запросов", systemImage: "arrow.down.circle")
                    Spacer()
                    Text("\(server.requestCount)")
                        .foregroundColor(.secondary)
                }
            }

            if let error = server.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Button {
                if server.isRunning {
                    server.stop()
                } else {
                    server.start()
                }
            } label: {
                Label(
                    server.isRunning ? "Остановить сервер" : "Запустить сервер",
                    systemImage: server.isRunning ? "stop.circle.fill" : "play.circle.fill"
                )
                .foregroundColor(server.isRunning ? .red : .green)
            }
        } header: {
            Text("MCP Сервер")
        }
    }

    private var statsSection: some View {
        Section {
            HStack {
                Label("Запросов обработано", systemImage: "arrow.down.circle")
                Spacer()
                Text("\(server.requestCount)")
                    .foregroundColor(.secondary)
            }

            let mcpRecords = store.records(matching: .mcpOnly)
            HStack {
                Label("MCP записей", systemImage: "list.bullet")
                Spacer()
                Text("\(mcpRecords.count)")
                    .foregroundColor(.secondary)
            }

            let violations = mcpRecords.filter { record in
                record.metadata.tags.contains { $0.hasPrefix("violation:") }
            }
            HStack {
                Label("Нарушений", systemImage: "exclamationmark.triangle")
                Spacer()
                Text("\(violations.count)")
                    .foregroundColor(violations.isEmpty ? .secondary : .orange)
            }
        } header: {
            Text("Статистика")
        }
    }

    private var activeFlowsSection: some View {
        Section {
            ForEach(tracker.activeFlows) { flow in
                flowRow(flow, isActive: true)
            }
        } header: {
            HStack {
                Text("Активные потоки")
                Spacer()
                Text("\(tracker.activeFlows.count)")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
    }

    private var completedFlowsSection: some View {
        Section {
            ForEach(tracker.completedFlows.reversed()) { flow in
                flowRow(flow, isActive: false)
            }
        } header: {
            HStack {
                Text("Завершённые потоки")
                Spacer()
                Text("\(tracker.completedFlows.count)")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
    }

    private var quickStartSection: some View {
        Section {
            // Сниппет конфига
            VStack(alignment: .leading, spacing: 4) {
                Text("Добавь в .mcp.json:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(mcpConfigSnippet)
                    .font(.system(.caption2, design: .monospaced))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
            .padding(.vertical, 2)

            // Кнопка копирования конфига
            Button {
                copyToClipboard(mcpConfigSnippet)
            } label: {
                Label("Скопировать MCP конфиг", systemImage: "doc.on.doc")
            }

            // Кнопка копирования cURL
            Button {
                copyToClipboard(exampleCURL)
            } label: {
                Label("Скопировать cURL пример", systemImage: "terminal")
            }
        } header: {
            Text("Быстрый старт")
        }
    }

    // MARK: - Flow Row

    private func flowRow(_ flow: MCPFlow, isActive: Bool) -> some View {
        Button {
            selectedFlow = flow
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "circle.fill" : statusIcon(flow.status))
                    .foregroundColor(isActive ? .orange : statusColor(flow.status))
                    .font(.caption)

                VStack(alignment: .leading, spacing: 4) {
                    Text(flow.name)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(flow.source.toolName)
                            .font(.caption2)
                            .foregroundColor(.indigo)

                        Text("\(flow.entries.count) операций")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if !flow.violations.isEmpty {
                            Text("\(flow.violations.count) нарушений")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func statusIcon(_ status: MCPFlowStatus) -> String {
        switch status {
        case .active: return "circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func statusColor(_ status: MCPFlowStatus) -> Color {
        switch status {
        case .active: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private var mcpConfigSnippet: String {
        """
        "NETCHECKER_URL": "\(server.connectionURL)"
        """
    }

    private var exampleJSON: String {
        """
        {
          "operationType": "apiCall",
          "source": {
            "toolName": "claude-code",
            "sessionId": "my-session"
          },
          "payload": {
            "type": "networkCall",
            "url": "https://api.example.com",
            "method": "GET",
            "statusCode": 200
          },
          "severity": "info"
        }
        """
    }

    private var exampleCURL: String {
        """
        curl -X POST \(server.connectionURL)/log \\
          -H "Content-Type: application/json" \\
          -d '{"operationType":"apiCall","source":{"toolName":"my-tool","sessionId":"s1"},"payload":{"type":"networkCall","url":"https://api.example.com","method":"GET","statusCode":200},"severity":"info"}'
        """
    }
}
