import Foundation
import Network

/// MCP-сервер для приёма структурированных логов от AI-инструментов
@MainActor
public final class MCPServer: ObservableObject {
    // MARK: - Singleton

    /// Общий экземпляр
    public static let shared = MCPServer()

    // MARK: - Published Properties

    /// Запущен ли сервер
    @Published public private(set) var isRunning: Bool = false

    /// Порт сервера
    @Published public private(set) var port: UInt16 = 9876

    /// Количество обработанных запросов
    @Published public private(set) var requestCount: Int = 0

    /// Ошибка (если есть)
    @Published public private(set) var lastError: String?

    /// Активные подключения
    @Published public private(set) var activeConnections: Int = 0

    /// IP-адрес устройства в Wi-Fi сети
    @Published public private(set) var deviceIP: String = "localhost"

    // MARK: - Private Properties

    private var listener: NWListener?
    private let router = MCPRouter()
    private let listenerQueue = DispatchQueue(
        label: "com.netchecker.mcp.listener",
        qos: .utility
    )

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// URL для подключения с Mac (Wi-Fi IP устройства)
    public var connectionURL: String {
        "http://\(deviceIP):\(port)"
    }

    /// Запустить MCP-сервер на указанном порту
    public func start(port: UInt16 = 9876) {
        guard !isRunning else {
            print("[NetChecker MCP] Сервер уже запущен на порту \(self.port)")
            return
        }

        self.port = port
        self.deviceIP = Self.detectWiFiIP()

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }

            listener?.start(queue: listenerQueue)
        } catch {
            lastError = "Не удалось запустить: \(error.localizedDescription)"
            print("[NetChecker MCP] Ошибка запуска: \(error)")
        }
    }

    /// Остановить MCP-сервер
    public func stop() {
        guard isRunning else { return }

        listener?.cancel()
        listener = nil
        isRunning = false
        activeConnections = 0
        print("[NetChecker MCP] Сервер остановлен")
    }

    /// Сбросить счётчик запросов
    public func resetStats() {
        requestCount = 0
        lastError = nil
    }

    // MARK: - Connection Handling

    /// Обработка изменения состояния listener
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            lastError = nil
            printConnectionInfo()

        case .failed(let error):
            isRunning = false
            lastError = "Ошибка: \(error.localizedDescription)"
            print("[NetChecker MCP] Ошибка: \(error)")
            // Попытка перезапуска через 2 секунды
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !self.isRunning {
                    self.start(port: self.port)
                }
            }

        case .cancelled:
            isRunning = false

        default:
            break
        }
    }

    /// Обработка нового подключения
    private nonisolated func handleNewConnection(_ connection: NWConnection) {
        Task { @MainActor in
            self.activeConnections += 1
        }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveData(on: connection)
            case .failed, .cancelled:
                Task { @MainActor in
                    guard let self else { return }
                    self.activeConnections = max(0, self.activeConnections - 1)
                }
            default:
                break
            }
        }

        connection.start(queue: listenerQueue)
    }

    /// Чтение данных из подключения
    private nonisolated func receiveData(on connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 1024 * 1024 // 1 MB chunk
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error = error {
                Task { @MainActor in
                    self.lastError = "Ошибка чтения: \(error.localizedDescription)"
                }
                connection.cancel()
                return
            }

            if let data = data, !data.isEmpty {
                self.processReceivedData(data, on: connection)
            }

            if isComplete {
                connection.cancel()
            }
        }
    }

    /// Обработка полученных данных
    private nonisolated func processReceivedData(_ data: Data, on connection: NWConnection) {
        guard let request = MCPRequestParser.parse(data) else {
            let response = MCPHTTPResponse.error("Malformed HTTP request")
            self.sendResponse(response, on: connection)
            return
        }

        // Обработка запроса на MainActor (для доступа к TrafficStore)
        Task { @MainActor in
            let response = await self.router.handle(request)
            self.requestCount += 1
            self.sendResponse(response, on: connection)
        }
    }

    /// Отправка ответа клиенту
    private nonisolated func sendResponse(_ response: MCPHTTPResponse, on connection: NWConnection) {
        let data = response.serialize()

        connection.send(
            content: data,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }

    // MARK: - Console Output

    /// Вывести информацию о подключении в консоль Xcode
    private func printConnectionInfo() {
        print("")
        print("┌──────────────────────────────────────────────────")
        print("│ [NetChecker MCP] Сервер запущен!")
        print("│")
        print("│ \(connectionURL)")
        print("│")
        print("│ Claude Code / Cursor .mcp.json:")
        print("│ \"NETCHECKER_URL\": \"\(connectionURL)\"")
        print("└──────────────────────────────────────────────────")
        print("")
    }

    // MARK: - Wi-Fi IP

    /// Определить IP устройства в Wi-Fi сети (en0)
    static func detectWiFiIP() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return "localhost" }
        defer { freeifaddrs(ifaddr) }

        var fallback = "localhost"
        var current: UnsafeMutablePointer<ifaddrs>? = first

        while let addr = current {
            let flags = Int32(addr.pointee.ifa_flags)
            if (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
               addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr.pointee.ifa_addr,
                               socklen_t(addr.pointee.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    let name = String(cString: addr.pointee.ifa_name)
                    if name == "en0" { return ip }
                    if fallback == "localhost" { fallback = ip }
                }
            }
            current = addr.pointee.ifa_next
        }
        return fallback
    }
}
