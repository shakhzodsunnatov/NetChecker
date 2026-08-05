import Foundation

/// Раздел инспектора, который можно скрыть
public enum InspectorFeature: String, CaseIterable, Codable, Sendable, Identifiable {
    case traffic
    case flows
    case environments
    case mocks
    case breakpoints

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .traffic: return "Traffic"
        case .flows: return "Flows"
        case .environments: return "Environments"
        case .mocks: return "Mocks"
        case .breakpoints: return "Breakpoints"
        }
    }

    public var systemImage: String {
        switch self {
        case .traffic: return "network"
        case .flows: return "point.3.connected.trianglepath.dotted"
        case .environments: return "server.rack"
        case .mocks: return "theatermasks"
        case .breakpoints: return "hand.raised"
        }
    }

    public var summary: String {
        switch self {
        case .traffic: return "Перехваченные запросы, импорт и экспорт HAR"
        case .flows: return "Сценарии из связанных запросов"
        case .environments: return "Переключение окружений и токенов"
        case .mocks: return "Подмена ответов правилами"
        case .breakpoints: return "Остановка запросов и ответов"
        }
    }

    /// Раздел нельзя скрыть — без него инспектор теряет смысл
    public var isRequired: Bool {
        self == .traffic
    }
}

/// Какие разделы показывать во вкладках инспектора.
///
/// Инспектор со временем оброс возможностями, а нужны обычно две-три.
/// Скрытые разделы не занимают место в панели вкладок; настройки остаются
/// доступны всегда.
@MainActor
public final class InspectorFeatureSettings: ObservableObject {
    public static let shared = InspectorFeatureSettings()

    /// Разделы, скрытые до первой настройки пользователем.
    ///
    /// Environments скрыт по умолчанию: он нужен не в каждой сессии отладки,
    /// а место в панели вкладок ограничено. Включается в «Разделах инспектора».
    public static let defaultHidden: Set<InspectorFeature> = [.environments]

    /// Скрытые разделы
    @Published public private(set) var hidden: Set<InspectorFeature> = defaultHidden {
        didSet { persist() }
    }

    private let storageKey = "NetCheckerHiddenFeatures"

    private init() {
        load()
    }

    /// Разделы для показа, в постоянном порядке
    public var visible: [InspectorFeature] {
        InspectorFeature.allCases.filter { !hidden.contains($0) }
    }

    public func isVisible(_ feature: InspectorFeature) -> Bool {
        !hidden.contains(feature)
    }

    /// Показать или скрыть раздел. Обязательные разделы скрыть нельзя.
    public func setVisible(_ isVisible: Bool, for feature: InspectorFeature) {
        guard !feature.isRequired else { return }

        if isVisible {
            hidden.remove(feature)
        } else {
            hidden.insert(feature)
        }
    }

    /// Вернуть все разделы
    public func showAll() {
        hidden.removeAll()
    }

    // MARK: - Персистентность

    private func persist() {
        guard let data = try? JSONEncoder().encode(Array(hidden)) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        // Отсутствие записи означает «пользователь ещё не настраивал» —
        // тогда действует набор по умолчанию, а не «показать всё»
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([InspectorFeature].self, from: data) else {
            return
        }
        hidden = Set(stored.filter { !$0.isRequired })
    }
}
