import Foundation

/// Профиль условий сети для симуляции медленных и нестабильных соединений
public struct NetworkConditionProfile: Codable, Sendable, Hashable, Identifiable {
    /// Идентификатор
    public var id: UUID

    /// Отображаемое имя
    public var name: String

    /// Эмодзи для UI
    public var emoji: String

    /// Задержка перед отправкой запроса (секунды)
    public var latency: TimeInterval

    /// Ограничение скорости загрузки ответа, байт/сек. `nil` — без ограничения
    public var downloadBytesPerSecond: Int?

    /// Вероятность потери запроса, от 0 до 1
    public var packetLossRate: Double

    /// Встроенный профиль (нельзя удалить из UI)
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "📶",
        latency: TimeInterval = 0,
        downloadBytesPerSecond: Int? = nil,
        packetLossRate: Double = 0,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.latency = max(0, latency)
        self.downloadBytesPerSecond = downloadBytesPerSecond.map { max(1, $0) }
        self.packetLossRate = min(max(0, packetLossRate), 1)
        self.isBuiltIn = isBuiltIn
    }

    // MARK: - Computed

    /// Профиль полностью блокирует сеть
    public var isOffline: Bool {
        packetLossRate >= 1
    }

    /// Профиль не оказывает никакого влияния
    public var isTransparent: Bool {
        latency == 0 && downloadBytesPerSecond == nil && packetLossRate == 0
    }

    /// Человекочитаемое описание ограничений
    public var summary: String {
        if isOffline { return "Соединение недоступно" }
        if isTransparent { return "Без ограничений" }

        var parts: [String] = []
        if latency > 0 {
            parts.append("задержка \(Int(latency * 1000)) мс")
        }
        if let bps = downloadBytesPerSecond {
            parts.append("загрузка \(Self.formatBandwidth(bps))")
        }
        if packetLossRate > 0 {
            parts.append("потери \(Int(packetLossRate * 100))%")
        }
        return parts.joined(separator: ", ")
    }

    private static func formatBandwidth(_ bytesPerSecond: Int) -> String {
        let bitsPerSecond = Double(bytesPerSecond) * 8
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.1f Мбит/с", bitsPerSecond / 1_000_000)
        }
        return String(format: "%.0f Кбит/с", bitsPerSecond / 1_000)
    }
}

// MARK: - Встроенные профили

public extension NetworkConditionProfile {
    /// Без ограничений
    static let none = NetworkConditionProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A0")!,
        name: "Без ограничений",
        emoji: "🚀",
        isBuiltIn: true
    )

    /// Wi-Fi — быстрое стабильное соединение
    static let wifi = NetworkConditionProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
        name: "Wi-Fi",
        emoji: "📶",
        latency: 0.005,
        downloadBytesPerSecond: 4_000_000, // ~32 Мбит/с
        isBuiltIn: true
    )

    /// DSL
    static let dsl = NetworkConditionProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!,
        name: "DSL",
        emoji: "🔌",
        latency: 0.02,
        downloadBytesPerSecond: 250_000, // ~2 Мбит/с
        isBuiltIn: true
    )

    /// 4G / LTE
    static let lte = NetworkConditionProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!,
        name: "4G / LTE",
        emoji: "📱",
        latency: 0.05,
        downloadBytesPerSecond: 1_500_000, // ~12 Мбит/с
        isBuiltIn: true
    )

    /// 3G
    static let threeG = NetworkConditionProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A4")!,
        name: "3G",
        emoji: "🐢",
        latency: 0.2,
        downloadBytesPerSecond: 96_000, // ~780 Кбит/с
        packetLossRate: 0.01,
        isBuiltIn: true
    )

    /// EDGE
    static let edge = NetworkConditionProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!,
        name: "EDGE",
        emoji: "🐌",
        latency: 0.5,
        downloadBytesPerSecond: 30_000, // ~240 Кбит/с
        packetLossRate: 0.03,
        isBuiltIn: true
    )

    /// Нестабильная сеть — быстрая, но с частыми обрывами
    static let flaky = NetworkConditionProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A6")!,
        name: "Нестабильная сеть",
        emoji: "⚡️",
        latency: 0.1,
        downloadBytesPerSecond: 500_000,
        packetLossRate: 0.25,
        isBuiltIn: true
    )

    /// Соединение отсутствует
    static let offline = NetworkConditionProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A7")!,
        name: "Нет сети",
        emoji: "✈️",
        packetLossRate: 1,
        isBuiltIn: true
    )

    /// Все встроенные профили в порядке убывания скорости
    static let builtIn: [NetworkConditionProfile] = [
        .none, .wifi, .dsl, .lte, .threeG, .edge, .flaky, .offline
    ]
}
