import Foundation

/// Что блок делает со своим содержимым
public enum FlowGroupKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// Всё внутри уходит одновременно, следующий шаг ждёт всех
    case parallel
    /// Внутри строгая очередь, следующий шаг ждёт последнего
    case sequence

    public var title: String {
        switch self {
        case .parallel: return "Одновременно"
        case .sequence: return "По очереди"
        }
    }

    public var explanation: String {
        switch self {
        case .parallel: return "Всё внутри уходит сразу. Следующий шаг ждёт, пока вернутся все."
        case .sequence: return "Внутри — строгая очередь. Следующий шаг ждёт последнего."
        }
    }

    public var systemImage: String {
        switch self {
        case .parallel: return "arrow.triangle.branch"
        case .sequence: return "arrow.down.to.line"
        }
    }
}

/// Блок сценария — контейнер, в который складывают шаги.
///
/// Порядок в сценарии задаётся зависимостями, и раньше сделать два запроса
/// параллельными означало эти зависимости убрать. Мысль при этом обратная:
/// «сложить их в один блок». Блок и есть эта мысль; зависимости он
/// расставляет сам.
public struct FlowGroup: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var kind: FlowGroupKind
    /// Порядок важен для очереди и задаёт порядок отрисовки
    public var stepIds: [UUID]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: FlowGroupKind = .parallel,
        stepIds: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.stepIds = stepIds
    }

    public var isEmpty: Bool { stepIds.isEmpty }
}
