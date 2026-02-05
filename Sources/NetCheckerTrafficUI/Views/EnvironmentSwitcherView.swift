import SwiftUI
import NetCheckerTrafficCore

/// View for switching between environments
public struct NetCheckerTrafficUI_EnvironmentSwitcherView: View {
    @ObservedObject private var store = EnvironmentStore.shared
    @State private var showingAddGroup = false
    @State private var showingAddEnvironment = false
    @State private var selectedGroup: EnvironmentGroup?

    public init() {}

    public var body: some View {
        List {
            // Quick override section
            if store.quickOverrideURL != nil {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Quick Override Active")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(store.quickOverrideURL?.absoluteString ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
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

            // Environment groups
            ForEach(store.groups) { group in
                Section {
                    EnvironmentGroupView(
                        group: group,
                        selectedGroup: $selectedGroup,
                        showingAddEnvironment: $showingAddEnvironment
                    )
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text(group.sourcePattern)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Add group
            Section {
                Button {
                    showingAddGroup = true
                } label: {
                    Label("Add Environment Group", systemImage: "plus.circle")
                }
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
                            selectedGroup = group
                            showingAddEnvironment = true
                        } label: {
                            Label("Add Environment", systemImage: "plus")
                        }
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
        .sheet(isPresented: $showingAddEnvironment) {
            if let group = selectedGroup {
                NavigationStack {
                    NetCheckerTrafficUI_AddEnvironmentView(group: group)
                }
            }
        }
    }
}

// MARK: - Environment Group View

struct EnvironmentGroupView: View {
    let group: EnvironmentGroup
    @Binding var selectedGroup: EnvironmentGroup?
    @Binding var showingAddEnvironment: Bool

    @ObservedObject private var store = EnvironmentStore.shared

    var body: some View {
        ForEach(group.environments) { env in
            EnvironmentRowView(
                environment: env,
                isActive: group.activeEnvironmentId == env.id,
                onSelect: {
                    store.switchEnvironment(groupId: group.id, to: env.id)
                }
            )
        }
        .onDelete { indexSet in
            for index in indexSet {
                store.removeEnvironment(group.environments[index].id, from: group.id)
            }
        }

        Button {
            selectedGroup = group
            showingAddEnvironment = true
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

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(environment.emoji)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(environment.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(environment.baseURL.absoluteString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
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

    var body: some View {
        Form {
            Section {
                TextField("Group Name (e.g., API Server)", text: $name)
                #if os(iOS)
                TextField("Host Pattern (e.g., api.example.com)", text: $sourcePattern)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                #else
                TextField("Host Pattern (e.g., api.example.com)", text: $sourcePattern)
                    .autocorrectionDisabled()
                #endif
            } footer: {
                Text("The host pattern will match requests to redirect to different environments")
            }
        }
        .navigationTitle("Add Group")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let group = EnvironmentGroup(
                        name: name,
                        sourcePattern: sourcePattern
                    )
                    store.addGroup(group)
                    dismiss()
                }
                .disabled(name.isEmpty || sourcePattern.isEmpty)
            }
        }
    }
}

#Preview {
    NavigationStack {
        NetCheckerTrafficUI_EnvironmentSwitcherView()
    }
}
