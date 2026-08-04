import SwiftUI
import NetCheckerTrafficCore

/// Список перехваченных WebSocket-соединений
public struct NetCheckerTrafficUI_WebSocketListView: View {
    @ObservedObject private var store = WebSocketStore.shared
    @State private var selected: WebSocketRecord?

    public init() {}

    public var body: some View {
        Group {
            if store.connections.isEmpty {
                emptyState
            } else {
                connectionsList
            }
        }
        .sheet(item: $selected) { record in
            NavigationStack {
                NetCheckerTrafficUI_WebSocketDetailView(connectionId: record.id)
            }
        }
    }

    // MARK: - Списки

    private var connectionsList: some View {
        List {
            ForEach(store.connections) { connection in
                Button {
                    selected = connection
                } label: {
                    WebSocketConnectionRow(connection: connection)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets {
                    store.remove(id: store.connections[index].id)
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 44))
                .foregroundColor(.secondary)

            Text("Нет WebSocket-соединений")
                .font(.headline)

            Text("Создавайте задачи через `session.netCheckerWebSocketTask(with:)` — обычные `webSocketTask` проходят мимо инспектора.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Строка соединения

struct WebSocketConnectionRow: View {
    let connection: WebSocketRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                WebSocketStateBadge(state: connection.state)

                Text(connection.host)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)

                Spacer()

                Text(connection.openedAt, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(connection.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack(spacing: 12) {
                Label("\(connection.sentFrameCount)", systemImage: "arrow.up")
                Label("\(connection.receivedFrameCount)", systemImage: "arrow.down")
                Label(NetCheckerTrafficUI_ByteFormat.string(connection.totalBytes), systemImage: "scalemass")

                if connection.droppedFrameCount > 0 {
                    Text("отброшено \(connection.droppedFrameCount)")
                        .foregroundColor(.orange)
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Индикатор состояния

struct WebSocketStateBadge: View {
    let state: WebSocketConnectionState

    var body: some View {
        Text(state.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var color: Color {
        switch state {
        case .connecting: return .orange
        case .open: return .green
        case .closed: return .secondary
        case .failed: return .red
        }
    }
}

/// Форматирование размеров для WebSocket-экранов
enum NetCheckerTrafficUI_ByteFormat {
    static func string(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) Б" }
        if bytes < 1024 * 1024 { return String(format: "%.1f КБ", Double(bytes) / 1024) }
        return String(format: "%.1f МБ", Double(bytes) / (1024 * 1024))
    }
}
