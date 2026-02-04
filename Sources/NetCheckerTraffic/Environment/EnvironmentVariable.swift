import Foundation
import Combine

/// Property wrapper для переменных окружения
@propertyWrapper
public struct EnvironmentVariable: Sendable {
    private let key: String
    private let defaultValue: String

    public init(_ key: String, default defaultValue: String = "") {
        self.key = key
        self.defaultValue = defaultValue
    }

    public var wrappedValue: String {
        // Access through MainActor context
        MainActor.assumeIsolated {
            EnvironmentStore.shared.variable(key) ?? defaultValue
        }
    }
}

/// Property wrapper для опциональных переменных
@propertyWrapper
public struct OptionalEnvironmentVariable: Sendable {
    private let key: String

    public init(_ key: String) {
        self.key = key
    }

    public var wrappedValue: String? {
        MainActor.assumeIsolated {
            EnvironmentStore.shared.variable(key)
        }
    }
}

/// Property wrapper с проекцией на Publisher
@propertyWrapper
public final class ReactiveEnvironmentVariable: ObservableObject {
    private let key: String
    private let defaultValue: String
    private var cancellable: AnyCancellable?

    @Published public var wrappedValue: String

    public var projectedValue: AnyPublisher<String, Never> {
        $wrappedValue.eraseToAnyPublisher()
    }

    public init(_ key: String, default defaultValue: String = "") {
        self.key = key
        self.defaultValue = defaultValue
        self.wrappedValue = defaultValue

        // Observe store changes
        Task { @MainActor in
            self.wrappedValue = EnvironmentStore.shared.variable(key) ?? defaultValue

            self.cancellable = EnvironmentStore.shared.$groups
                .map { [key, defaultValue] _ in
                    EnvironmentStore.shared.variable(key) ?? defaultValue
                }
                .assign(to: \.wrappedValue, on: self)
        }
    }
}

// MARK: - Convenience Functions

/// Получить переменную окружения
public func env(_ key: String) -> String? {
    MainActor.assumeIsolated {
        EnvironmentStore.shared.variable(key)
    }
}

/// Получить переменную окружения с default
public func env(_ key: String, default defaultValue: String) -> String {
    MainActor.assumeIsolated {
        EnvironmentStore.shared.variable(key) ?? defaultValue
    }
}
