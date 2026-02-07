import SwiftUI
import NetCheckerTrafficCore

// Type alias to avoid collision with SwiftUI.Environment
public typealias AppEnvironment = NetCheckerTrafficCore.Environment

/// Badge showing current environment
public struct NetCheckerTrafficUI_EnvironmentBadge: View {
    let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(environment.emoji)
                .font(.caption)

            Text(environment.name)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(environmentColor.opacity(0.15))
        .foregroundColor(environmentColor)
        .cornerRadius(TrafficTheme.badgeCornerRadius)
    }

    private var environmentColor: Color {
        inferEnvironmentColor(from: environment.name)
    }
}

/// Compact environment indicator
public struct EnvironmentIndicator: View {
    @ObservedObject private var store = EnvironmentStore.shared

    public init() {}

    public var body: some View {
        if let activeEnv = store.activeEnvironment {
            HStack(spacing: 4) {
                Circle()
                    .fill(inferEnvironmentColor(from: activeEnv.name))
                    .frame(width: 8, height: 8)

                Text(activeEnv.name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } else {
            Text("No Environment")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

/// Environment picker inline view
public struct EnvironmentPickerView: View {
    @ObservedObject private var store = EnvironmentStore.shared
    let sourcePattern: String

    public init(sourcePattern: String) {
        self.sourcePattern = sourcePattern
    }

    public var body: some View {
        if let group = store.groups.first(where: { $0.sourcePattern == sourcePattern }) {
            Menu {
                ForEach(group.environments) { env in
                    Button {
                        store.switchEnvironment(groupId: group.id, to: env.id)
                    } label: {
                        HStack {
                            Text(env.emoji)
                            Text(env.name)
                            if group.activeEnvironmentId == env.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                if let active = group.activeEnvironment {
                    NetCheckerTrafficUI_EnvironmentBadge(environment: active)
                } else {
                    Text("Select Environment")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } else {
            Text("No matching group")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// Quick environment toggle buttons
public struct QuickEnvironmentToggle: View {
    @ObservedObject private var store = EnvironmentStore.shared
    let group: EnvironmentGroup

    public init(group: EnvironmentGroup) {
        self.group = group
    }

    public var body: some View {
        if group.environments.isEmpty {
            Text("No environments configured")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            HStack(spacing: 8) {
                ForEach(group.environments) { env in
                    Button {
                        store.switchEnvironment(groupId: group.id, to: env.id)
                    } label: {
                        let isActive = group.activeEnvironmentId == env.id
                        VStack(spacing: 2) {
                            Text(env.emoji)
                                .font(.title3)
                            Text(env.name)
                                .font(.caption2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            isActive
                                ? inferEnvironmentColor(from: env.name).opacity(0.2)
                                : Color.gray.opacity(0.15)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isActive
                                        ? inferEnvironmentColor(from: env.name)
                                        : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Active environment banner for traffic list
public struct ActiveEnvironmentBanner: View {
    @ObservedObject private var store = EnvironmentStore.shared

    public init() {}

    public var body: some View {
        if let activeEnv = store.activeEnvironment, !activeEnv.isDefault {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Non-Production Environment Active")
                        .font(.caption)
                        .fontWeight(.medium)

                    Text("\(activeEnv.emoji) \(activeEnv.name) - \(activeEnv.host)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    store.resetToProduction()
                } label: {
                    Text("Reset")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
        }
    }
}

/// Infer environment color from name
func inferEnvironmentColor(from name: String) -> Color {
    let lowercased = name.lowercased()
    if lowercased.contains("prod") {
        return TrafficTheme.productionColor
    } else if lowercased.contains("staging") || lowercased.contains("stage") {
        return TrafficTheme.stagingColor
    } else if lowercased.contains("dev") {
        return TrafficTheme.developmentColor
    } else if lowercased.contains("local") {
        return TrafficTheme.localColor
    } else {
        return .purple
    }
}

#Preview {
    VStack(spacing: 20) {
        NetCheckerTrafficUI_EnvironmentBadge(
            environment: AppEnvironment(
                name: "Production",
                emoji: "🚀",
                baseURL: URL(string: "https://api.example.com")!
            )
        )

        NetCheckerTrafficUI_EnvironmentBadge(
            environment: AppEnvironment(
                name: "Staging",
                emoji: "🔧",
                baseURL: URL(string: "https://staging.example.com")!
            )
        )

        NetCheckerTrafficUI_EnvironmentBadge(
            environment: AppEnvironment(
                name: "Local",
                emoji: "🏠",
                baseURL: URL(string: "http://localhost:8080")!
            )
        )

        EnvironmentIndicator()

        ActiveEnvironmentBanner()
    }
    .padding()
}
