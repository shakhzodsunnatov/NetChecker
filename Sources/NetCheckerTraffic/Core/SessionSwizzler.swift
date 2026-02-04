import Foundation
import ObjectiveC

/// Swizzler для URLSessionConfiguration
public final class SessionSwizzler {
    // MARK: - Singleton

    public static let shared = SessionSwizzler()

    // MARK: - State

    private var isSwizzled = false
    private let swizzleLock = NSLock()

    // MARK: - Public Methods

    /// Активировать swizzling
    public func activate() {
        swizzleLock.lock()
        defer { swizzleLock.unlock() }

        guard !isSwizzled else { return }

        #if DEBUG
        swizzleProtocolClasses()
        isSwizzled = true
        #else
        print("[NetChecker] Warning: Swizzling is disabled in Release builds")
        #endif
    }

    /// Деактивировать swizzling
    public func deactivate() {
        swizzleLock.lock()
        defer { swizzleLock.unlock() }

        guard isSwizzled else { return }

        #if DEBUG
        unswizzleProtocolClasses()
        isSwizzled = false
        #endif
    }

    // MARK: - Private Methods

    private func swizzleProtocolClasses() {
        // Swizzle URLSessionConfiguration.default
        swizzleClassPropertyGetter(
            originalSelector: #selector(getter: URLSessionConfiguration.default),
            swizzledSelector: #selector(getter: URLSessionConfiguration.nc_swizzled_default)
        )

        // Swizzle URLSessionConfiguration.ephemeral
        swizzleClassPropertyGetter(
            originalSelector: #selector(getter: URLSessionConfiguration.ephemeral),
            swizzledSelector: #selector(getter: URLSessionConfiguration.nc_swizzled_ephemeral)
        )

        // Swizzle protocolClasses property
        swizzleInstanceProperty()
    }

    private func unswizzleProtocolClasses() {
        // Unswizzle by swizzling again (swaps back)
        swizzleClassPropertyGetter(
            originalSelector: #selector(getter: URLSessionConfiguration.default),
            swizzledSelector: #selector(getter: URLSessionConfiguration.nc_swizzled_default)
        )

        swizzleClassPropertyGetter(
            originalSelector: #selector(getter: URLSessionConfiguration.ephemeral),
            swizzledSelector: #selector(getter: URLSessionConfiguration.nc_swizzled_ephemeral)
        )

        swizzleInstanceProperty()
    }

    private func swizzleClassPropertyGetter(
        originalSelector: Selector,
        swizzledSelector: Selector
    ) {
        guard let metaClass = object_getClass(URLSessionConfiguration.self),
              let originalMethod = class_getClassMethod(URLSessionConfiguration.self, originalSelector),
              let swizzledMethod = class_getClassMethod(URLSessionConfiguration.self, swizzledSelector) else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    private func swizzleInstanceProperty() {
        let originalSelector = #selector(getter: URLSessionConfiguration.protocolClasses)
        let swizzledSelector = #selector(getter: URLSessionConfiguration.nc_swizzled_protocolClasses)

        guard let originalMethod = class_getInstanceMethod(URLSessionConfiguration.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(URLSessionConfiguration.self, swizzledSelector) else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

// MARK: - URLSessionConfiguration Extension

extension URLSessionConfiguration {
    @objc dynamic class var nc_swizzled_default: URLSessionConfiguration {
        // After swizzling, this actually calls the original 'default' getter
        let config = Self.nc_swizzled_default
        config.injectNetCheckerProtocol()
        return config
    }

    @objc dynamic class var nc_swizzled_ephemeral: URLSessionConfiguration {
        // After swizzling, this actually calls the original 'ephemeral' getter
        let config = Self.nc_swizzled_ephemeral
        config.injectNetCheckerProtocol()
        return config
    }

    @objc dynamic var nc_swizzled_protocolClasses: [AnyClass]? {
        // After swizzling, this actually calls the original getter
        let classes = self.nc_swizzled_protocolClasses
        return injectProtocol(into: classes)
    }

    private func injectNetCheckerProtocol() {
        var protocols = protocolClasses ?? []
        if !protocols.contains(where: { $0 == NetCheckerURLProtocol.self }) {
            protocols.insert(NetCheckerURLProtocol.self, at: 0)
            protocolClasses = protocols
        }
    }

    private func injectProtocol(into classes: [AnyClass]?) -> [AnyClass]? {
        var protocols = classes ?? []
        if !protocols.contains(where: { $0 == NetCheckerURLProtocol.self }) {
            protocols.insert(NetCheckerURLProtocol.self, at: 0)
        }
        return protocols
    }
}

// MARK: - Manual Injection

public extension URLSessionConfiguration {
    /// Ручное добавление NetChecker протокола в конфигурацию
    func addNetCheckerProtocol() {
        var protocols = protocolClasses ?? []
        if !protocols.contains(where: { $0 == NetCheckerURLProtocol.self }) {
            protocols.insert(NetCheckerURLProtocol.self, at: 0)
            protocolClasses = protocols
        }
    }

    /// Создать конфигурацию с NetChecker протоколом
    static func withNetChecker() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.addNetCheckerProtocol()
        return config
    }
}
