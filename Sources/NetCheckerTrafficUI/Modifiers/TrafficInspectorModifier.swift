import SwiftUI
import NetCheckerTrafficCore
import Combine

/// NetChecker SDK Version
public let NetCheckerVersion = "1.2.0"

#if canImport(UIKit)
import UIKit

// MARK: - Shake Gesture Detection via UIWindow Extension

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)

        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("NetCheckerDeviceDidShake")
}

// MARK: - Haptic Feedback

enum HapticFeedback {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

// MARK: - Shake Gesture View Modifier

struct ShakeGestureViewModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                action()
            }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(ShakeGestureViewModifier(action: action))
    }
}
#endif

// MARK: - NetChecker Configuration

/// Configuration options for NetChecker
public struct NetCheckerConfiguration {
    /// Whether to start the traffic interceptor automatically. Default is `true`.
    public var startInterceptor: Bool

    /// Whether mock engine is enabled by default. Default is `false`.
    public var enableMocking: Bool

    /// Whether breakpoints are enabled by default. Default is `false`.
    public var enableBreakpoints: Bool

    /// Environment groups to setup
    public var environmentGroups: [EnvironmentGroup]

    /// Whether to show haptic feedback on shake. Default is `true`.
    public var hapticFeedback: Bool

    /// Interception level. Default is `.full`.
    public var interceptionLevel: InterceptionLevel

    /// Default configuration
    public static let `default` = NetCheckerConfiguration()

    public init(
        startInterceptor: Bool = true,
        enableMocking: Bool = false,
        enableBreakpoints: Bool = false,
        environmentGroups: [EnvironmentGroup] = [],
        hapticFeedback: Bool = true,
        interceptionLevel: InterceptionLevel = .full
    ) {
        self.startInterceptor = startInterceptor
        self.enableMocking = enableMocking
        self.enableBreakpoints = enableBreakpoints
        self.environmentGroups = environmentGroups
        self.hapticFeedback = hapticFeedback
        self.interceptionLevel = interceptionLevel
    }
}

// MARK: - Traffic Inspector Modifier

struct TrafficInspectorModifier: ViewModifier {
    @State private var isPresented = false

    let triggerOnShake: Bool
    let presentationStyle: TrafficInspectorPresentationStyle
    let configuration: NetCheckerConfiguration

    init(
        triggerOnShake: Bool,
        presentationStyle: TrafficInspectorPresentationStyle,
        configuration: NetCheckerConfiguration
    ) {
        self.triggerOnShake = triggerOnShake
        self.presentationStyle = presentationStyle
        self.configuration = configuration

        // Apply configuration on init
        Self.applyConfiguration(configuration)
    }

    private static func applyConfiguration(_ config: NetCheckerConfiguration) {
        // Start interceptor if enabled
        if config.startInterceptor {
            Task { @MainActor in
                if !TrafficInterceptor.shared.isRunning {
                    TrafficInterceptor.shared.start(level: config.interceptionLevel)
                }
            }
        }

        // Configure mock engine - only enable if explicitly requested
        // Don't override user's persisted preference to disable
        if config.enableMocking {
            Task { @MainActor in
                MockEngine.shared.isEnabled = true
            }
        }

        // Configure breakpoint engine - only enable if explicitly requested
        // Don't override user's persisted preference to disable
        if config.enableBreakpoints {
            Task { @MainActor in
                BreakpointEngine.shared.isEnabled = true
            }
        }

        // Add environment groups
        Task { @MainActor in
            for group in config.environmentGroups {
                EnvironmentStore.shared.addGroup(group)
            }
        }
    }

    func body(content: Content) -> some View {
        content
            #if canImport(UIKit)
            .onShake {
                if triggerOnShake {
                    // Haptic feedback
                    if configuration.hapticFeedback {
                        HapticFeedback.impact(.medium)
                    }
                    isPresented = true
                }
            }
            #endif
            .modifier(PresentationModifier(
                isPresented: $isPresented,
                style: presentationStyle
            ))
    }
}

// MARK: - Presentation Style

/// Style for presenting the traffic inspector
public enum TrafficInspectorPresentationStyle {
    /// Present as a sheet (default)
    case sheet
    /// Present as a full screen cover
    case fullScreenCover
}

// MARK: - Presentation Modifier

struct PresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let style: TrafficInspectorPresentationStyle

    func body(content: Content) -> some View {
        switch style {
        case .sheet:
            content
                .sheet(isPresented: $isPresented) {
                    TrafficInspectorSheet()
                }
        case .fullScreenCover:
            #if os(iOS)
            content
                .fullScreenCover(isPresented: $isPresented) {
                    TrafficInspectorSheet()
                }
            #else
            content
                .sheet(isPresented: $isPresented) {
                    TrafficInspectorSheet()
                }
            #endif
        }
    }
}

// MARK: - Traffic Inspector Sheet

