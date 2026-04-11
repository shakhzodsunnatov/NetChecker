import Foundation

/// Статус потока
public enum MCPFlowStatus: String, Codable, Sendable {
    case active
    case completed
    case failed
}

/// Запись в потоке (ссылка на TrafficRecord)
public struct MCPFlowEntry: Codable, Sendable, Identifiable {
    /// ID записи в TrafficStore
    public let id: UUID

    /// Порядковый номер
    public let sequenceNumber: Int

    /// Тип операции
    public let operationType: MCPOperationType

    /// Серьёзность
    public let severity: MCPSeverity

    /// Нарушения
    public let violations: [MCPViolation]

    /// Временная метка
    public let timestamp: Date

    public init(
        id: UUID,
        sequenceNumber: Int,
        operationType: MCPOperationType,
        severity: MCPSeverity = .info,
        violations: [MCPViolation] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sequenceNumber = sequenceNumber
        self.operationType = operationType
        self.severity = severity
        self.violations = violations
        self.timestamp = timestamp
    }
}

/// Поток — группа связанных операций
public struct MCPFlow: Codable, Sendable, Identifiable {
    /// Уникальный ID потока
    public var id: UUID

    /// Название потока / задачи
    public var name: String

    /// Описание
    public var flowDescription: String?

    /// Источник
    public var source: MCPSourceInfo

    /// Начало потока
    public var startedAt: Date

    /// Завершение потока
    public var completedAt: Date?

    /// Записи в потоке (упорядочены)
    public var entries: [MCPFlowEntry]

    /// Статус
    public var status: MCPFlowStatus

    /// Все нарушения в потоке (агрегированные)
    public var violations: [MCPViolation] {
        entries.flatMap { $0.violations }
    }

    /// Длительность потока
    public var duration: TimeInterval? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    /// Количество ошибок
    public var errorCount: Int {
        entries.filter { $0.severity >= .error }.count
    }

    public init(
        id: UUID,
        name: String,
        flowDescription: String? = nil,
        source: MCPSourceInfo,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        entries: [MCPFlowEntry] = [],
        status: MCPFlowStatus = .active
    ) {
        self.id = id
        self.name = name
        self.flowDescription = flowDescription
        self.source = source
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.entries = entries
        self.status = status
    }
}

/// Трекер потоков — управляет активными и завершёнными потоками
@MainActor
public final class MCPFlowTracker: ObservableObject {
    // MARK: - Singleton

    /// Общий экземпляр
    public static let shared = MCPFlowTracker()

    // MARK: - Published Properties

    /// Активные потоки
    @Published public private(set) var activeFlows: [MCPFlow] = []

    /// Завершённые потоки (ring buffer)
    @Published public private(set) var completedFlows: [MCPFlow] = []

    // MARK: - Configuration

    /// Максимальное количество завершённых потоков
    public var maxCompletedFlows: Int = 100

    // MARK: - Private

    private var flowsById: [UUID: Int] = [:]

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Начать новый поток
    @discardableResult
    public func startFlow(
        id: UUID,
        name: String,
        description: String? = nil,
        source: MCPSourceInfo
    ) -> MCPFlow {
        let flow = MCPFlow(
            id: id,
            name: name,
            flowDescription: description,
            source: source
        )

        activeFlows.append(flow)
        flowsById[id] = activeFlows.count - 1

        print("[NetChecker MCP] Поток начат: \(name) (\(id))")
        return flow
    }

    /// Добавить запись в поток
    public func addEntry(flowId: UUID, entry: MCPLogEntry) {
        guard let index = flowsById[flowId], index < activeFlows.count else {
            // Поток не найден — создаём автоматически
            if let flowContext = entry.flowContext {
                startFlow(
                    id: flowId,
                    name: flowContext.flowName,
                    description: flowContext.flowDescription,
                    source: entry.source
                )
                addEntry(flowId: flowId, entry: entry)
            }
            return
        }

        let flowEntry = MCPFlowEntry(
            id: entry.id,
            sequenceNumber: entry.flowContext?.sequenceNumber ?? activeFlows[index].entries.count,
            operationType: entry.operationType,
            severity: entry.severity,
            violations: entry.expectations?.violations ?? [],
            timestamp: entry.timestamp
        )

        activeFlows[index].entries.append(flowEntry)
    }

    /// Завершить поток
    @discardableResult
    public func endFlow(id: UUID) -> MCPFlow? {
        guard let index = flowsById[id], index < activeFlows.count else {
            return nil
        }

        var flow = activeFlows[index]
        flow.completedAt = Date()
        flow.status = flow.violations.isEmpty ? .completed : .failed

        // Перемещаем из active в completed
        activeFlows.remove(at: index)
        rebuildIndex()

        // Ring buffer для completed
        while completedFlows.count >= maxCompletedFlows {
            completedFlows.removeFirst()
        }
        completedFlows.append(flow)

        print("[NetChecker MCP] Поток завершён: \(flow.name) (\(flow.entries.count) записей, \(flow.violations.count) нарушений)")
        return flow
    }

    /// Получить поток по ID
    public func flow(for id: UUID) -> MCPFlow? {
        if let index = flowsById[id], index < activeFlows.count {
            return activeFlows[index]
        }
        return completedFlows.first { $0.id == id }
    }

    /// ID записей TrafficRecord для потока
    public func recordIds(for flowId: UUID) -> [UUID] {
        guard let flow = flow(for: flowId) else { return [] }
        return flow.entries.map { $0.id }
    }

    /// Очистить все потоки
    public func clear() {
        activeFlows.removeAll()
        completedFlows.removeAll()
        flowsById.removeAll()
    }

    // MARK: - Private

    private func rebuildIndex() {
        flowsById.removeAll()
        for (index, flow) in activeFlows.enumerated() {
            flowsById[flow.id] = index
        }
    }
}
