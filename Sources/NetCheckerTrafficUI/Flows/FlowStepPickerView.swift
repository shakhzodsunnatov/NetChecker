import SwiftUI
import NetCheckerTrafficCore

/// Добавление шагов из пойманного трафика.
///
/// Тот же множественный выбор, что и в пометке тегами, но с номерами:
/// порядок отметки задаёт порядок шагов.
struct FlowStepPickerView: View {
    let onDone: ([TrafficRecord]) -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = TrafficStore.shared
    @State private var selected: [UUID] = []

    var body: some View {
        Group {
            if store.records.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Добавить шаги")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Добавить (\(selected.count))") {
                    onDone(selected.compactMap { store.record(for: $0) })
                    dismiss()
                }
                .disabled(selected.isEmpty)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(store.records, id: \.compositeId) { record in
                Button {
                    toggle(record.id)
                } label: {
                    HStack(spacing: 10) {
                        orderBadge(for: record.id)
                        TrafficRecordRow(record: record)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("Трафик пуст")
                .font(.headline)

            Text("Сделайте запросы в приложении — они появятся здесь, и из них можно будет собрать сценарий.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Номер вместо галочки: он и есть порядок шага в сценарии
    @ViewBuilder
    private func orderBadge(for id: UUID) -> some View {
        if let index = selected.firstIndex(of: id) {
            ZStack {
                Circle().fill(Color.accentColor).frame(width: 24, height: 24)
                Text("\(index + 1)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
            }
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .imageScale(.large)
                .frame(width: 24, height: 24)
        }
    }

    private func toggle(_ id: UUID) {
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else {
            selected.append(id)
        }
    }
}
