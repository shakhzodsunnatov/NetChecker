import Foundation
import Network

#if canImport(UIKit)
import UIKit
#endif

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

    /// IP-адрес устройства в локальной сети
    @Published public private(set) var localIPAddress: String = "localhost"

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

    /// Полный URL для подключения к серверу
    public var connectionURL: String {
        "http://\(localIPAddress):\(port)"
    }

    /// Запустить MCP-сервер на указанном порту
    public func start(port: UInt16 = 9876) {
        guard !isRunning else {
            print("[NetChecker MCP] Сервер уже запущен на порту \(self.port)")
            return
        }

        self.port = port
        self.localIPAddress = Self.detectLocalIPAddress()

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
            let response = self.router.handle(request)
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

    // MARK: - IP Detection

    /// Вывести информацию о подключении в консоль Xcode
    private func printConnectionInfo() {
        let url = connectionURL
        print("")
        print("┌──────────────────────────────────────────────────")
        print("│ [NetChecker MCP] Сервер запущен!")
        print("│")
        print("│ URL:    \(url)")
        print("│ Status: \(url)/status")
        print("│")
        print("│ Тест:")
        print("│ curl -X POST \(url)/log \\")
        print("│   -H \"Content-Type: application/json\" \\")
        print("│   -d '{\"operationType\":\"apiCall\",\"source\":{\"toolName\":\"test\",\"sessionId\":\"s1\"},\"payload\":{\"type\":\"networkCall\",\"url\":\"https://api.example.com\",\"method\":\"GET\",\"statusCode\":200},\"severity\":\"info\"}'")
        print("└──────────────────────────────────────────────────")
        print("")
    }

    /// Определить IP-адрес устройства в локальной сети
    static func detectLocalIPAddress() -> String {
        var address = "localhost"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return address
        }

        defer { freeifaddrs(ifaddr) }

        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = current {
            let flags = Int32(addr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback {
                let family = addr.pointee.ifa_addr.pointee.sa_family
                if family == UInt8(AF_INET) { // IPv4
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let result = getnameinfo(
                        addr.pointee.ifa_addr,
                        socklen_t(addr.pointee.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil, 0,
                        NI_NUMERICHOST
                    )
                    if result == 0 {
                        let ip = String(cString: hostname)
                        // Предпочитаем en0 (WiFi на iOS, основной на Mac)
                        let ifName = String(cString: addr.pointee.ifa_name)
                        if ifName == "en0" {
                            return ip
                        }
                        // Запомнить первый найденный, если en0 не найдётся
                        if address == "localhost" {
                            address = ip
                        }
                    }
                }
            }
            current = addr.pointee.ifa_next
        }

        return address
    }
}
