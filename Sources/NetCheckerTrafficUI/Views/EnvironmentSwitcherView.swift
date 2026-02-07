import SwiftUI
import NetCheckerTrafficCore

/// View for switching between environments
public struct NetCheckerTrafficUI_EnvironmentSwitcherView: View {
    @ObservedObject private var store = EnvironmentStore.shared
    @State private var showingAddGroup = false
    @State private var groupForNewEnvironment: EnvironmentGroup?
    @State private var environmentToEdit: (environment: NetCheckerTrafficCore.Environment, groupId: UUID)?

    public init() {}

    public var body: some View {
        Group {
            if store.groups.isEmpty {
                EmptyEnvironmentsView(onAddGroup: { showingAddGroup = true })
            } else {
                environmentList
            }
        }
        .navigationTitle("Environments")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddGroup = true
                    } label: {
                        Label("Add Group", systemImage: "folder.badge.plus")
                    }

                    if let group = store.groups.first {
                        Button {
                            groupForNewEnvironment = group
                        } label: {
                            Label("Add Environment", systemImage: "plus")
                        }
                    }

                    Divider()

                    Button {
                        store.resetToProduction()
                    } label: {
                        Label("Reset to Production", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddGroup) {
            NavigationStack {
                AddEnvironmentGroupView()
            }
        }
        .sheet(item: $groupForNewEnvironment) { group in
            NavigationStack {
                NetCheckerTrafficUI_AddEnvironmentView(group: group)
            }
        }
        .sheet(item: Binding(
            get: { environmentToEdit.map { EditableEnvironment(environment: $0.environment, groupId: $0.groupId) } },
            set: { environmentToEdit = $0.map { ($0.environment, $0.groupId) } }
        )) { item in
            NavigationStack {
                EditEnvironmentView(groupId: item.groupId, environment: item.environment)
            }
        }
    }

    private var environmentList: some View {
        List {
            // Quick override section
            if store.hasActiveOverride {
                Section {
                    QuickOverrideRow()
                }
            }

            // Environment groups
            ForEach(store.groups) { group in
                Section {
                    if group.environments.isEmpty {
                        EmptyGroupRow(group: group, onAddEnvironment: {
                            groupForNewEnvironment = group
                        })
                    } else {
                        EnvironmentGroupView(
                            group: group,
                            onAddEnvironment: {
                                groupForNewEnvironment = group
                            },
                            onEditEnvironment: { env in
                                environmentToEdit = (env, group.id)
                            }
                        )
                    }
                } header: {
                    GroupHeaderView(group: group)
                }
            }
            .onDelete(perform: deleteGroups)

            // Add group button
            Section {
                Button {
                    showingAddGroup = true
                } label: {
                    Label("Add Environment Group", systemImage: "plus.circle")
                }
            }
        }
    }

    private func deleteGroups(at offsets: IndexSet) {
        for index in offsets {
            store.removeGroup(id: store.groups[index].id)
        }
    }
}

// MARK: - Helper for sheet binding

private struct EditableEnvironment: Identifiable {
    let id: UUID
    let environment: NetCheckerTrafficCore.Environment
    let groupId: UUID

    init(environment: NetCheckerTrafficCore.Environment, groupId: UUID) {
        self.id = environment.id
        self.environment = environment
        self.groupId = groupId
    }
}

// MARK: - Empty States

struct EmptyEnvironmentsView: View {
    let onAddGroup: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Environments Configured")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create environment groups to manage different servers like Production, Staging, and Development.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                onAddGroup()
            } label: {
                Label("Add Environment Group", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 10)
        }
        .padding()
    }
}