struct TrafficInspectorSheet: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                NetCheckerTrafficUI_TrafficListView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
            }
            .tag(0)
            .tabItem {
                Label("Traffic", systemImage: "network")
            }

            NavigationStack {
                NetCheckerTrafficUI_EnvironmentSwitcherView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
            }
            .tag(1)
            .tabItem {
                Label("Environments", systemImage: "server.rack")
            }

            NavigationStack {
                NetCheckerTrafficUI_MockRulesView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
            }
            .tag(2)
            .tabItem {
                Label("Mocks", systemImage: "theatermasks")
            }

            NavigationStack {
                NetCheckerTrafficUI_BreakpointRulesView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
            }
            .tag(3)
            .tabItem {
                Label("Breakpoints", systemImage: "hand.raised")
            }

            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
            }
            .tag(4)
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .tint(.blue)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject private var interceptor = TrafficInterceptor.shared
    @ObservedObject private var store = TrafficStore.shared
    @ObservedObject private var mockEngine = MockEngine.shared
    @ObservedObject private var breakpointEngine = BreakpointEngine.shared

    var body: some View {
        List {
            Section("Interceptor") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(interceptor.isRunning ? "Running" : "Stopped")
                        .foregroundColor(interceptor.isRunning ? .green : .secondary)
                }

                HStack {
                    Text("Requests Captured")
                    Spacer()
                    Text("\(interceptor.requestCount)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Errors")
                    Spacer()
                    Text("\(interceptor.errorCount)")
                        .foregroundColor(interceptor.errorCount > 0 ? .red : .secondary)
                }

                Button {
                    if interceptor.isRunning {
                        interceptor.stop()
                    } else {
                        interceptor.start()
                    }
                } label: {
                    Label(
                        interceptor.isRunning ? "Stop Interceptor" : "Start Interceptor",
                        systemImage: interceptor.isRunning ? "stop.fill" : "play.fill"
                    )
                }
            }

            Section("Mock Engine") {
                Toggle("Enable Mocking", isOn: $mockEngine.isEnabled)

                HStack {
                    Text("Active Rules")
                    Spacer()
                    Text("\(mockEngine.rules.filter { $0.isEnabled }.count)")
                        .foregroundColor(.secondary)
                }
            }

            Section("Breakpoints") {
                Toggle("Enable Breakpoints", isOn: $breakpointEngine.isEnabled)

                HStack {
                    Text("Active Rules")
                    Spacer()
                    Text("\(breakpointEngine.rules.filter { $0.isEnabled }.count)")
                        .foregroundColor(.secondary)
                }

                if !breakpointEngine.pausedRequests.isEmpty {
                    HStack {
                        Text("Paused Requests")
                        Spacer()
                        Text("\(breakpointEngine.pausedRequests.count)")
                            .foregroundColor(.orange)
                    }

                    Button("Resume All") {
                        breakpointEngine.resumeAll()
                    }
                }
            }

            Section("Actions") {
                Button(role: .destructive) {
                    store.clear()
                } label: {
                    Label("Clear All Records", systemImage: "trash")
                }

                Button(role: .destructive) {
                    mockEngine.clearRules()
                } label: {
                    Label("Clear All Mock Rules", systemImage: "trash")
                }

                Button(role: .destructive) {
                    breakpointEngine.clearRules()
                } label: {
                    Label("Clear All Breakpoints", systemImage: "trash")
                }
            }

            Section("Info") {
                HStack {
                    Text("SDK Version")
                    Spacer()
                    Text(NetCheckerVersion)
                        .foregroundColor(.secondary)
                }

                Link(destination: URL(string: "https://github.com/shakhzodsunnatov/NetChecker")!) {
                    HStack {
                        Text("GitHub Repository")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - View Extension

public extension View {
    /// Enables the NetChecker traffic inspector with shake-to-open functionality.
    ///
    /// When enabled, shaking the device will present the traffic inspector sheet.
    /// The interceptor starts automatically and settings are persisted.
    ///
    /// Example usage:
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             ContentView()
    ///                 .netChecker()
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// With custom configuration:
    /// ```swift
    /// ContentView()
    ///     .netChecker(configuration: .init(
    ///         startInterceptor: true,
    ///         enableMocking: false,
    ///         environmentGroups: [myEnvironmentGroup]
    ///     ))
    /// ```
    ///
    /// - Parameters:
    ///   - enabled: Whether the traffic inspector is enabled. Default is `true`.
    ///   - triggerOnShake: Whether to show the inspector when device is shaken. Default is `true`.
    ///   - presentationStyle: How to present the inspector. Default is `.sheet`.
    ///   - configuration: Configuration options. Default starts interceptor with mocking disabled.
    /// - Returns: A view with traffic inspector functionality.
    @ViewBuilder
    func netChecker(
        enabled: Bool = true,
        triggerOnShake: Bool = true,
        presentationStyle: TrafficInspectorPresentationStyle = .sheet,
        configuration: NetCheckerConfiguration = .default
    ) -> some View {
        if enabled {
            self.modifier(TrafficInspectorModifier(
                triggerOnShake: triggerOnShake,
                presentationStyle: presentationStyle,
                configuration: configuration
            ))
        } else {
            self
        }
    }

    /// Alias for `netChecker()` - enables traffic inspector with shake-to-open.
    ///
    /// Both `netChecker()` and `trafficInspector()` do the same thing.
    /// Use whichever name you prefer.
    ///
    /// Example usage:
    /// ```swift
    /// ContentView()
    ///     .trafficInspector()
    /// ```
    @ViewBuilder
    func trafficInspector(
        enabled: Bool = true,
        triggerOnShake: Bool = true,
        presentationStyle: TrafficInspectorPresentationStyle = .sheet,
        configuration: NetCheckerConfiguration = .default
    ) -> some View {
        netChecker(
            enabled: enabled,
            triggerOnShake: triggerOnShake,
            presentationStyle: presentationStyle,
            configuration: configuration
        )
    }
}

#Preview {
    TrafficInspectorSheet()
}
