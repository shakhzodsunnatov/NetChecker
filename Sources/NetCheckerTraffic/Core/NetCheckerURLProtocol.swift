import Foundation

/// URLProtocol для перехвата HTTP/HTTPS запросов
public final class NetCheckerURLProtocol: URLProtocol {
    // MARK: - Constants

    /// Ключ для маркировки обработанных запросов
    private static let handledKey = "NetCheckerHandled"

    // MARK: - Thread-Safe State

    /// Thread-safe flag for interception state (accessed from canInit)
    private static var _isIntercepting: Bool = false
    private static let lock = NSLock()

    /// Thread-safe configuration snapshot
    private static var _configSnapshot: InterceptorConfiguration = .default

    /// Update interception state (called from main actor)
    static func setIntercepting(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _isIntercepting = enabled
    }

    /// Update configuration snapshot (called from main actor)
    static func updateConfiguration(_ config: InterceptorConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        _configSnapshot = config
    }

    private static var isIntercepting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isIntercepting
    }

    private static var configSnapshot: InterceptorConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return _configSnapshot
    }

    // MARK: - Properties

    private var dataTask: URLSessionDataTask?
    private var receivedData: Data = Data()
    private var receivedResponse: HTTPURLResponse?
    private var startTime: Date = Date()
    private var recordId: UUID?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.protocolClasses = [] // Prevent recursion
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // MARK: - URLProtocol Override

    public override class func canInit(with request: URLRequest) -> Bool {
        // Skip already handled requests
        if URLProtocol.property(forKey: handledKey, in: request) != nil {
            return false
        }

        // Check if interception is enabled (thread-safe)
        guard isIntercepting else {
            return false
        }

        // Get thread-safe configuration snapshot
        let config = configSnapshot

        // Check callback filter
        if let shouldIntercept = config.shouldIntercept {
            if !shouldIntercept(request) {
                return false
            }
        }

        guard let url = request.url, let host = url.host else {
            return false
        }

        // Check ignore hosts
        if config.ignoreHosts.contains(host.lowercased()) {
            return false
        }

        // Check capture hosts (if specified)
        if let captureHosts = config.captureHosts {
            if !captureHosts.contains(host.lowercased()) {
                return false
            }
        }

        // Check methods
        if let captureMethods = config.captureMethods {
            let method = HTTPMethod(from: request)
            if !captureMethods.contains(method) {
                return false
            }
        }

        // Check path patterns
        for pattern in config.ignorePathPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let path = url.path
                let range = NSRange(path.startIndex..., in: path)
                if regex.firstMatch(in: path, options: [], range: range) != nil {
                    return false
                }
            }
        }

        return true
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        startTime = Date()

        // Create a mutable copy and mark as handled
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown))
            return
        }

        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)

        // Create and store traffic record
        let record = TrafficRecord(from: mutableRequest as URLRequest)
        recordId = record.id

        // Perform main actor operations and then start the request
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Apply environment URL rewriting
            if let rewrittenURL = EnvironmentStore.shared.rewriteURL(mutableRequest.url) {
                mutableRequest.url = rewrittenURL
            }

            TrafficStore.shared.add(record)

            // Check for mocks first
            if let mockResponse = MockEngine.shared.match(request: mutableRequest as URLRequest) {
                self.handleMockResponse(mockResponse)
                return
            }

            // Check for breakpoints - this will pause and wait for user action
            if BreakpointEngine.shared.shouldPause(request: mutableRequest as URLRequest) {
                // Pause the request and wait for user to resume/cancel
                let result = await BreakpointEngine.shared.pause(request: mutableRequest as URLRequest)

                if let modifiedRequest = result {
                    // User resumed - use the (possibly modified) request
                    // Update mutableRequest with any modifications
                    if let newURL = modifiedRequest.url {
                        mutableRequest.url = newURL
                    }
                    if let method = modifiedRequest.httpMethod {
                        mutableRequest.httpMethod = method
                    }
                    mutableRequest.allHTTPHeaderFields = modifiedRequest.allHTTPHeaderFields
                    mutableRequest.httpBody = modifiedRequest.httpBody
                } else {
                    // User cancelled - fail the request
                    self.client?.urlProtocol(self, didFailWithError: NSError(
                        domain: NSURLErrorDomain,
                        code: NSURLErrorCancelled,
                        userInfo: [NSLocalizedDescriptionKey: "Request cancelled by breakpoint"]
                    ))
                    return
                }
            }

            // Start the actual request on the URL loading queue
            self.dataTask = self.session.dataTask(with: mutableRequest as URLRequest)
            self.dataTask?.resume()
        }
    }

    public override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
    }

    // MARK: - Mock Handling

    private func handleMockResponse(_ mockResponse: MockResponse) {
        // Simulate delay if specified
        if let delay = mockResponse.delay, delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }

        // Create HTTP response
        guard let url = request.url else { return }

        let response = HTTPURLResponse(
            url: url,
            statusCode: mockResponse.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: mockResponse.headers
        )!

        // Update record
        if let id = recordId {
            Task { @MainActor in
                TrafficStore.shared.update(id: id) { record in
                    record.complete(
                        with: ResponseData(from: response, body: mockResponse.body, isFromCache: false)
                    )
                    record.markAsMocked()
                }
            }
        }

        // Deliver to client
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body = mockResponse.body {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
}

// MARK: - URLSessionDataDelegate

extension NetCheckerURLProtocol: URLSessionDataDelegate {
    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        receivedResponse = response as? HTTPURLResponse
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
        client?.urlProtocol(self, didLoad: data)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // Update record with error
            if let id = recordId {
                Task { @MainActor in
                    TrafficStore.shared.fail(id: id, error: error)
                }
            }
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            // Update record with response
            if let id = recordId, let response = receivedResponse {
                // Use thread-safe config snapshot
                let config = Self.configSnapshot
                let body = config.captureResponseBody ? receivedData : nil

                // Timings are handled via URLSessionTaskDelegate didFinishCollecting metrics
                let timings: RequestTimings? = nil

                Task { @MainActor in
                    TrafficStore.shared.complete(
                        id: id,
                        response: ResponseData(from: response, body: body),
                        timings: timings
                    )
                }
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Record redirect
        if let id = recordId,
           let fromURL = task.currentRequest?.url,
           let toURL = request.url {
            let hop = RedirectHop(
                fromURL: fromURL,
                toURL: toURL,
                statusCode: response.statusCode,
                headers: response.allHeaderFields as? [String: String] ?? [:]
            )

            Task { @MainActor in
                TrafficStore.shared.update(id: id) { record in
                    record.addRedirect(hop)
                }
            }
        }

        // Allow redirect
        completionHandler(request)
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Handle SSL trust based on configuration (thread-safe)
        let config = Self.configSnapshot.ssl

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        switch config.trustMode {
        case .strict:
            completionHandler(.performDefaultHandling, nil)

        case .allowSelfSigned(let hosts):
            if hosts.contains(host.lowercased()) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }

        case .allowExpired(let hosts):
            if hosts.contains(host.lowercased()) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }

        case .allowInvalidHost(let hosts):
            if hosts.contains(host.lowercased()) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }

        case .allowAll(let understood):
            if understood {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }

        case .allowProxy(let proxyHosts):
            if proxyHosts.contains(host.lowercased()) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }

        case .custom(let handler):
            if handler(serverTrust, host) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
}

// MARK: - URLSessionTaskDelegate

extension NetCheckerURLProtocol: URLSessionTaskDelegate {
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        // Metrics are handled in didCompleteWithError
    }
}
