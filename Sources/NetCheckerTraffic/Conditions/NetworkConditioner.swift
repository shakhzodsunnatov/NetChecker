import Foundation

/// Неизменяемый снимок условий сети.
/// Нужен потому, что `NetCheckerURLProtocol` работает вне главного актора
/// и не может обращаться к `@MainActor`-состоянию напрямую.
struct NetworkConditionSnapshot: Sendable {
    var isEnabled: Bool
    var latency: TimeInterval
    var downloadBytesPerSecond: Int?
    var packetLossRate: Double

    static let disabled = NetworkConditionSnapshot(
        isEnabled: false,
        latency: 0,
        downloadBytesPerSecond: nil,
        packetLossRate: 0
    )

    /// Условия реально влияют на запрос
    var isActive: Bool {
        isEnabled && (latency > 0 || downloadBytesPerSecond != nil || packetLossRate > 0)
    }

    /// Решить, потерять ли запрос
    func shouldDropRequest() -> Bool {
        guard isEnabled, packetLossRate > 0 else { return false }
        if packetLossRate >= 1 { return true }
        return Double.random(in: 0..<1) < packetLossRate
    }

    /// Разбить тело ответа на порции по бюджету скорости.
    /// Возвращает пары «порция данных — пауза перед её доставкой».
    func downloadChunks(for data: Data) -> [(chunk: Data, delay: TimeInterval)] {
        guard isEnabled, let bytesPerSecond = downloadBytesPerSecond, !data.isEmpty else {
            return [(data, 0)]
        }

        // Доставляем примерно десять порций в секунду — компромисс между
        // правдоподобностью и количеством пробуждений таймера.
        let chunkSize = max(1, bytesPerSecond / 10)
        guard data.count > chunkSize else {
            return [(data, TimeInterval(data.count) / TimeInterval(bytesPerSecond))]
        }

        var result: [(Data, TimeInterval)] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<end)
            result.append((chunk, TimeInterval(chunk.count) / TimeInterval(bytesPerSecond)))
            offset = end
        }
        return result
    }
}

/// Потокобезопасное хранилище активных условий сети
enum NetworkConditionState {
    private static let lock = NSLock()
    private static var _current: NetworkConditionSnapshot = .disabled

    static var current: NetworkConditionSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return _current
    }

    static func update(_ snapshot: NetworkConditionSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        _current = snapshot
    }
}

/// Симуляция условий сети: задержки, ограничение скорости, потери пакетов.
///
/// Влияет на весь перехватываемый трафик, в отличие от `MockEngine`,
/// который действует только на совпавшие правила.
@MainActor
public final class NetworkConditioner: ObservableObject {
    // MARK: - Singleton

    public static let shared = NetworkConditioner()

    // MARK: - Published Properties

    /// Включена ли симуляция
    @Published public var isEnabled: Bool = false {
        didSet {
            guard isEnabled != oldValue else { return }
            persist()
            syncSnapshot()
        }
    }

    /// Активный профиль
    @Published public var activeProfile: NetworkConditionProfile = .none {
        didSet {
            guard activeProfile != oldValue else { return }
            persist()
            syncSnapshot()
        }
    }

    /// Пользовательские профили
    @Published public private(set) var customProfiles: [NetworkConditionProfile] = [] {
        didSet { persist() }
    }

    // MARK: - Storage Keys

    private let enabledKey = "NetCheckerConditionsEnabled"
    private let profileKey = "NetCheckerConditionsActiveProfile"
    private let customKey = "NetCheckerConditionsCustomProfiles"

    // MARK: - Initialization

    private init() {
        load()
        syncSnapshot()
    }

    // MARK: - Public API

    /// Все доступные профили — встроенные и пользовательские
    public var allProfiles: [NetworkConditionProfile] {
        NetworkConditionProfile.builtIn + customProfiles
    }

    /// Включить симуляцию с указанным профилем
    public func apply(_ profile: NetworkConditionProfile) {
        activeProfile = profile
        isEnabled = !profile.isTransparent
    }

    /// Выключить симуляцию
    public func disable() {
        isEnabled = false
    }

    /// Добавить пользовательский профиль
    public func addProfile(_ profile: NetworkConditionProfile) {
        var stored = profile
        stored.isBuiltIn = false
        customProfiles.append(stored)
    }

    /// Обновить пользовательский профиль
    public func updateProfile(_ profile: NetworkConditionProfile) {
        guard let index = customProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        customProfiles[index] = profile
        if activeProfile.id == profile.id {
            activeProfile = profile
        }
    }

    /// Удалить пользовательский профиль
    public func removeProfile(id: UUID) {
        customProfiles.removeAll { $0.id == id }
        if activeProfile.id == id {
            activeProfile = .none
            isEnabled = false
        }
    }

    // MARK: - Private

    /// Опубликовать текущее состояние для потоков загрузки URL
    private func syncSnapshot() {
        NetworkConditionState.update(
            NetworkConditionSnapshot(
                isEnabled: isEnabled,
                latency: activeProfile.latency,
                downloadBytesPerSecond: activeProfile.downloadBytesPerSecond,
                packetLossRate: activeProfile.packetLossRate
            )
        )
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: enabledKey)

        if let data = try? JSONEncoder().encode(activeProfile) {
            defaults.set(data, forKey: profileKey)
        }
        if let data = try? JSONEncoder().encode(customProfiles) {
            defaults.set(data, forKey: customKey)
        }
    }

    private func load() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: customKey),
           let profiles = try? JSONDecoder().decode([NetworkConditionProfile].self, from: data) {
            customProfiles = profiles
        }

        if let data = defaults.data(forKey: profileKey),
           let profile = try? JSONDecoder().decode(NetworkConditionProfile.self, from: data) {
            activeProfile = profile
        }

        // Читаем последним: присваивание профиля выше могло сбросить флаг
        isEnabled = defaults.bool(forKey: enabledKey)
    }
}
