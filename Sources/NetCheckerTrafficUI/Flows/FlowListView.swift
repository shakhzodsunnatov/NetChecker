import SwiftUI
import NetCheckerTrafficCore

/// Список сценариев
public struct NetCheckerTrafficUI_FlowListView: View {
    @ObservedObject private var store = FlowStore.shared
    @State private var isNaming = false
    @State private var newName = ""

    public init() {}

    public var body: some View {
        List {
            if store.flows.isEmpty {
                Section { emptyState }
            } else {
                ForEach(store.flows) { flow in
                    NavigationLink {
                        NetCheckerTrafficUI_FlowCanvasView(flow: flow)
                    } label: {
                        row(for: flow)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        store.remove(id: store.flows[index].id)
                    }
                }
            }
        }
        .navigationTitle("Flows")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isNaming = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Новый сценарий", isPresented: $isNaming) {
            TextField("Checkout Flow", text: $newName)
            Button("Отмена", role: .cancel) { newName = "" }
            Button("Создать") { create() }
        } message: {
            Text("Шаги добавите из пойманного трафика.")
        }
    }

    private func row(for flow: Flow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(flow.name)
                .font(.body)

            HStack(spacing: 6) {
                Text("\(flow.steps.count) шагов")

                if flow.hasCycle {
                    // Цикл нельзя выполнить — лучше сказать сразу,
                    // а не в момент запуска
                    Label("цикл", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if flow.levels().count > 1 {
                    Text("· \(flow.levels().count) уровней")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("Нет сценариев")
                .font(.headline)

            Text("Соберите цепочку из пойманных запросов и прогоняйте её одной кнопкой — вместо мок-сцены в коде и сборки в TestFlight.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            store.add(Flow(name: name))
        }
        newName = ""
    }
}
