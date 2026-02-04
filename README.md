<p align="center">
  <img src="https://raw.githubusercontent.com/shakhzodsunnatov/NetChecker/main/Assets/logo.png" alt="NetChecker Logo" width="200" height="200">
</p>

<h1 align="center">NetChecker</h1>

<p align="center">
  <strong>The Ultimate Network Traffic Inspector for iOS & macOS</strong><br>
  Debug, mock, and intercept HTTP/HTTPS requests like a pro — Charles Proxy, built right into your app.
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+"></a>
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-16.0+-007AFF?style=flat-square&logo=apple&logoColor=white" alt="iOS 16.0+"></a>
  <a href="https://developer.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-13.0+-007AFF?style=flat-square&logo=apple&logoColor=white" alt="macOS 13.0+"></a>
  <a href="https://swift.org/package-manager/"><img src="https://img.shields.io/badge/SPM-Compatible-brightgreen?style=flat-square&logo=swift&logoColor=white" alt="SPM Compatible"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow?style=flat-square" alt="MIT License"></a>
</p>

<p align="center">
  <a href="#-features">Features</a> •
  <a href="#-installation">Installation</a> •
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-documentation">Documentation</a> •
  <a href="#-contributing">Contributing</a>
</p>

---

## Why NetChecker?

Stop switching between your app and external proxy tools. **NetChecker** brings professional-grade network debugging directly into your development workflow — with zero configuration and a beautiful native UI.

```swift
// That's it. One line to start.
TrafficInterceptor.shared.start()
```

<p align="center">
  <img src="https://raw.githubusercontent.com/shakhzodsunnatov/NetChecker/main/Assets/demo.gif" alt="NetChecker Demo" width="300">
</p>

---

## ✨ Features

<table>
<tr>
<td width="50%">

### 🔍 Real-Time Traffic Monitoring
Capture every HTTP/HTTPS request your app makes. See requests as they happen with live updates.

### 📊 Detailed Request Analysis
- Headers, body, query parameters
- Cookies inspection
- JSON syntax highlighting
- Binary data preview

### ⏱️ Performance Timing
Visual waterfall charts showing:
- DNS lookup
- TCP connection
- TLS handshake
- Time to first byte
- Content download

</td>
<td width="50%">

### 🎭 Powerful Mocking Engine
Create mock responses without touching your backend:
- URL pattern matching (regex support)
- Custom status codes & headers
- Simulated delays & errors
- Priority-based rule matching

### ⏸️ Request Breakpoints
Pause, inspect, and modify requests in real-time:
- Edit headers on-the-fly
- Modify request body
- Change URL endpoints
- Auto-resume with timeout

### 🌍 Environment Switching
Switch between environments instantly:
- Dev / Staging / Production
- Quick URL overrides
- Per-host configuration
- Environment variables

</td>
</tr>
</table>

### More Powerful Features

| Feature | Description |
|---------|-------------|
| 🔄 **Edit & Retry** | Modify any captured request and resend it instantly |
| 📋 **Export to cURL** | Copy any request as a cURL command |
| 📦 **HAR Export** | Export traffic sessions in standard HAR format |
| 🔐 **SSL Inspection** | View TLS version, cipher suites, and certificate chains |
| 🎨 **Native SwiftUI** | Beautiful, responsive UI that feels right at home |
| 💾 **Persistent Rules** | Mock rules and breakpoints survive app restarts |
| 🚀 **Zero Dependencies** | Pure Swift — no third-party libraries required |

---

## 📦 Installation

### Swift Package Manager

Add NetChecker to your project using Xcode:

1. Go to **File → Add Package Dependencies**
2. Enter the repository URL:
   ```
   https://github.com/shakhzodsunnatov/NetChecker.git
   ```
3. Select **Up to Next Major Version** with `1.0.0`

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/shakhzodsunnatov/NetChecker.git", from: "1.0.0")
]
```

Then add the product to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "NetCheckerTraffic", package: "NetChecker")
    ]
)
```

---

## 🚀 Quick Start

### 1. Start Intercepting (2 lines of code)

```swift
import NetCheckerTraffic

// In your App's init or AppDelegate
TrafficInterceptor.shared.start()
```

