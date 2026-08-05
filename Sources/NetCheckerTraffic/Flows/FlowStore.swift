import Foundation

/// Хранилище сценариев
@MainActor
public final class FlowStore: ObservableObject {
    public static let shared = FlowStore()

    @Published public private(set) var flows: [Flow] = [] {
        didSet { persist() }
    }

    private let storageKey = "NetCheckerFlows"

    private init() {
        load()
    }

    // MARK: - Доступ

    public func flow(id: UUID) -> Flow? {
        flows.first { $0.id == id }
    }

    public func add(_ flow: Flow) {
        flows.insert(flow, at: 0)
    }

    public func update(_ flow: Flow) {
        guard let index = flows.firstIndex(where: { $0.id == flow.id }) else { return }
        flows[index] = flow
    }

    public func remove(id: UUID) {
        flows.removeAll { $0.id == id }
    }

    public func removeAll() {
        flows.removeAll()
    }

    // MARK: - Сборка

    /// Собрать сценарий из выбранных записей трафика.
    ///
    /// Шаги связываются последовательно, в порядке выбора: это ожидаемое
    /// поведение по умолчанию. Параллельность и развилки настраиваются потом,
    /// изменением связей.
    public func makeFlow(name: String, from records: [TrafficRecord]) -> Flow {
        var steps: [FlowStep] = []

        for record in records {
            steps.append(
                FlowStep(
                    name: "\(record.request.method.rawValue) \(record.path)",
                    request: record.request,
                    dependsOn: steps.last.map { [$0.id] } ?? []
                )
            )
        }

        return Flow(name: name, steps: steps)
    }

    /// То же из сохранённых помеченных запросов — они переживают перезапуск,
    /// поэтому собрать сценарий можно и в новой сессии
    public func makeFlow(name: String, from archived: [ArchivedRequest]) -> Flow {
        var steps: [FlowStep] = []

        for request in archived {
            steps.append(
                FlowStep(
                    name: "\(request.method.rawValue) \(request.path)",
                    request: request.requestData,
                    dependsOn: steps.last.map { [$0.id] } ?? []
                )
            )
        }

        return Flow(name: name, steps: steps)
    }

    // MARK: - Персистентность

    private func persist() {
        guard let data = try? JSONEncoder().encode(flows) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([Flow].self, from: data) else { return }
        flows = stored
    }
}
