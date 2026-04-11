import SwiftUI
import NetCheckerTrafficCore

/// Бейдж типа MCP-операции
public struct MCPOperationBadge: View {
    let operationType: MCPOperationType

    public init(operationType: MCPOperationType) {
        self.operationType = operationType
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: operationType.systemImage)
            Text(operationType.displayName)
        }
        .font(.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(TrafficTheme.badgeCornerRadius)
    }

    private var color: Color {
        Color(operationType.colorName)
    }
}

/// Бейдж источника (AI-инструмент)
public struct MCPSourceBadge: View {
    let source: MCPSourceInfo

    public init(source: MCPSourceInfo) {
        self.source = source
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
            Text(source.toolName)
        }
        .font(.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.indigo.opacity(0.15))
        .foregroundColor(.indigo)
        .cornerRadius(TrafficTheme.badgeCornerRadius)
    }
}

/// Бейдж серьёзности MCP-нарушения
public struct MCPSeverityBadge: View {
    let severity: MCPSeverity

    public init(severity: MCPSeverity) {
        self.severity = severity
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: severity.systemImage)
            Text(severity.displayName)
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(TrafficTheme.badgeCornerRadius)
    }

    private var color: Color {
        Color(severity.colorName)
    }
}

/// Маленький индикатор MCP (для отображения в списке трафика)
public struct MCPIndicator: View {
    let source: MCPSourceInfo
    let hasViolations: Bool

    public init(source: MCPSourceInfo, hasViolations: Bool = false) {
        self.source = source
        self.hasViolations = hasViolations
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption2)
            Text("MCP")
                .font(.caption2)
                .fontWeight(.bold)
            if hasViolations {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.teal.opacity(0.15))
        .foregroundColor(.teal)
        .cornerRadius(TrafficTheme.badgeCornerRadius)
    }
}