### 2. Add the Traffic Inspector UI

```swift
import SwiftUI
import NetCheckerTraffic

struct ContentView: View {
    var body: some View {
        TabView {
            YourMainView()
                .tabItem { Label("Home", systemImage: "house") }

            TrafficListView()  // ← Add this tab
                .tabItem { Label("Network", systemImage: "network") }
        }
    }
}
```

### 3. That's It! 🎉

All network requests now appear in the Traffic tab with full details.

---

## 📖 Documentation

### Interception Levels

Choose the level of detail you need:

```swift
// Full interception — headers + body + timing
TrafficInterceptor.shared.start(level: .full)

// Basic — works with all URLSession configurations
TrafficInterceptor.shared.start(level: .basic)

// Manual — for custom URLSession setups
TrafficInterceptor.shared.start(level: .manual)
```

### Configuration Options

Fine-tune the interceptor to your needs:

```swift
var config = InterceptorConfiguration()

// Capture only specific hosts
config.captureHosts = ["api.myapp.com", "cdn.myapp.com"]

// Ignore noisy hosts
config.ignoreHosts = ["analytics.com", "crashlytics.com"]

// Limit memory usage
config.maxRecords = 500

// Redact sensitive headers in logs
config.redactedHeaders = ["Authorization", "X-API-Key"]

TrafficInterceptor.shared.start(configuration: config)
```

---

### 🎭 Mocking API Responses

Create mock responses without a backend:

```swift
let mockEngine = MockEngine.shared

// Mock a JSON response
mockEngine.mockJSON(
    url: "*/api/users/*",
    json: """
    {
        "id": 1,
        "name": "John Doe",
        "email": "john@example.com"
    }
    """,
    statusCode: 200
)

// Simulate network errors
mockEngine.mockError(
    url: "*/api/payments/*",
    error: .networkError(.notConnectedToInternet)
)

// Add artificial latency
mockEngine.mockDelay(
    url: "*/api/slow-endpoint",
    seconds: 3.0
)
```

### Mock Rule Priority

Rules are matched in priority order:

```swift
let rule = MockRule(
    matching: MockMatching(urlPattern: "*/api/*", method: .post),
    action: .respond(.json("{}", statusCode: 201)),
    priority: 100  // Higher = matched first
)
mockEngine.addRule(rule)
```

---

### ⏸️ Request Breakpoints

Pause and modify requests before they're sent:

```swift
let breakpointEngine = BreakpointEngine.shared

// Break on all requests to a host
breakpointEngine.breakpoint(host: "api.myapp.com")

// Break on specific URL patterns
breakpointEngine.breakpoint(url: "*/auth/login", direction: .request)

// Break on responses too
breakpointEngine.breakpoint(url: "*/api/*", direction: .both)
```

When a breakpoint triggers, the request appears in `pausedRequests`:

```swift
// In your UI
ForEach(breakpointEngine.pausedRequests) { paused in
    Text(paused.url?.absoluteString ?? "")
    Button("Resume") {
        breakpointEngine.resume(id: paused.id, with: nil)
    }
    Button("Cancel") {
        breakpointEngine.cancel(id: paused.id)
    }
}
```

---

### 🌍 Environment Management

Switch between environments without rebuilding:

```swift
// Define your environments
TrafficInterceptor.shared.addEnvironment(
    group: "API",
    source: "api.myapp.com",
    environments: [
        Environment(name: "Production", host: "api.myapp.com"),
        Environment(name: "Staging", host: "staging-api.myapp.com"),
        Environment(name: "Development", host: "dev-api.myapp.com", variables: [
            "DEBUG": "true",
            "LOG_LEVEL": "verbose"
        ])
    ]
)

// Switch environments at runtime
TrafficInterceptor.shared.switchEnvironment(group: "API", to: "Staging")

// Quick temporary override
TrafficInterceptor.shared.override(
    host: "api.myapp.com",
    with: "localhost:8080",
    autoDisableAfter: 300  // 5 minutes
)

// Access environment variables
if let debugMode = TrafficInterceptor.shared.variable("DEBUG") {
    print("Debug mode: \(debugMode)")
}
```

