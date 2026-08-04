import SwiftUI
import NetCheckerTrafficCore

/// Лента кадров одного WebSocket-соединения
public struct NetCheckerTrafficUI_WebSocketDetailView: View {
    let connectionId: UUID

    @ObservedObject private var store = WebSocketStore.shared
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var autoScroll = true
    @State private var directionFilter: WebSocketDirection?
    @State private var selectedFrame: WebSocketFrame?

    public init(connectionId: UUID) {
        self.connectionId = connectionId
    }

    private var connection: WebSocketRecord? {
        store.connection(id: connectionId)
    }

    private var frames: [WebSocketFrame] {
        guard let connection = connection else { return [] }
        guard let filter = directionFilter else { return connection.frames }
        return connection.frames.filter { $0.direction == filter }
    }

    public var body: some View {
        Group {
            if let connection = connection {
                content(for: connection)
            } else {
                Text("Соединение удалено")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("WebSocket")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(item: $selectedFrame) { frame in
            NavigationStack {
                WebSocketFrameDetail(frame: frame)
            }
        }
    }

    // MARK: - Содержимое

    private func content(for connection: WebSocketRecord) -> some View {
        VStack(spacing: 0) {
            header(for: connection)
            Divider()
            filterBar
            Divider()
            frameFeed
        }
    }

    private func header(for connection: WebSocketRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                WebSocketStateBadge(state: connection.state)
                Spacer()
                Text(String(format: "%.1f с", connection.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(connection.url.absoluteString)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)

            HStack(spacing: 14) {
                Label("\(connection.sentFrameCount)", systemImage: "arrow.up")
                Label("\(connection.receivedFrameCount)", systemImage: "arrow.down")
                Label(NetCheckerTrafficUI_ByteFormat.string(connection.totalBytes), systemImage: "scalemass")
            }
            .font(.caption2)
            .foregroundColor(.secondary)

            if connection.droppedFrameCount > 0 {
                Text("Отброшено ранних кадров: \(connection.droppedFrameCount) — достигнут предел хранения")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var filterBar: some View {
        HStack {
            Picker("Направление", selection: $directionFilter) {
                Text("Все").tag(WebSocketDirection?.none)
                Text("Отправленные").tag(WebSocketDirection?.some(.outgoing))
                Text("Полученные").tag(WebSocketDirection?.some(.incoming))
            }
            .pickerStyle(.segmented)

            Toggle(isOn: $autoScroll) {
                Image(systemName: "arrow.down.to.line")
            }
            .toggleStyle(.button)
            .help("Автопрокрутка к последнему кадру")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var frameFeed: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(frames) { frame in
                    Button {
                        selectedFrame = frame
                    } label: {
                        WebSocketFrameRow(frame: frame)
                    }
                    .buttonStyle(.plain)
                    .id(frame.id)
                }
            }
            .listStyle(.plain)
            .onChange(of: frames.count) { _ in
                guard autoScroll, let last = frames.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

// MARK: - Строка кадра

struct WebSocketFrameRow: View {
    let frame: WebSocketFrame

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: frame.direction.symbolName)
                .foregroundColor(tint)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(frame.kind.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(tint)

                    if frame.isJSON {
                        Text("JSON")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(NetCheckerTrafficUI_ByteFormat.string(frame.size))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(frame.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(frame.preview)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var tint: Color {
        if frame.kind == .error { return .red }
        return frame.direction == .outgoing ? .blue : .green
    }
}

// MARK: - Подробности кадра

struct WebSocketFrameDetail: View {
    let frame: WebSocketFrame

    @SwiftUI.Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let text = frame.text {
                    if frame.isJSON {
                        NetCheckerTrafficUI_JSONSyntaxView(json: text)
                    } else {
                        Text(text)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } else if let data = frame.data {
                    Text(data.map { String(format: "%02x", $0) }.joined(separator: " "))
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    Text("Кадр без содержимого")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(frame.kind.label)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
