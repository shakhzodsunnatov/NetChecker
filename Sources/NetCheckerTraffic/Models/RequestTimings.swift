import Foundation

/// Тайминги сетевого запроса
public struct RequestTimings: Codable, Sendable, Hashable {
    /// DNS lookup time
    public var dnsLookup: TimeInterval

    /// TCP connection time
    public var tcpConnect: TimeInterval

    /// TLS handshake time (HTTPS only)
    public var tlsHandshake: TimeInterval?

    /// Time to send request
    public var requestSend: TimeInterval

    /// Time waiting for first byte (TTFB)
    public var serverWait: TimeInterval

    /// Time to receive response
    public var responseReceive: TimeInterval

    /// Total request duration
    public var total: TimeInterval

    /// Was connection reused (keep-alive)
    public var connectionReused: Bool

    /// Was proxy used
    public var proxyConnection: Bool

    /// Protocol name (h2, http/1.1, etc.)
    public var protocolName: String?

    /// Local address
    public var localAddress: String?

    /// Local port
    public var localPort: Int?

    /// Remote address
    public var remoteAddress: String?

    /// Remote port
    public var remotePort: Int?

    // MARK: - Initialization

    public init(
        dnsLookup: TimeInterval = 0,
        tcpConnect: TimeInterval = 0,
        tlsHandshake: TimeInterval? = nil,
        requestSend: TimeInterval = 0,
        serverWait: TimeInterval = 0,
        responseReceive: TimeInterval = 0,
        total: TimeInterval = 0,
        connectionReused: Bool = false,
        proxyConnection: Bool = false,
        protocolName: String? = nil,
        localAddress: String? = nil,
        localPort: Int? = nil,
        remoteAddress: String? = nil,
        remotePort: Int? = nil
    ) {
        self.dnsLookup = dnsLookup
        self.tcpConnect = tcpConnect
        self.tlsHandshake = tlsHandshake
        self.requestSend = requestSend
        self.serverWait = serverWait
        self.responseReceive = responseReceive
        self.total = total
        self.connectionReused = connectionReused
        self.proxyConnection = proxyConnection
        self.protocolName = protocolName
        self.localAddress = localAddress
        self.localPort = localPort
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
    }

    #if !os(watchOS)
    /// Создать из URLSessionTaskTransactionMetrics
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, *)
    public init(from metrics: URLSessionTaskTransactionMetrics) {
        // Calculate durations from date intervals
        let fetchStart = metrics.fetchStartDate ?? Date()

        // DNS lookup
        if let dnsStart = metrics.domainLookupStartDate,
           let dnsEnd = metrics.domainLookupEndDate {
            self.dnsLookup = dnsEnd.timeIntervalSince(dnsStart)
        } else {
            self.dnsLookup = 0
        }

        // TCP connect
        if let connectStart = metrics.connectStartDate,
           let connectEnd = metrics.connectEndDate {
            self.tcpConnect = connectEnd.timeIntervalSince(connectStart)
        } else {
            self.tcpConnect = 0
        }

        // TLS handshake
        if let secureStart = metrics.secureConnectionStartDate,
           let secureEnd = metrics.secureConnectionEndDate {
            self.tlsHandshake = secureEnd.timeIntervalSince(secureStart)
        } else {
            self.tlsHandshake = nil
        }

        // Request send
        if let requestStart = metrics.requestStartDate,
           let requestEnd = metrics.requestEndDate {
            self.requestSend = requestEnd.timeIntervalSince(requestStart)
        } else {
            self.requestSend = 0
        }

        // Server wait (TTFB)
        if let requestEnd = metrics.requestEndDate,
           let responseStart = metrics.responseStartDate {
            self.serverWait = responseStart.timeIntervalSince(requestEnd)
        } else {
            self.serverWait = 0
        }

        // Response receive
        if let responseStart = metrics.responseStartDate,
           let responseEnd = metrics.responseEndDate {
            self.responseReceive = responseEnd.timeIntervalSince(responseStart)
        } else {
            self.responseReceive = 0
        }

        // Total
        if let responseEnd = metrics.responseEndDate {
            self.total = responseEnd.timeIntervalSince(fetchStart)
        } else {
            self.total = dnsLookup + tcpConnect + (tlsHandshake ?? 0) + requestSend + serverWait + responseReceive
        }

        // Connection info
        self.connectionReused = metrics.isReusedConnection
        self.proxyConnection = metrics.isProxyConnection

        // Protocol
        if let version = metrics.negotiatedTLSProtocolVersion {
            self.protocolName = Self.tlsVersionString(version)
        } else {
            self.protocolName = nil
        }

        // Addresses
        if let endpoint = metrics.localAddress {
            self.localAddress = "\(endpoint)"
        } else {
            self.localAddress = nil
        }
        self.localPort = nil // Port is part of the endpoint string

        if let endpoint = metrics.remoteAddress {
            self.remoteAddress = "\(endpoint)"
        } else {
            self.remoteAddress = nil
        }
        self.remotePort = nil // Port is part of the endpoint string
    }

    private static func tlsVersionString(_ version: tls_protocol_version_t) -> String {
        switch version {
        case .TLSv10: return "TLS 1.0"
        case .TLSv11: return "TLS 1.1"
        case .TLSv12: return "TLS 1.2"
        case .TLSv13: return "TLS 1.3"
        case .DTLSv10: return "DTLS 1.0"
        case .DTLSv12: return "DTLS 1.2"
        default: return "Unknown"
        }
    }
    #endif

    // MARK: - Computed Properties

    /// Время до первого байта (DNS + TCP + TLS + Send + Wait)
    public var timeToFirstByte: TimeInterval {
        dnsLookup + tcpConnect + (tlsHandshake ?? 0) + requestSend + serverWait
    }

    /// Время соединения (DNS + TCP + TLS)
    public var connectionTime: TimeInterval {
        dnsLookup + tcpConnect + (tlsHandshake ?? 0)
    }

    /// Форматированное общее время
    public var formattedTotal: String {
        formatDuration(total)
    }

    /// Все фазы как массив для визуализации
    public var phases: [TimingPhase] {
        var result: [TimingPhase] = []

        if dnsLookup > 0 {
            result.append(TimingPhase(name: "DNS", duration: dnsLookup, colorName: "blue"))
        }

        if tcpConnect > 0 {
            result.append(TimingPhase(name: "TCP", duration: tcpConnect, colorName: "green"))
        }

        if let tls = tlsHandshake, tls > 0 {
            result.append(TimingPhase(name: "TLS", duration: tls, colorName: "purple"))
        }

        if requestSend > 0 {
            result.append(TimingPhase(name: "Send", duration: requestSend, colorName: "orange"))
        }

        if serverWait > 0 {
            result.append(TimingPhase(name: "Wait", duration: serverWait, colorName: "yellow"))
        }

        if responseReceive > 0 {
            result.append(TimingPhase(name: "Receive", duration: responseReceive, colorName: "cyan"))
        }

        return result
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 0.001 {
            return "<1 ms"
        } else if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.2f s", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = duration.truncatingRemainder(dividingBy: 60)
            return String(format: "%d min %.0f s", minutes, seconds)
        }
    }
}

// MARK: - Timing Phase

public struct TimingPhase: Codable, Sendable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let duration: TimeInterval
    public let colorName: String

    /// Форматированная длительность
    public var formattedDuration: String {
        if duration < 0.001 {
            return "<1 ms"
        } else if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        } else {
            return String(format: "%.2f s", duration)
        }
    }

    /// Длительность в миллисекундах
    public var durationMs: Double {
        duration * 1000
    }
}