---

### 📊 Programmatic Access

Access traffic data in your code:

```swift
import Combine

// Get all records
let records = TrafficStore.shared.records

// Filter records
let filter = TrafficFilter()
filter.methods = [.get, .post]
filter.statusCategories = [.success, .clientError]
let filtered = filter.apply(to: records)

// React to new traffic
TrafficStore.shared.$records
    .sink { records in
        print("Total requests: \(records.count)")
    }
    .store(in: &cancellables)

// Get statistics
let stats = TrafficStatistics.calculate(from: records)
print("Average response time: \(stats.averageResponseTime)ms")
```

---

### 📋 Export Options

#### cURL Command

```swift
let record = TrafficStore.shared.records.first!
let curl = CURLFormatter.format(record: record)
// curl -X GET 'https://api.example.com/users' -H 'Authorization: Bearer ...'
```

#### HAR Format

```swift
let records = TrafficStore.shared.records
if let harData = HARFormatter.format(records: records) {
    // Save or share HAR file
    // Compatible with Chrome DevTools, Charles, etc.
}
```

---

## 🎨 UI Components

### Available Views

| View | Description |
|------|-------------|
| `TrafficListView` | Main list of all captured requests |
| `TrafficDetailView` | Full request/response details with tabs |
| `RequestEditorView` | Edit and retry requests |
| `TrafficStatisticsView` | Visual statistics dashboard |
| `WaterfallChartView` | Performance timing visualization |
| `SSLDashboardView` | SSL/TLS security overview |
| `EnvironmentSwitcherView` | Environment management UI |
| `MockRulesView` | Manage mock rules |
| `BreakpointRulesView` | Manage breakpoints |

### Floating Traffic Badge

Add a floating indicator anywhere in your app:

```swift
ZStack {
    YourContentView()

    FloatingTrafficBadge()
        .padding()
}
```

---

## 🛡️ Best Practices

### Debug Builds Only

```swift
#if DEBUG
import NetCheckerTraffic
#endif

@main
struct MyApp: App {
    init() {
        #if DEBUG
        TrafficInterceptor.shared.start()
        #endif
    }
}
```

### Performance Tips

```swift
var config = InterceptorConfiguration()

// Use basic level for better performance
config.level = .basic

// Limit stored records
config.maxRecords = 200

// Exclude high-frequency hosts
config.ignoreHosts = [
    "analytics.google.com",
    "api.segment.io",
    "logs.myapp.com"
]

TrafficInterceptor.shared.start(configuration: config)
```

### SSL Debugging

```swift
#if DEBUG
// Allow self-signed certificates (local development)
TrafficInterceptor.shared.allowSelfSignedCertificates(
    for: ["localhost", "192.168.1.100"]
)

// Enable proxy mode (Charles/Proxyman)
TrafficInterceptor.shared.enableProxyMode(
    for: ["api.myapp.com"]
)
#endif
```

---

## 📋 Requirements

| Requirement | Version |
|-------------|---------|
| Swift | 5.9+ |
| iOS | 16.0+ |
| macOS | 13.0+ |
| Xcode | 15.0+ |

---

## 🗺️ Roadmap

- [ ] WebSocket traffic inspection
- [ ] gRPC support
- [ ] Traffic replay from HAR files
- [ ] Shared team mock configurations
- [ ] Charles/Proxyman session import
- [ ] Network condition simulation (3G, Edge, etc.)

---

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) before submitting a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

NetChecker is available under the MIT license. See the [LICENSE](LICENSE) file for more info.

---

## 💬 Support

- 📫 **Issues**: [GitHub Issues](https://github.com/shakhzodsunnatov/NetChecker/issues)
- 💡 **Discussions**: [GitHub Discussions](https://github.com/shakhzodsunnatov/NetChecker/discussions)
- ⭐ **Star** this repo if you find it useful!

---

<p align="center">
  <strong>Built with ❤️ by <a href="https://github.com/shakhzodsunnatov">Shakhzod Sunnatov</a></strong>
</p>

<p align="center">
  <sub>If NetChecker helps you debug faster, consider giving it a ⭐</sub>
</p>
