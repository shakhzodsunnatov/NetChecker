<p align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/e18f105c-fc88-4628-9844-2423e4c449d0" width="400">
  <source media="(prefers-color-scheme: light)" srcset="https://github.com/user-attachments/assets/734078db-33b8-41a4-a917-4aec963a0b70" width="400">
  <img alt="NetChecker Logo" src="https://github.com/user-attachments/assets/734078db-33b8-41a4-a917-4aec963a0b70" width="400">
</picture>
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

---

## 📸 Screenshots

<p align="center">
<img width="180" alt="Shake Inspector" src="https://github.com/user-attachments/assets/003cdd12-9abc-41f3-b19e-88ee0497c45a" />
<img width="180" alt="Menu Options" src="https://github.com/user-attachments/assets/223f364d-518f-4275-b01b-acf45c9c6f82" />
<img width="180" alt="Edit & Retry" src="https://github.com/user-attachments/assets/6cf31d28-f0f0-4adc-9e21-3bf49e03cb11" />
<img width="180" alt="Traffic List" src="https://github.com/user-attachments/assets/fb76cf9d-4b36-45bf-a7a7-fbc88e731026" />
</p>

<p align="center">
  <em>Shake Inspector • Menu Options • Edit & Retry • Traffic List • Request Details</em>
</p>

### 🎭 Mock Rules

<p align="center">
<img width="180" alt="Mock Rules List" src="https://github.com/user-attachments/assets/f5022f7a-b304-45ef-ba3f-fbc51a52b8d7" />
<img width="180" alt="Edit Mock Rule" src="https://github.com/user-attachments/assets/a2b32b58-54be-4931-8288-facfdc4f75d6" />
<img width="180" alt="Create Mock Rule" src="https://github.com/user-attachments/assets/3b249884-3f3d-4ab3-b709-5d276a17abc8" />
</p>

<p align="center">
  <em>Mock Rules List • Edit Mock Rule • Create Mock Rule</em>
</p>

### ⏸️ Breakpoints

<p align="center">
<img width="180" alt="IMG_1889" src="https://github.com/user-attachments/assets/c8aa0613-322c-45e0-8a48-55be34dd9800" />
<img width="180" alt="IMG_1892" src="https://github.com/user-attachments/assets/9121c223-9266-49c5-af35-3f093fe686f2" />
<img width="180" alt="IMG_1893" src="https://github.com/user-attachments/assets/0bbabaec-2c26-4bd5-8815-226c264eb618" />
<img width="180" alt="Screenshot" src="https://github.com/user-attachments/assets/e7ea3d7f-39d1-460a-876d-1f820a2238ad" />
</p>

<p align="center">
  <em>Breakpoints List • Paused Request • Edit & Resume • Request Modification</em>
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

### 🌍 Environment Switching <sup><kbd>Coming Soon</kbd></sup>
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
| 🤖 **MCP Server** | AI tools can control your app, test APIs, and inspect traffic remotely |
| 🎯 **Custom Triggers** | Register any app action as an AI-invokable trigger |
| 📡 **Execute Through Device** | AI sends HTTP requests using the device's real auth session |

---

## 📦 Installation

### Swift Package Manager

Add NetChecker to your project using Xcode:

1. Go to **File → Add Package Dependencies**
2. Enter the repository URL:
   ```
   https://github.com/shakhzodsunnatov/NetChecker.git
   ```
3. Select **Up to Next Major Version** with `1.2.0`

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/shakhzodsunnatov/NetChecker.git", from: "1.2.0")
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

### Option 1: Shake-to-Open (Recommended)

The easiest way to integrate NetChecker — just add the `.netChecker()` modifier:

```swift
import SwiftUI
import NetCheckerTraffic

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .netChecker()  // ← Shake device to open inspector!
        }
    }
}
```

**That's it!** Shake your device to open the traffic inspector. No UI changes needed.

### Option 2: Tab-Based Integration

For permanent access, add a Traffic tab:

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
        .onAppear {
            TrafficInterceptor.shared.start()
        }
    }
}
```

### Option 3: Manual Start Only

If you just want interception without UI:

```swift
import NetCheckerTraffic

