# NetChecker Traffic SDK

A powerful HTTP/HTTPS traffic inspection SDK for iOS applications. Monitor, debug, and test network requests directly within your app - like having Charles Proxy built-in.

## Features

- **Real-time Traffic Monitoring** - Intercept and display all HTTP/HTTPS requests
- **Request Details** - View headers, body, query parameters, and cookies
- **Response Inspection** - See status codes, response headers, and formatted body content
- **Timing Analysis** - DNS, TCP, TLS handshake, and response time breakdown
- **Edit & Retry** - Modify headers (Bearer tokens, API keys) and body, then resend requests
- **Export** - Copy as cURL command or export to HAR format
- **Filtering** - Filter by method, status code, content type, or search text

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/shakhzodsunnatov/netcheckerSDK.git", from: "1.0.0")
]
```

Or in Xcode: File → Add Package Dependencies → Enter repository URL

Add the dependency to your target:

```swift
.product(name: "NetCheckerTraffic", package: "NetCheckerTraffic"),
```

## Quick Start

### 1. Import and Start

```swift
import SwiftUI
import NetCheckerTraffic

@main
struct MyApp: App {
    init() {
        // Start intercepting traffic
        TrafficInterceptor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 2. Add Traffic UI

```swift
import SwiftUI
import NetCheckerTraffic

struct ContentView: View {
    var body: some View {
        TabView {
            // Your app content
            YourMainView()
                .tabItem { Label("Home", systemImage: "house") }

            // Traffic inspector tab
            TrafficListView()
                .tabItem { Label("Traffic", systemImage: "arrow.up.arrow.down.circle") }
        }
    }
}
```

That's it! All network requests will now appear in the Traffic tab.

## Usage Examples

### Interception Levels

```swift
// Full interception (headers + body)
TrafficInterceptor.shared.start(level: .full)

// Headers only (better performance)
TrafficInterceptor.shared.start(level: .headersOnly)

// Minimal (URL and status only)
TrafficInterceptor.shared.start(level: .minimal)

// Stop interception
TrafficInterceptor.shared.stop()
```

### Filtering Specific Hosts

```swift
var config = InterceptorConfiguration()
config.includedHosts = ["api.myapp.com", "api.example.com"]
// OR exclude hosts
config.excludedHosts = ["analytics.com", "crashlytics.com"]

TrafficInterceptor.shared.start(configuration: config)
```

### Access Traffic Programmatically

```swift
import NetCheckerTraffic

// Get all recorded traffic
let records = TrafficStore.shared.records

// Filter records
let filter = TrafficFilter()
filter.methods = [.get, .post]
filter.statusCategories = [.success, .clientError]
let filtered = filter.apply(to: records)

// Listen for new records
TrafficStore.shared.$records
    .sink { records in
        print("Total requests: \(records.count)")
    }
    .store(in: &cancellables)

// Clear all records
TrafficStore.shared.clear()
```

### Export as cURL

```swift
let record = TrafficStore.shared.records.first!
let curl = CURLFormatter.format(record: record)
// Output: curl -X GET 'https://api.example.com/users' -H 'Authorization: Bearer ...'
```

### Export as HAR

```swift
let records = TrafficStore.shared.records
if let harData = HARFormatter.format(records: records) {
    // Save or share HAR file
}
```

## UI Components

### Main Views

| View | Description |
|------|-------------|
| `TrafficListView` | Main list showing all intercepted requests |
| `TrafficDetailView` | Detailed view with Request/Response/Timing tabs |
| `RequestEditorView` | Edit headers and body, then retry request |

### Detail Tabs

- **Request** - URL breakdown, headers, query params, body, cookies
- **Response** - Status code, headers, formatted body (JSON syntax highlighting)
- **Timing** - Visual waterfall chart showing DNS/TCP/TLS/Download times
- **Security** - TLS version, cipher suite, certificate chain (when available)

### Floating Indicator (Optional)

Add a floating badge that shows request count:

```swift
ZStack {
    YourContentView()

    FloatingTrafficBadge()
}
```

## Edit & Retry Feature

The SDK includes a powerful request editor:

1. Tap any request in the list to open details
2. Tap the menu button and select "Edit & Retry"
3. Modify:
   - URL
   - HTTP Method
   - Headers (add/edit/remove)
   - Request Body
4. Use **Quick Add** buttons for common headers:
   - Bearer Token
   - Content-Type: application/json
   - API Key
5. Tap **Send** to execute the modified request
6. View the response inline

This is perfect for:
- Testing different auth tokens
- Debugging API responses with modified parameters
- Exploring API behavior without rebuilding the app

## Configuration Options

```swift
var config = InterceptorConfiguration()

// Hosts to include/exclude
config.includedHosts = ["api.myapp.com"]
config.excludedHosts = ["analytics.com"]

// Maximum records to keep (ring buffer)
config.maxRecords = 1000

// Redact sensitive headers
config.redactedHeaders = ["Authorization", "Cookie", "X-API-Key"]

// Interception level
config.level = .full // .full, .headersOnly, .minimal

TrafficInterceptor.shared.start(configuration: config)
```

## Best Practices

### Debug Builds Only

```swift
#if DEBUG
TrafficInterceptor.shared.start()
#endif
```

### Exclude from App Store Builds

The SDK uses URLProtocol swizzling which is safe for development but should be disabled in production:

```swift
#if DEBUG
import NetCheckerTraffic
#endif

// In your app setup:
#if DEBUG
TrafficInterceptor.shared.start()
#endif
```

### Performance

- Use `.headersOnly` level if you don't need body inspection
- Set `maxRecords` to limit memory usage
- Exclude high-frequency hosts (analytics, logging) from interception

## Requirements

- iOS 16.0+
- macOS 13.0+
- Swift 5.9+

## License

MIT License - See LICENSE file for details.

## Support

- GitHub Issues: [Report a bug](https://github.com/shakhzodsunnatov/netcheckerSDK/issues)
