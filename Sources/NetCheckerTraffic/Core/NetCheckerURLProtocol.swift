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

    /// Thread-safe flag for response breakpoint (written on MainActor, read on URLSession delegate queue)
    private var _shouldPauseOnResponse: Bool = false
    private let responsePauseLock = NSLock()

    private var shouldPauseOnResponse: Bool {
        get {
            responsePauseLock.lock()
            defer { responsePauseLock.unlock() }
            return _shouldPauseOnResponse
        }
        set {
            responsePauseLock.lock()
            defer { responsePauseLock.unlock() }
            _shouldPauseOnResponse = newValue
        }
    }

    /// Ограничивать ли скорость доставки тела ответа.
    /// Пишется на MainActor, читается в очереди делегата URLSession.
    private var _shouldThrottleDownload: Bool = false
    private let throttleLock = NSLock()

    private var shouldThrottleDownload: Bool {
        get {
            throttleLock.lock()
            defer { throttleLock.unlock() }
            return _shouldThrottleDownload
        }
        set {
            throttleLock.lock()
            defer { throttleLock.unlock() }
            _shouldThrottleDownload = newValue
        }
    }

    /// Ответ придерживается до полной загрузки: либо ждёт брейкпоинт,
    /// либо будет отдан порциями по бюджету скорости
    private var isResponseHeld: Bool {
        shouldPauseOnResponse || shouldThrottleDownload
    }

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

        var record = TrafficRecord(from: mutableRequest as URLRequest)

        // Чтение httpBodyStream осушает его: InputStream одноразовый.
        // Если не вернуть тело обратно в запрос, дальше в сеть уйдёт пустое
        // тело — так SDK молча ломал multipart-загрузки и любые запросы,
        // собранные через поток (Alamofire и подобные).
        // httpBody и httpBodyStream взаимоисключающие: присваивание одного
        // обнуляет другое. Поэтому достаточно записать httpBody — обнулять
        // поток отдельно нельзя, это сотрёт только что записанное тело.
        if mutableRequest.httpBody == nil, let captured = record.request.body {
            mutableRequest.httpBody = captured
        }

        // Лимиты размера применяются к сохраняемой копии — уже после того,
        // как тело возвращено в запрос
        let captureConfig = Self.configSnapshot
        record.request.body = captureConfig.captureRequestBody
            ? captureConfig.bodyWithinLimits(record.request.body)
            : nil
        recordId = record.id

        // Perform main actor operations and then start the request
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Apply environment URL rewriting and headers
            let rewriteResult = EnvironmentStore.shared.rewrite(mutableRequest.url)

            // Apply rewritten URL if different
            if let rewrittenURL = rewriteResult.url {
                mutableRequest.url = rewrittenURL
            }

            // Apply environment headers (environment headers override existing ones)
            if !rewriteResult.headers.isEmpty {
                URLRewriter.applyHeaders(rewriteResult.headers, to: mutableRequest, overwrite: true)
            }

            // Автоматические теги: помечаем запрос по правилам, чтобы связанные
            // вызовы одного потока можно было отфильтровать по имени
            let autoTags = TrafficTagger.shared.tags(
                for: record.request.url,
                method: record.request.method
            )
            if !autoTags.isEmpty {
                record.metadata.tags.append(contentsOf: autoTags)
            }

            TrafficStore.shared.add(record)

            let conditions = NetworkConditionState.current

            // Симуляция потери пакета — отбрасываем запрос до отправки
            if conditions.shouldDropRequest() {
                let lostError = NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorNetworkConnectionLost,
                    userInfo: [NSLocalizedDescriptionKey: "Соединение потеряно (симуляция условий сети)"]
                )
                if let id = self.recordId {
                    TrafficStore.shared.fail(id: id, error: lostError)
                }
                self.client?.urlProtocol(self, didFailWithError: lostError)
                return
            }

            // Задержка правила .delay — ждём асинхронно, не блокируя поток загрузки
            if let mockDelay = MockEngine.shared.matchDelay(request: mutableRequest as URLRequest) {
                try? await Task.sleep(nanoseconds: UInt64(mockDelay * 1_000_000_000))
            }

            // Задержка условий сети
            if conditions.isEnabled, conditions.latency > 0 {
                try? await Task.sleep(nanoseconds: UInt64(conditions.latency * 1_000_000_000))
            }

            // Check for mocks first
            if let mockResponse = MockEngine.shared.match(request: mutableRequest as URLRequest) {
                await self.handleMockResponse(mockResponse)
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
                    let cancelError = NSError(
                        domain: NSURLErrorDomain,
                        code: NSURLErrorCancelled,
                        userInfo: [NSLocalizedDescriptionKey: "Request cancelled by breakpoint"]
                    )

                    // Update the traffic record to show as cancelled
                    if let id = self.recordId {
                        TrafficStore.shared.fail(id: id, error: cancelError)
                    }

                    self.client?.urlProtocol(self, didFailWithError: cancelError)
                    return
                }
            }

            // Check if we need to pause on response
            if BreakpointEngine.shared.shouldPauseResponse(request: mutableRequest as URLRequest) {
                self.shouldPauseOnResponse = true
            }

            // При ограничении скорости тело придерживается и отдаётся порциями
            if conditions.isEnabled, conditions.downloadBytesPerSecond != nil {
                self.shouldThrottleDownload = true
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

    private func handleMockResponse(_ mockResponse: MockResponse) async {
        // Задержка мока — асинхронное ожидание вместо блокировки потока загрузки
        if let delay = mockResponse.delay, delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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
            let requestBodyOverride = mockResponse.requestBodyOverride

            Task { @MainActor in
                TrafficStore.shared.update(id: id) { record in
                    // Правило может подменить тело запроса: настоящий запрос
                    // никуда не уходит, поэтому в записи показываем то тело,
                    // которое задал автор мока
                    if let override = requestBodyOverride {
                        record.request.body = override
                        record.request.bodySize = Int64(override.count)
                    }

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
        // Ответ придерживается, если ждёт брейкпоинт или троттлинг
        if !isResponseHeld {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
        // Накапливаем тело, но не отдаём, пока ответ придерживается
        if !isResponseHeld {
            client?.urlProtocol(self, didLoad: data)
        }
    }

    /// Отдать придержанный ответ клиенту.
    /// При включённом ограничении скорости тело доставляется порциями.
    private func deliverHeldResponse() async {
        if let response = receivedResponse {
            client?.urlProtocol(self, didReceive: response as URLResponse, cacheStoragePolicy: .notAllowed)
        }

        if !receivedData.isEmpty {
            if shouldThrottleDownload {
                for (chunk, delay) in NetworkConditionState.current.downloadChunks(for: receivedData) {
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    client?.urlProtocol(self, didLoad: chunk)
                }
            } else {
                client?.urlProtocol(self, didLoad: receivedData)
            }
        }

        client?.urlProtocolDidFinishLoading(self)

        if let id = recordId, let response = receivedResponse {
            let config = Self.configSnapshot
            let body = config.captureResponseBody ? config.bodyWithinLimits(receivedData) : nil
            await MainActor.run {
                var data = ResponseData(from: response, body: body)
                data.headers = config.redacted(headers: data.headers)
                TrafficStore.shared.complete(id: id, response: data, timings: nil)
            }
        }
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
        } else if shouldThrottleDownload && !shouldPauseOnResponse {
            // Троттлинг без брейкпоинта: отдаём придержанное тело порциями
            Task { [weak self] in
                guard let self = self else { return }
                await self.deliverHeldResponse()
            }
        } else if shouldPauseOnResponse {
            // Response breakpoint: pause before delivering response to client
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                let result = await BreakpointEngine.shared.pause(request: self.request, phase: .response)

                if result != nil {
                    // User resumed — deliver the held response to client
                    await self.deliverHeldResponse()
                } else {
                    // User cancelled — deliver error instead
                    let cancelError = NSError(
                        domain: NSURLErrorDomain,
                        code: NSURLErrorCancelled,
                        userInfo: [NSLocalizedDescriptionKey: "Response cancelled by breakpoint"]
                    )
                    if let id = self.recordId {
                        TrafficStore.shared.fail(id: id, error: cancelError)
                    }
                    self.client?.urlProtocol(self, didFailWithError: cancelError)
                }
            }
        } else {
            // Update record with response
            if let id = recordId, let response = receivedResponse {
                // Use thread-safe config snapshot
                let config = Self.configSnapshot
                let body = config.captureResponseBody ? config.bodyWithinLimits(receivedData) : nil

                // Timings are handled via URLSessionTaskDelegate didFinishCollecting metrics
                let timings: RequestTimings? = nil

                Task { @MainActor in
                    var data = ResponseData(from: response, body: body)
                    data.headers = config.redacted(headers: data.headers)
                    TrafficStore.shared.complete(id: id, response: data, timings: timings)
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