// In your App's init or AppDelegate
TrafficInterceptor.shared.start()
```

---

## 📱 The `.netChecker()` Modifier

The simplest way to add network debugging to your app:

```swift
ContentView()
    .netChecker()
```

### Features

- **Shake to Open**: Shake your device to instantly open the traffic inspector
- **Full Inspector UI**: Traffic list, environment switching, mock rules, and settings
- **Zero UI Changes**: Works with any app structure — tabs, navigation, or custom layouts
- **Presentation Styles**: Choose between sheet or full-screen cover

### Configuration Options

```swift
// Default: shake-to-open with sheet presentation
.netChecker()

// Disable shake gesture (use programmatic trigger)
.netChecker(triggerOnShake: false)

// Full screen presentation
.netChecker(presentationStyle: .fullScreenCover)

// Disable in production
.netChecker(enabled: false)

// Alternative name
.trafficInspector()
```

### Conditional Enablement

```swift
ContentView()
    #if DEBUG
    .netChecker()
    #endif
```

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

### 🌍 Environment Management <sup><kbd>Coming Soon</kbd></sup>

> **Note:** Environment switching UI is under development. The API is ready and functional, but the UI tab is temporarily disabled.

Switch between environments without rebuilding:

```swift
// Create environment group
let apiGroup = EnvironmentGroup(
    name: "API Server",
    sourcePattern: "api.myapp.com",
    environments: [
        Environment(
            name: "Production",
            emoji: "🟢",
            baseURL: URL(string: "https://api.myapp.com")!,
            isDefault: true,
            variables: ["DEBUG": "false"]
        ),
        Environment(
            name: "Staging",
            emoji: "🟡",
            baseURL: URL(string: "https://staging-api.myapp.com")!,
            variables: ["DEBUG": "true", "API_VERSION": "v2-beta"]
        ),
        Environment(
            name: "Development",
            emoji: "🔧",
            baseURL: URL(string: "https://dev-api.myapp.com")!,
            variables: ["DEBUG": "true", "LOG_LEVEL": "verbose"]
        ),
        Environment(
            name: "Local",
            emoji: "💻",
            baseURL: URL(string: "http://localhost:3000")!,
            variables: ["LOCAL": "true"]
        )
    ]
)

// Add to store
EnvironmentStore.shared.addGroup(apiGroup)

// Switch environments at runtime
EnvironmentStore.shared.switchEnvironment(group: "API Server", to: "Staging")

// Quick temporary override (auto-expires after 5 minutes)
EnvironmentStore.shared.addQuickOverride(
    from: "api.myapp.com",
    to: "localhost:8080",
    autoDisableAfter: 300  // 5 minutes
)

// Access environment variables
if let debugMode = TrafficInterceptor.shared.variable("DEBUG") {
    print("Debug mode: \(debugMode)")
}
```

---

---

## 🤖 MCP Server — AI Remote Control

NetChecker includes a built-in **MCP (Model Context Protocol)** server that lets AI coding tools (Claude Code, Cursor, etc.) **directly control your app**: send API requests through the device, trigger actions, inspect traffic, and run test suites — all without touching the screen.

### How It Works

```
AI Tool (Claude Code, Cursor)
  ↓ MCP JSON-RPC over stdio
Node.js Bridge (netchecker-mcp.js)
  ↓ HTTP over Wi-Fi
NetChecker MCP Server (on device, port 9876)
  ↓
Your App (real auth tokens, cookies, certificates)
```

### Setup

**1. Start the MCP server in your app:**

```swift
// Start manually from code
MCPServer.shared.start()

