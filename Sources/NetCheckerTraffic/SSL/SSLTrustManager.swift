import Foundation
import Security

/// Управление доверием SSL сертификатов
public final class SSLTrustManager: @unchecked Sendable {
    // MARK: - Singleton

    public static let shared = SSLTrustManager()

    // MARK: - Properties

    private var trustMode: SSLTrustMode = .strict
    private let lock = NSLock()

    // MARK: - Public Methods

    /// Установить режим доверия
    public func setTrustMode(_ mode: SSLTrustMode) {
        lock.lock()
        defer { lock.unlock() }
        trustMode = mode
    }

    /// Получить текущий режим
    public func currentMode() -> SSLTrustMode {
        lock.lock()
        defer { lock.unlock() }
        return trustMode
    }

    /// Оценить доверие к сертификату
    public func evaluate(trust: SecTrust, host: String) -> Bool {
        lock.lock()
        let mode = trustMode
        lock.unlock()

        switch mode {
        case .strict:
            return evaluateStrict(trust: trust)

        case .allowSelfSigned(let hosts):
            if hosts.contains(host.lowercased()) {
                return true
            }
            return evaluateStrict(trust: trust)

        case .allowExpired(let hosts):
            if hosts.contains(host.lowercased()) {
                return evaluateIgnoringExpiration(trust: trust)
            }
            return evaluateStrict(trust: trust)

        case .allowInvalidHost(let hosts):
            if hosts.contains(host.lowercased()) {
                return evaluateIgnoringHostname(trust: trust)
            }
            return evaluateStrict(trust: trust)

        case .allowAll(let understood):
            return understood

        case .allowProxy(let proxyHosts):
            if proxyHosts.contains(host.lowercased()) {
                return true
            }
            return evaluateStrict(trust: trust)

        case .custom(let handler):
            return handler(trust, host)
        }
    }

    // MARK: - Evaluation Methods

    private func evaluateStrict(trust: SecTrust) -> Bool {
        var error: CFError?
        let result = SecTrustEvaluateWithError(trust, &error)
        return result
    }

    private func evaluateIgnoringExpiration(trust: SecTrust) -> Bool {
        // Set policy to allow expired certificates
        let policy = SecPolicyCreateSSL(true, nil)
        SecTrustSetPolicies(trust, policy)

        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
    }

    private func evaluateIgnoringHostname(trust: SecTrust) -> Bool {
        // Create policy without hostname verification
        let policy = SecPolicyCreateSSL(true, nil)
        SecTrustSetPolicies(trust, policy)

        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
    }
}
