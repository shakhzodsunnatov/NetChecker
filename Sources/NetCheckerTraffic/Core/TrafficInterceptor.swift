import Foundation
import Combine

/// Главный класс для управления перехватом трафика
@MainActor
public final class TrafficInterceptor: ObservableObject {
    // MARK: - Singleton

    /// Общий экземпляр
    public static let shared = TrafficInterceptor()

    // MARK: - Published Properties

    /// Запущен ли перехват
    @Published public private(set) var isRunning: Bool = false

    /// Количество перехваченных запросов
    @Published public private(set) var requestCount: Int = 0

    /// Количество ошибок
    @Published public private(set) var errorCount: Int = 0

    // MARK: - Configuration

    /// Текущая конфигурация
    public private(set) var configuration: InterceptorConfiguration = .default

    // MARK: - Engines

    /// Mock engine
    public let mockEngine = MockEngine.shared

    /// Breakpoint engine
    public let breakpointEngine = BreakpointEngine.shared

    /// Environment store
    public let environmentStore = EnvironmentStore.shared

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        setupObservers()
    }

    // MARK: - Public Methods

    /// Запустить перехват с конфигурацией по умолчанию
    public func start() {
        start(configuration: .default)
    }

    /// Запустить перехват с указанным уровнем
    public func start(level: InterceptionLevel) {
        var config = InterceptorConfiguration.default
        config.level = level
        start(configuration: config)
    }

    /// Запустить перехват с указанной конфигурацией
    public func start(configuration: InterceptorConfiguration) {
        guard !isRunning else {
            print("[NetChecker] Traffic interception is already running")
            return
        }

        self.configuration = configuration

        // Update thread-safe state for URLProtocol access
        NetCheckerURLProtocol.updateConfiguration(configuration)
        NetCheckerURLProtocol.setIntercepting(true)

        // Configure store
        TrafficStore.shared.maxRecords = configuration.maxRecords

        // Register protocol based on level
        switch configuration.level {
        case .basic:
            URLProtocol.registerClass(NetCheckerURLProtocol.self)

        case .full:
            URLProtocol.registerClass(NetCheckerURLProtocol.self)
            SessionSwizzler.shared.activate()

        case .manual:
            // User must manually add protocol to their sessions
            break
        }

        isRunning = true
        print("[NetChecker] Traffic interception started (level: \(configuration.level.rawValue))")
    }

    /// Остановить перехват
    public func stop() {
        guard isRunning else { return }

        // Update thread-safe state
        NetCheckerURLProtocol.setIntercepting(false)

        // Unregister protocol
        URLProtocol.unregisterClass(NetCheckerURLProtocol.self)

        // Deactivate swizzling if was used
        if configuration.level == .full {
            SessionSwizzler.shared.deactivate()
        }

        isRunning = false
        print("[NetChecker] Traffic interception stopped")
    }

    /// Очистить все записи
    public func clearRecords() {
        TrafficStore.shared.clear()
        requestCount = 0
        errorCount = 0
    }

    /// Получить классы протоколов для ручной настройки
    public static func protocolClasses() -> [AnyClass] {
        [NetCheckerURLProtocol.self]
    }

    // MARK: - Environment Management

    /// Добавить группу окружений
    public func addEnvironment(
        group: String,
        source: String,
        environments: [Environment]
    ) {
        environmentStore.addGroup(
            EnvironmentGroup(
                name: group,
                sourcePattern: source,
                environments: environments
            )
        )
    }

    /// Переключить окружение
    public func switchEnvironment(group: String, to environmentName: String) {
        environmentStore.switchEnvironment(group: group, to: environmentName)
    }

    /// Quick override для хоста
    public func override(
        host: String,
        with newHost: String,
        autoDisableAfter: TimeInterval? = nil
    ) {
        environmentStore.addQuickOverride(
            from: host,
            to: newHost,
            autoDisableAfter: autoDisableAfter
        )
    }

    /// Удалить override для хоста
    public func removeOverride(for host: String) {
        environmentStore.removeQuickOverride(for: host)
    }

    /// Получить переменную окружения
    public func variable(_ key: String) -> String? {
        environmentStore.variable(key)
    }

    // MARK: - Private Methods

    private func setupObservers() {
        TrafficStore.shared.$count
            .receive(on: DispatchQueue.main)
            .assign(to: &$requestCount)

        TrafficStore.shared.$errorCount
            .receive(on: DispatchQueue.main)
            .assign(to: &$errorCount)
    }
}

// MARK: - Convenience Extensions

public extension TrafficInterceptor {
    /// Запустить с фильтром по хостам
    func start(hosts: Set<String>) {
        var config = InterceptorConfiguration.default
        config.captureHosts = hosts
        start(configuration: config)
    }

    /// Запустить с игнорированием хостов
    func start(ignoring hosts: Set<String>) {
        var config = InterceptorConfiguration.default
        config.ignoreHosts = hosts
        start(configuration: config)
    }

    /// Включить SSL bypass для хостов
    func allowSelfSignedCertificates(for hosts: Set<String>) {
        var config = configuration
        config.ssl.trustMode = .allowSelfSigned(hosts: hosts)
        self.configuration = config
    }

    /// Включить режим прокси (Charles/Proxyman)
    func enableProxyMode(for hosts: Set<String>) {
        var config = configuration
        config.ssl.trustMode = .allowProxy(proxyHosts: hosts)
        self.configuration = config
    }
}
