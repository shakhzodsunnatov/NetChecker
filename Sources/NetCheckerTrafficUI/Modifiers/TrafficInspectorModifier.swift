import SwiftUI
import NetCheckerTrafficCore
import Combine

#if canImport(UIKit)
import UIKit

// MARK: - Shake Detection

/// Custom UIWindow that detects shake gestures
final class ShakeDetectingWindow: UIWindow {
    static var onShake: (() -> Void)?

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            ShakeDetectingWindow.onShake?()
        }
        super.motionEnded(motion, with: event)
    }
}

/// Observable object to track shake events
@MainActor
final class ShakeDetector: ObservableObject {
    @Published var shakeDetected = false

    init() {
        ShakeDetectingWindow.onShake = { [weak self] in
            Task { @MainActor in
                self?.shakeDetected = true
            }
        }
    }

    func reset() {
        shakeDetected = false
    }
}
#endif

// MARK: - Traffic Inspector Modifier

struct TrafficInspectorModifier: ViewModifier {
    @State private var isPresented = false

    #if canImport(UIKit)
    @StateObject private var shakeDetector = ShakeDetector()
    #endif

    let triggerOnShake: Bool
    let presentationStyle: TrafficInspectorPresentationStyle

    func body(content: Content) -> some View {
        content
            #if canImport(UIKit)
            .onReceive(shakeDetector.$shakeDetected) { detected in
                if detected && triggerOnShake {
                    isPresented = true
                    shakeDetector.reset()
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
        NavigationStack {
            TabView(selection: $selectedTab) {
                NetCheckerTrafficUI_TrafficListView()
                    .tag(0)
                    .tabItem {
                        Label("Traffic", systemImage: "network")
                    }

                NetCheckerTrafficUI_EnvironmentSwitcherView()
                    .tag(1)
                    .tabItem {
                        Label("Environments", systemImage: "server.rack")
                    }

                NetCheckerTrafficUI_MockRulesView()
                    .tag(2)
                    .tabItem {
                        Label("Mocks", systemImage: "theatermasks")
                    }

                SettingsView()
                    .tag(3)
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject private var interceptor = TrafficInterceptor.shared
    @ObservedObject private var store = TrafficStore.shared

    var body: some View {
        List {
            Section("Status") {
                HStack {
                    Text("Interceptor")
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
            }

            Section("Actions") {
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

                Button(role: .destructive) {
                    store.clear()
                } label: {
                    Label("Clear All Records", systemImage: "trash")
                }
            }

            Section("Info") {
                HStack {
                    Text("SDK Version")
                    Spacer()
                    Text("1.0.0")
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
    /// This is perfect for debugging network traffic in development builds.
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
    /// - Parameters:
    ///   - enabled: Whether the traffic inspector is enabled. Default is `true`.
    ///   - triggerOnShake: Whether to show the inspector when device is shaken. Default is `true`.
    ///   - presentationStyle: How to present the inspector (`.sheet` or `.fullScreenCover`). Default is `.sheet`.
    /// - Returns: A view with traffic inspector functionality.
    @ViewBuilder
    func netChecker(
        enabled: Bool = true,
        triggerOnShake: Bool = true,
        presentationStyle: TrafficInspectorPresentationStyle = .sheet
    ) -> some View {
        if enabled {
            self.modifier(TrafficInspectorModifier(
                triggerOnShake: triggerOnShake,
                presentationStyle: presentationStyle
            ))
        } else {
            self
        }
    }

    /// Alias for `netChecker()` - enables traffic inspector with shake-to-open.
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
        presentationStyle: TrafficInspectorPresentationStyle = .sheet
    ) -> some View {
        netChecker(
            enabled: enabled,
            triggerOnShake: triggerOnShake,
            presentationStyle: presentationStyle
        )
    }
}

#Preview {
    TrafficInspectorSheet()
}
