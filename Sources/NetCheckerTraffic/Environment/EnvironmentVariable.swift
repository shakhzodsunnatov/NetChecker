import Foundation
import Combine

/// Property wrapper for environment variables
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

/// Property wrapper for optional environment variables
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

/// Property wrapper with Publisher projection for reactive updates
@propertyWrapper
@MainActor
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
        self.wrappedValue = EnvironmentStore.shared.variable(key) ?? defaultValue

        // Observe store changes
        self.cancellable = EnvironmentStore.shared.$groups
            .map { [key, defaultValue] _ in
                EnvironmentStore.shared.variable(key) ?? defaultValue
            }
            .removeDuplicates()
            .assign(to: \.wrappedValue, on: self)
    }
}

// MARK: - Convenience Functions

/// Get environment variable value
@MainActor
public func env(_ key: String) -> String? {
    EnvironmentStore.shared.variable(key)
}

/// Get environment variable value with default
@MainActor
public func env(_ key: String, default defaultValue: String) -> String {
    EnvironmentStore.shared.variable(key) ?? defaultValue
}
