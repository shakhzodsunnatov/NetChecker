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

    // MARK: - Редактирование

    /// Заменить шаг на месте
    public mutating func update(_ step: FlowStep) {
        guard let index = steps.firstIndex(where: { $0.id == step.id }) else { return }
        steps[index] = step
    }

    /// Удалить шаг и все ссылки на него.
    ///
    /// Без очистки ссылок остались бы висячие зависимости: выполнению они не
    /// мешают, но в редакторе выглядели бы как связь с несуществующим шагом.
    public mutating func removeStep(id: UUID) {
        steps.removeAll { $0.id == id }
        for index in steps.indices {
            steps[index].dependsOn.removeAll { $0 == id }
        }
    }

    /// Значения, доступные шагу для подстановки.
    ///
    /// Только выходы шагов со строго более ранних уровней: сосед по уровню
    /// выполняется одновременно, и полагаться на его ответ нельзя.
    public func availableValueNames(before stepId: UUID) -> [String] {
        let allLevels = levels()
        guard let levelIndex = allLevels.firstIndex(where: { level in
            level.contains { $0.id == stepId }
        }) else { return [] }

        let earlier = allLevels.prefix(levelIndex).flatMap { $0 }
        return Array(Set(earlier.flatMap { $0.outputs.map(\.name) })).sorted()
    }

    /// Шаги, которые можно назначить зависимостями.
    ///
    /// Исключается сам шаг и всё, что от него зависит прямо или косвенно, —
    /// иначе получился бы цикл, и сценарий стал бы невыполнимым.
    public func possibleDependencies(for stepId: UUID) -> [FlowStep] {
        var blocked: Set<UUID> = [stepId]
        var frontier: Set<UUID> = [stepId]

        while !frontier.isEmpty {
            var next: Set<UUID> = []
            for step in steps where !blocked.contains(step.id) {
                guard !frontier.isDisjoint(with: step.dependsOn) else { continue }
                blocked.insert(step.id)
                next.insert(step.id)
            }
            frontier = next
        }

        return steps.filter { !blocked.contains($0.id) }
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
