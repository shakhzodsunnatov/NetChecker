import Foundation

/// Сценарий — ациклический граф шагов.
///
/// Не линейная цепочка: нужны параллельные ветки и развилки. Шаг стартует,
/// когда завершились все, от кого он зависит, — из одного этого правила
/// выводятся и строгая последовательность, и параллельный старт,
/// и ожидание обоих, и «отправить и не ждать».
public struct Flow: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var steps: [FlowStep]
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, steps: [FlowStep] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.steps = steps
        self.createdAt = createdAt
    }

    public func step(id: UUID) -> FlowStep? {
        steps.first { $0.id == id }
    }

    /// Никто не ждёт этот шаг — «триггер на всякий случай».
    /// Помечается в интерфейсе, иначе непонятно, почему сценарий
    /// завершился, пока такой запрос ещё летит.
    public func isFireAndForget(_ step: FlowStep) -> Bool {
        !steps.contains { $0.dependsOn.contains(step.id) }
    }

    /// Граф содержит цикл и не может быть выполнен
    public var hasCycle: Bool {
        !steps.isEmpty && levelsIfAcyclic() == nil
    }

    /// Уровни выполнения: всё внутри уровня идёт одновременно.
    /// Пустой массив означает либо пустой сценарий, либо цикл.
    public func levels() -> [[FlowStep]] {
        levelsIfAcyclic() ?? []
    }

    /// Топологическая сортировка по уровням, алгоритм Кана.
    ///
    /// `nil` означает цикл: остались шаги, зависимости которых
    /// так и не разрешились.
    private func levelsIfAcyclic() -> [[FlowStep]]? {
        guard !steps.isEmpty else { return [] }

        let known = Set(steps.map(\.id))
        var remaining = steps
        var resolved = Set<UUID>()
        var result: [[FlowStep]] = []

        while !remaining.isEmpty {
            // Ссылки на несуществующие шаги игнорируются: иначе удаление
            // одного шага намертво заклинило бы весь сценарий
            let ready = remaining.filter { step in
                step.dependsOn.allSatisfy { !known.contains($0) || resolved.contains($0) }
            }

            guard !ready.isEmpty else { return nil }

            result.append(ready)
            resolved.formUnion(ready.map(\.id))
            let readyIds = Set(ready.map(\.id))
            remaining.removeAll { readyIds.contains($0.id) }
        }

        return result
    }
}
