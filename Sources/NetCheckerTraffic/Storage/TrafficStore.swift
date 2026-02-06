import Foundation
import Combine

/// Центральное хранилище записей трафика
@MainActor
public final class TrafficStore: ObservableObject {
    // MARK: - Singleton

    /// Общий экземпляр
    public static let shared = TrafficStore()

    // MARK: - Published Properties

    /// Все записи
    @Published public private(set) var records: [TrafficRecord] = []

    /// Количество записей
    @Published public private(set) var count: Int = 0

    /// Количество ошибок
    @Published public private(set) var errorCount: Int = 0

    /// Количество pending запросов
    @Published public private(set) var pendingCount: Int = 0

    // MARK: - Configuration

    /// Максимальное количество записей (ring buffer)
    public var maxRecords: Int = 1000

    /// Включена ли запись
    public var isRecordingEnabled: Bool = true

    // MARK: - Private Properties

    private var recordsById: [UUID: Int] = [:]
    private let queue = DispatchQueue(label: "com.netchecker.trafficstore", qos: .utility)

    // MARK: - Callbacks

    /// Callback при добавлении новой записи
    public var onNewRecord: ((TrafficRecord) -> Void)?

    /// Callback при обновлении записи
    public var onRecordUpdated: ((TrafficRecord) -> Void)?

    /// Callback при ошибке
    public var onError: ((TrafficRecord) -> Void)?

    // MARK: - Publishers

    /// Publisher для изменений
    public var recordsPublisher: AnyPublisher<[TrafficRecord], Never> {
        $records.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    public init(maxRecords: Int = 1000) {
        self.maxRecords = maxRecords
    }

    // MARK: - Public Methods

    /// Добавить новую запись
    public func add(_ record: TrafficRecord) {
        guard isRecordingEnabled else { return }

        // Ring buffer - удаляем старые записи
        while records.count >= maxRecords {
            let removed = records.removeFirst()
            recordsById.removeValue(forKey: removed.id)
        }

        records.append(record)
        recordsById[record.id] = records.count - 1

        updateCounts()
        onNewRecord?(record)
    }

    /// Обновить существующую запись
    public func update(_ record: TrafficRecord) {
        guard let index = recordsById[record.id], index < records.count else {
            // Record not found, add it
            add(record)
            return
        }

        // Explicitly notify SwiftUI before changing
        objectWillChange.send()

        records[index] = record
        updateCounts()
        onRecordUpdated?(record)

        // Notify if error
        if case .failed = record.state {
            onError?(record)
        }
    }

    /// Обновить запись по ID
    public func update(id: UUID, with modifier: (inout TrafficRecord) -> Void) {
        guard let index = recordsById[id], index < records.count else { return }

        var record = records[index]
        modifier(&record)

        // Explicitly notify SwiftUI before changing
        objectWillChange.send()

        records[index] = record

        updateCounts()
        onRecordUpdated?(record)

        if case .failed = record.state {
            onError?(record)
        }
    }

    /// Завершить запись с ответом
    public func complete(
        id: UUID,
        response: ResponseData,
        timings: RequestTimings? = nil,
        security: SecurityInfo? = nil
    ) {
        update(id: id) { record in
            record.complete(with: response, timings: timings, security: security)
        }
    }

    /// Пометить запись как неудавшуюся
    public func fail(id: UUID, error: Error) {
        update(id: id) { record in
            record.fail(with: error)
        }
    }

    /// Получить запись по ID
    public func record(for id: UUID) -> TrafficRecord? {
        guard let index = recordsById[id], index < records.count else { return nil }
        return records[index]
    }

    /// Очистить все записи
    public func clear() {
        records.removeAll()
        recordsById.removeAll()
        updateCounts()
    }

    /// Удалить записи по фильтру
    public func remove(matching filter: TrafficFilter) {
        let filtered = filter.apply(to: records)
        let idsToRemove = Set(filtered.map { $0.id })

        records.removeAll { idsToRemove.contains($0.id) }
        rebuildIndex()
        updateCounts()
    }

    /// Удалить запись по ID
    public func remove(id: UUID) {
        guard let index = recordsById[id], index < records.count else { return }
        records.remove(at: index)
        rebuildIndex()
        updateCounts()
    }

    /// Получить записи с фильтром
    public func records(matching filter: TrafficFilter) -> [TrafficRecord] {
        filter.apply(to: records)
    }

    /// Получить последние N записей
    public func lastRecords(_ count: Int) -> [TrafficRecord] {
        Array(records.suffix(count))
    }

    /// Получить записи за период
    public func records(from: Date, to: Date) -> [TrafficRecord] {
        records.filter { $0.timestamp >= from && $0.timestamp <= to }
    }

    // MARK: - AsyncStream

    /// AsyncStream для получения новых записей
    public func recordsStream() -> AsyncStream<TrafficRecord> {
        AsyncStream { continuation in
            let callback = self.onNewRecord
            self.onNewRecord = { record in
                callback?(record)
                continuation.yield(record)
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.onNewRecord = callback
                }
            }
        }
    }

    // MARK: - Private Methods

    private func updateCounts() {
        count = records.count
        errorCount = records.filter { $0.isError }.count
        pendingCount = records.filter {
            if case .pending = $0.state { return true }
            return false
        }.count
    }

    private func rebuildIndex() {
        recordsById.removeAll()
        for (index, record) in records.enumerated() {
            recordsById[record.id] = index
        }
    }
}

// MARK: - Export

extension TrafficStore {
    /// Экспортировать записи в формате
    public func export(format: ExportFormat, filter: TrafficFilter? = nil) -> Data? {
        let recordsToExport = filter?.apply(to: records) ?? records

        switch format {
        case .json:
            return try? JSONEncoder().encode(recordsToExport)
        case .har:
            return HARFormatter.format(records: recordsToExport)
        case .curl:
            let curls = recordsToExport.map { CURLFormatter.format(record: $0) }
            return curls.joined(separator: "\n\n---\n\n").data(using: .utf8)
        }
    }
}

/// Формат экспорта
public enum ExportFormat: String, CaseIterable, Sendable {
    case json
    case har
    case curl

    public var fileExtension: String {
        switch self {
        case .json: return "json"
        case .har: return "har"
        case .curl: return "sh"
        }
    }

    public var mimeType: String {
        switch self {
        case .json: return "application/json"
        case .har: return "application/json"
        case .curl: return "text/plain"
        }
    }
}
