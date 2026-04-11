import SwiftUI
import NetCheckerTrafficCore

/// Детальный просмотр MCP-специфических данных внутри TrafficRecord
public struct MCPLogEntryView: View {
    let record: TrafficRecord

    public init(record: TrafficRecord) {
        self.record = record
    }

    /// Показывать только если запись от MCP
    public var isMCPRecord: Bool {
        record.metadata.mcpSource != nil
    }

    public var body: some View {
        if isMCPRecord {
            mcpContent
        }
    }

    private var mcpContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Заголовок
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.teal)
                Text("MCP Запись")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Источник
            if let source = record.metadata.mcpSource {
                infoRow(label: "Инструмент", value: source.toolName)
                infoRow(label: "Сессия", value: source.sessionId)
                if let version = source.toolVersion {
                    infoRow(label: "Версия", value: version)
                }
            }

            // Теги
            let mcpTags = record.metadata.tags.filter { !["mcp"].contains($0) }
            if !mcpTags.isEmpty {
                tagsSection(mcpTags)
            }

            // Нарушения
            let violations = record.metadata.tags.filter { $0.hasPrefix("violation:") }
            if !violations.isEmpty {
                violationsSection(violations)
            }
        }
        .padding()
        .background(Color.teal.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.teal.opacity(0.2), lineWidth: 1)
        )
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    private func tagsSection(_ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Теги")
                .font(.caption)
                .foregroundColor(.secondary)

            FlowLayout(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundColor(.secondary)
                        .cornerRadius(4)
                }
            }
        }
    }

    private func violationsSection(_ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Нарушения")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            ForEach(tags, id: \.self) { tag in
                let field = tag.replacingOccurrences(of: "violation:", with: "")
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text(field)
                        .font(.caption)
                }
            }
        }
    }
}

// MARK: - FlowLayout (для тегов)

struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let itemSize = subview.sizeThatFits(.unspecified)

                if currentX + itemSize.width > maxWidth, currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(origin: CGPoint(x: currentX, y: currentY), size: itemSize))
                lineHeight = max(lineHeight, itemSize.height)
                currentX += itemSize.width + spacing
            }

            size = CGSize(
                width: maxWidth,
                height: currentY + lineHeight
            )
        }
    }
}