struct EmptyGroupRow: View {
    let group: EnvironmentGroup
    let onAddEnvironment: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("No environments in this group")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button {
                onAddEnvironment()
            } label: {
                Label("Add Environment", systemImage: "plus")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Group Header View

struct GroupHeaderView: View {
    let group: EnvironmentGroup

    var body: some View {
        HStack {
            Text(group.name)

            Spacer()

            Text(group.sourcePattern)
                .font(.caption)
                .foregroundColor(.secondary)

            if !group.isProductionActive {
                Text("Non-Prod")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
            }
        }
    }
}

// MARK: - Quick Override Row

struct QuickOverrideRow: View {
    @ObservedObject private var store = EnvironmentStore.shared

    var body: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Quick Override Active")
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let url = store.quickOverrideURL {
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                store.clearQuickOverride()
            } label: {
                Text("Clear")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Environment Group View

struct EnvironmentGroupView: View {
    let group: EnvironmentGroup
    let onAddEnvironment: () -> Void
    let onEditEnvironment: (NetCheckerTrafficCore.Environment) -> Void

    @ObservedObject private var store = EnvironmentStore.shared

    var body: some View {
        ForEach(group.environments) { env in
            EnvironmentRowView(
                environment: env,
                isActive: group.activeEnvironmentId == env.id,
                onSelect: {
                    store.switchEnvironment(groupId: group.id, to: env.id)
                },
                onEdit: {
                    onEditEnvironment(env)
                }
            )
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    store.removeEnvironment(env.id, from: group.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    onEditEnvironment(env)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }

        Button {
            onAddEnvironment()
        } label: {
            Label("Add Environment", systemImage: "plus")
                .font(.subheadline)
        }
    }
}

// MARK: - Environment Row View

struct EnvironmentRowView: View {
    let environment: NetCheckerTrafficCore.Environment
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(environment.emoji)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(environment.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        if environment.isDefault {
                            Text("Default")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(3)
                        }
                    }

                    Text(environment.baseURL.absoluteString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    // Show badges for headers/variables
                    if environment.hasHeaders || environment.hasVariables {
                        HStack(spacing: 8) {
                            if environment.hasHeaders {
                                Label("\(environment.headers.count) headers", systemImage: "list.bullet")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if environment.hasVariables {
                                Label("\(environment.variables.count) vars", systemImage: "chevron.left.forwardslash.chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Environment Group View

struct AddEnvironmentGroupView: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = EnvironmentStore.shared

    @State private var name = ""
    @State private var sourcePattern = ""
    @State private var createWithPresets = true

    var body: some View {
        Form {
            Section {
                TextField("Group Name (e.g., API Server)", text: $name)

                #if os(iOS)
                TextField("Host Pattern (e.g., api.example.com)", text: $sourcePattern)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                #else
                TextField("Host Pattern (e.g., api.example.com)", text: $sourcePattern)
                    .autocorrectionDisabled()
                #endif
            } footer: {
                Text("The host pattern will match requests to redirect to different environments. Use * for wildcards (e.g., *.example.com)")
            }

            Section {
                Toggle("Create with default environments", isOn: $createWithPresets)
            } footer: {
                if createWithPresets {
                    Text("Will create Production, Staging, and Development environments automatically")
                }
            }
        }
        .navigationTitle("Add Group")
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
                Button("Add") {
                    addGroup()
                }
                .disabled(name.isEmpty || sourcePattern.isEmpty)
            }
        }
    }

    private func addGroup() {
        var environments: [NetCheckerTrafficCore.Environment] = []

        if createWithPresets {
            // Create default environments based on the pattern
            let baseHost = sourcePattern.replacingOccurrences(of: "*", with: "")

            if let prodURL = URL(string: "https://\(baseHost)") {
                environments.append(.production(baseURL: prodURL))
            }

            if let stagingURL = URL(string: "https://staging.\(baseHost)") {
                environments.append(.staging(baseURL: stagingURL))
            }

            if let devURL = URL(string: "https://dev.\(baseHost)") {
                environments.append(.development(baseURL: devURL))
            }
        }

        let group = EnvironmentGroup(
            name: name,
            sourcePattern: sourcePattern,
            environments: environments
        )
        store.addGroup(group)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        NetCheckerTrafficUI_EnvironmentSwitcherView()
    }
}