// Or use the AI Control tab in the demo app
```

**2. Add to your `.mcp.json`** (Claude Code / Cursor config):

```json
{
  "mcpServers": {
    "netchecker": {
      "command": "node",
      "args": ["/path/to/netchecker-mcp.js"],
      "env": {
        "NETCHECKER_URL": "http://<DEVICE_IP>:9876"
      }
    }
  }
}
```

The device IP is shown in Xcode console when the MCP server starts and in the AI Control tab.

**3. That's it.** AI can now control your app.

### MCP Tools

| Tool | Description |
|------|-------------|
| `netchecker_status` | Check if MCP server is running |
| `netchecker_log` | Send structured log entry (track API calls, file ops, code changes) |
| `netchecker_flow_start` | Start a named flow to group related operations |
| `netchecker_flow_end` | End a flow — triggers test generation |
| `netchecker_list` | Get recorded HTTP requests (filter: `all`, `mcp`, `errors`) |
| `netchecker_get_record` | Get full details of a single request (headers, body) |
| `netchecker_clear` | Clear all recorded traffic |
| `netchecker_execute` | **Execute HTTP request through the iOS device** (with real auth) |
| `netchecker_triggers` | List available app triggers |
| `netchecker_trigger` | Invoke a registered trigger (navigate, show UI, run tests) |

### Execute API Through Device

AI can send HTTP requests through your iOS app's network stack — with real authentication tokens, cookies, and certificates. No need to share credentials with AI.

```
# AI runs this:
netchecker_execute(url: "https://api.yourapp.com/me", method: "GET")

# The iOS device makes the request with its real session
# AI gets back: statusCode, headers, body, duration
```

### Custom Triggers

Register any app action as a trigger that AI can invoke remotely:

```swift
let registry = MCPActionRegistry.shared

// Navigate to a screen
registry.register(
    tag: "open_profile",
    name: "Open Profile",
    description: "Navigate to user profile",
    parameters: ["userId"]
) { params in
    let id = params["userId"] ?? "me"
    await AppRouter.shared.push(.profile(id))
    return "Opened profile: \(id)"
}

// Trigger a login flow
registry.register(
    tag: "login",
    name: "Login Test User",
    description: "Authenticate with test credentials"
) {
    try await AuthManager.shared.login(email: "test@app.com", password: "test123")
    return "Logged in, token: \(AuthManager.shared.token ?? "nil")"
}

// Add a mock and test error handling
registry.register(
    tag: "mock_auth_expired",
    name: "Simulate Token Expiry",
    description: "Return 401 for all API calls"
) {
    MockEngine.shared.addRule(.serverError(for: "*/api/*", statusCode: 401))
    MockEngine.shared.isEnabled = true
    return "401 mock active"
}

// Show AI message on device screen
registry.register(
    tag: "show_message",
    name: "Show Message",
    description: "Display overlay banner from AI",
    parameters: ["title", "body", "style"]
) { params in
    await MainActor.run {
        overlay.show(title: params["title"] ?? "", body: params["body"] ?? "", style: params["style"] ?? "info")
    }
    return "Message shown"
}
```

### AI Testing Workflow Example

Tell your AI assistant:

> "Use netchecker to: add a 500 error mock, fetch /posts/1, check the traffic for errors, clear the mock, and fetch again. Show before/after comparison."

The AI will:
1. `netchecker_trigger(tag: "add_mock_error")` — enable 500 mock
2. `netchecker_trigger(tag: "fetch_post", params: {id: "1"})` — request through device
3. `netchecker_list(filter: "errors")` — inspect traffic
4. `netchecker_trigger(tag: "clear_mocks")` — remove mock
5. `netchecker_trigger(tag: "fetch_post", params: {id: "1"})` — re-test
6. Report results with comparison

### Node.js Bridge

The bridge (`netchecker-mcp.js`) is zero-dependency — pure Node.js built-ins. It auto-discovers the device:
- Tries `localhost:9876` first (iOS Simulator)
- Falls back to `NETCHECKER_URL` env var (real device over Wi-Fi)
- Auto-retries on connection failure

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
| `EnvironmentSwitcherView` | Environment management UI *(Coming Soon)* |
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

### Debug vs Release Builds

NetChecker works in both Debug and Release builds (including TestFlight). You control when to enable it:

```swift
// Option 1: Debug only (recommended for most apps)
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

// Option 2: Enable in TestFlight for QA testing
@main
struct MyApp: App {
    init() {
        #if DEBUG || TESTFLIGHT
        TrafficInterceptor.shared.start()
        #endif
    }
}

// Option 3: Always available (for internal/enterprise apps)
TrafficInterceptor.shared.start()
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

- [x] MCP Server for AI tool integration
- [x] Execute API requests through device (real auth)
- [x] Custom triggers for remote app control
- [x] AI-driven test automation
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
