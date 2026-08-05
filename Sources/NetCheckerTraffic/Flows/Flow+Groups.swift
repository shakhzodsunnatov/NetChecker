import Foundation

public extension Flow {

    // MARK: - Чтение

    func group(id: UUID) -> FlowGroup? {
        groups.first { $0.id == id }
    }

    /// Блок, в котором лежит шаг. Шаг принадлежит не более чем одному блоку
    func group(containing stepId: UUID) -> FlowGroup? {
        groups.first { $0.stepIds.contains(stepId) }
    }

    /// Шаги блока в его порядке; удалённые пропускаются
    func steps(in group: FlowGroup) -> [FlowStep] {
        group.stepIds.compactMap { step(id: $0) }
    }

    // MARK: - Создание и удаление

    @discardableResult
    mutating func addGroup(name: String, kind: FlowGroupKind = .parallel) -> FlowGroup {
        let group = FlowGroup(name: name, kind: kind)
        groups.append(group)
        return group
    }

    /// Убрать блок, оставив шаги на месте.
    ///
    /// Зависимости не трогаем: расставленный блоком порядок остаётся,
    /// иначе роспуск контейнера молча переделывал бы сценарий.
    mutating func dissolveGroup(id: UUID) {
        groups.removeAll { $0.id == id }
    }

    /// Убрать блок вместе со всеми шагами внутри
    mutating func removeGroup(id: UUID) {
        guard let group = group(id: id) else { return }
        removeSteps(ids: Set(group.stepIds))
        groups.removeAll { $0.id == id }
    }

    mutating func renameGroup(id: UUID, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
    }

    mutating func setKind(_ kind: FlowGroupKind, forGroup id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].kind = kind
        applyGroupWiring(id)
    }

    // MARK: - Состав

    /// Положить шаг в блок и переписать зависимости под смысл блока.
    ///
    /// Возвращает `false`, если так получился бы цикл: тогда состав
    /// и зависимости остаются прежними.
    @discardableResult
    mutating func addStep(_ stepId: UUID, toGroup groupId: UUID) -> Bool {
        guard step(id: stepId) != nil,
              let index = groups.firstIndex(where: { $0.id == groupId }) else { return false }

        let snapshot = self

        // Шаг живёт максимум в одном блоке
        for other in groups.indices where other != index {
            groups[other].stepIds.removeAll { $0 == stepId }
        }

        if !groups[index].stepIds.contains(stepId) {
            groups[index].stepIds.append(stepId)
        }

        applyGroupWiring(groupId)

        guard !hasCycle else {
            self = snapshot
            return false
        }
        return true
    }

    /// Вынуть шаг из блока. Зависимости остаются как есть — шаг
    /// продолжает выполняться там же, где выполнялся
    mutating func removeStep(_ stepId: UUID, fromGroup groupId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].stepIds.removeAll { $0 == stepId }
        applyGroupWiring(groupId)
    }

    /// Переставить шаг внутри блока. Для очереди это меняет порядок запуска
    mutating func moveStep(_ stepId: UUID, inGroup groupId: UUID, to position: Int) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }),
              let current = groups[index].stepIds.firstIndex(of: stepId) else { return }

        var ids = groups[index].stepIds
        ids.remove(at: current)
        ids.insert(stepId, at: min(max(position, 0), ids.count))
        groups[index].stepIds = ids

        applyGroupWiring(groupId)
    }

    // MARK: - Расстановка зависимостей

    /// Привести зависимости в соответствие смыслу блока.
    ///
    /// Единственное место, где блок влияет на выполнение: движок про блоки
    /// не знает и продолжает читать только `dependsOn`.
    mutating func applyGroupWiring(_ groupId: UUID) {
        guard let group = group(id: groupId) else { return }

        let members = group.stepIds.filter { id in steps.contains { $0.id == id } }
        guard !members.isEmpty else { return }

        let memberSet = Set(members)

        // До блока: всё, чего ждут его участники, кроме них самих
        let predecessors = members
            .compactMap { step(id: $0) }
            .flatMap(\.dependsOn)
            .filter { !memberSet.contains($0) }
        let entry = Array(Set(predecessors))

        // После блока: те, кто ждал хоть кого-то изнутри
        let successors = steps
            .filter { !memberSet.contains($0.id) }
            .filter { !Set($0.dependsOn).isDisjoint(with: memberSet) }
            .map(\.id)

        switch group.kind {
        case .parallel:
            for id in members {
                guard var member = step(id: id) else { continue }
                member.dependsOn = entry
                update(member)
            }
            // Ждать всех: иначе следующий шаг стартовал бы,
            // когда часть блока ещё в полёте
            rewire(successors, toWaitFor: members, insteadOf: memberSet)

        case .sequence:
            for (offset, id) in members.enumerated() {
                guard var member = step(id: id) else { continue }
                member.dependsOn = offset == 0 ? entry : [members[offset - 1]]
                update(member)
            }
            if let last = members.last {
                rewire(successors, toWaitFor: [last], insteadOf: memberSet)
            }
        }
    }

    private mutating func rewire(_ successors: [UUID], toWaitFor members: [UUID], insteadOf old: Set<UUID>) {
        for id in successors {
            guard var successor = step(id: id) else { continue }
            successor.dependsOn.removeAll { old.contains($0) }
            successor.dependsOn.append(contentsOf: members)
            update(successor)
        }
    }

    // MARK: - Копирование шага

    /// Копия шага рядом с оригиналом.
    ///
    /// Один и тот же запрос часто нужен дважды с разными значениями,
    /// и собирать его заново из трафика — лишняя работа.
    @discardableResult
    mutating func duplicateStep(id: UUID) -> FlowStep? {
        guard let original = step(id: id) else { return nil }

        var copy = original
        copy.id = UUID()
        copy.name = original.name + " (копия)"

        // Имена значений должны остаться уникальными: иначе два шага
        // писали бы в одну ячейку контекста прогона
        var taken = Set(steps.flatMap { $0.outputs.map(\.name) })
        copy.outputs = original.outputs.map { output in
            var renamed = output
            renamed.name = Flow.uniqueName(for: output.name, avoiding: taken)
            taken.insert(renamed.name)
            return renamed
        }

        if let index = steps.firstIndex(where: { $0.id == id }) {
            steps.insert(copy, at: steps.index(after: index))
        } else {
            steps.append(copy)
        }

        if let group = group(containing: id),
           let groupIndex = groups.firstIndex(where: { $0.id == group.id }),
           let position = groups[groupIndex].stepIds.firstIndex(of: id) {
            groups[groupIndex].stepIds.insert(copy.id, at: groups[groupIndex].stepIds.index(after: position))
            applyGroupWiring(group.id)
        }

        return copy
    }

    static func uniqueName(for base: String, avoiding taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains("\(base)\(index)") { index += 1 }
        return "\(base)\(index)"
    }
}
