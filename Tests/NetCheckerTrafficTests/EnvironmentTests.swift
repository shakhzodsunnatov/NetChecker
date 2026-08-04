import XCTest
@testable import NetCheckerTrafficCore

/// Тесты переписывания URL — чистые функции, без синглтонов
final class URLRewriterTests: XCTestCase {

    private let url = URL(string: "https://api.example.com/v1/users?page=2")!

    // MARK: - matches

    func testMatchesExactHost() {
        XCTAssertTrue(URLRewriter.matches(url: url, pattern: "api.example.com"))
    }

    func testMatchesIsCaseInsensitive() {
        XCTAssertTrue(URLRewriter.matches(url: url, pattern: "API.EXAMPLE.COM"))
    }

    func testMatchesLeadingWildcard() {
        XCTAssertTrue(URLRewriter.matches(url: url, pattern: "*.example.com"))
    }

    func testMatchesTrailingWildcard() {
        XCTAssertTrue(URLRewriter.matches(url: url, pattern: "api.*"))
    }

    func testDoesNotMatchDifferentHost() {
        XCTAssertFalse(URLRewriter.matches(url: url, pattern: "api.other.com"))
    }

    func testDoesNotMatchWhenURLHasNoHost() {
        let hostless = URL(string: "file:///tmp/report.json")!
        XCTAssertFalse(URLRewriter.matches(url: hostless, pattern: "*"))
    }

    // MARK: - rewrite

    func testRewriteReplacesHostAndKeepsPathAndQuery() {
        let target = URL(string: "https://staging.example.com")!
        let result = URLRewriter.rewrite(url: url, from: "api.example.com", to: target)

        XCTAssertEqual(result?.host, "staging.example.com")
        XCTAssertEqual(result?.path, "/v1/users")
        XCTAssertEqual(result?.query, "page=2")
    }

    func testRewriteReturnsNilWhenPatternDoesNotMatch() {
        let target = URL(string: "https://staging.example.com")!
        XCTAssertNil(URLRewriter.rewrite(url: url, from: "nope.example.com", to: target))
    }

    func testRewriteCarriesTargetSchemeAndPort() {
        let target = URL(string: "http://localhost:8080")!
        let result = URLRewriter.rewrite(url: url, from: "api.example.com", to: target)

        XCTAssertEqual(result?.scheme, "http")
        XCTAssertEqual(result?.host, "localhost")
        XCTAssertEqual(result?.port, 8080)
    }

    func testRewritePrependsTargetPathPrefix() {
        let target = URL(string: "https://gateway.example.com/proxy")!
        let result = URLRewriter.rewrite(url: url, from: "api.example.com", to: target)

        XCTAssertEqual(result?.path, "/proxy/v1/users")
    }

    // MARK: - Точечные преобразования

    func testRewriteHostOnly() {
        XCTAssertEqual(URLRewriter.rewriteHost(url: url, to: "dev.example.com")?.host, "dev.example.com")
    }

    func testRewriteHostAndPort() {
        let result = URLRewriter.rewriteHostAndPort(url: url, to: "localhost", port: 3000)
        XCTAssertEqual(result?.host, "localhost")
        XCTAssertEqual(result?.port, 3000)
    }

    func testRewriteScheme() {
        XCTAssertEqual(URLRewriter.rewriteScheme(url: url, to: "http")?.scheme, "http")
    }

    func testRewritePathPrefix() {
        let result = URLRewriter.rewritePath(url: url, from: "/v1", to: "/v2")
        XCTAssertEqual(result?.path, "/v2/users")
    }

    func testRewritePathLeavesNonMatchingPrefixAlone() {
        let result = URLRewriter.rewritePath(url: url, from: "/api", to: "/v2")
        XCTAssertEqual(result?.path, "/v1/users")
    }
}

/// Тесты моделей окружений — значимые типы, без синглтонов
final class EnvironmentModelTests: XCTestCase {

    private func makeGroup() -> EnvironmentGroup {
        EnvironmentGroup(
            name: "API",
            sourcePattern: "api.example.com",
            environments: [
                Environment(
                    name: "Production",
                    baseURL: URL(string: "https://api.example.com")!,
                    isDefault: true,
                    variables: ["DEBUG": "false"]
                ),
                Environment(
                    name: "Staging",
                    baseURL: URL(string: "https://staging.example.com")!,
                    headers: ["X-Env": "staging"],
                    variables: ["DEBUG": "true"]
                )
            ]
        )
    }

    func testGroupActivatesDefaultEnvironment() {
        XCTAssertEqual(makeGroup().activeEnvironment?.name, "Production")
    }

    func testGroupFallsBackToFirstEnvironmentWhenNoDefault() {
        let group = EnvironmentGroup(
            name: "API",
            sourcePattern: "api.example.com",
            environments: [
                Environment(name: "Staging", baseURL: URL(string: "https://staging.example.com")!),
                Environment(name: "Dev", baseURL: URL(string: "https://dev.example.com")!)
            ]
        )
        XCTAssertEqual(group.activeEnvironment?.name, "Staging")
    }

    func testGroupReportsEnvironmentCount() {
        XCTAssertEqual(makeGroup().environmentCount, 2)
        XCTAssertFalse(makeGroup().isEmpty)
    }

    func testRewriteReturnsNoURLWhenActiveEnvironmentIsTheSameHost() {
        // Production активна и совпадает с исходным хостом — переписывать нечего
        let result = makeGroup().rewrite(URL(string: "https://api.example.com/users")!)
        XCTAssertNil(result.url)
    }

    func testRewriteChangesHostWhenActiveEnvironmentDiffers() {
        var group = makeGroup()
        let staging = group.environments[1]
        group.activeEnvironmentId = staging.id

        let result = group.rewrite(URL(string: "https://api.example.com/users?a=1")!)

        XCTAssertEqual(result.url?.host, "staging.example.com")
        XCTAssertEqual(result.url?.path, "/users")
        XCTAssertEqual(result.url?.query, "a=1")
        XCTAssertEqual(result.headers["X-Env"], "staging")
    }

    func testRewriteIgnoresUnrelatedHost() {
        let result = makeGroup().rewrite(URL(string: "https://cdn.other.com/img.png")!)
        XCTAssertNil(result.url)
        XCTAssertTrue(result.headers.isEmpty)
    }

    func testEnvironmentInitFromURLStringRejectsGarbage() {
        XCTAssertNil(Environment(name: "Bad", urlString: ""))
        XCTAssertNotNil(Environment(name: "Good", urlString: "https://example.com"))
    }
}

/// Тесты EnvironmentStore — синглтон, состояние чистится до и после каждого теста
@MainActor
final class EnvironmentStoreTests: XCTestCase {

    private var store: EnvironmentStore { EnvironmentStore.shared }

    override func setUp() async throws {
        try await super.setUp()
        reset()
    }

    override func tearDown() async throws {
        reset()
        try await super.tearDown()
    }

    private func reset() {
        store.clearQuickOverrides()
        for group in store.groups {
            store.removeGroup(id: group.id)
        }
    }

    private func addAPIGroup() -> EnvironmentGroup {
        let group = EnvironmentGroup(
            name: "API",
            sourcePattern: "api.example.com",
            environments: [
                Environment(
                    name: "Production",
                    baseURL: URL(string: "https://api.example.com")!,
                    isDefault: true,
                    variables: ["MODE": "prod"]
                ),
                Environment(
                    name: "Staging",
                    baseURL: URL(string: "https://staging.example.com")!,
                    variables: ["MODE": "staging"]
                )
            ]
        )
        store.addGroup(group)
        return group
    }

    func testAddGroupIsStored() {
        _ = addAPIGroup()

        XCTAssertTrue(store.hasGroups)
        XCTAssertEqual(store.totalEnvironmentCount, 2)
        XCTAssertNotNil(store.group(named: "API"))
    }

    func testRemoveGroup() {
        let group = addAPIGroup()
        store.removeGroup(id: group.id)

        XCTAssertFalse(store.hasGroups)
        XCTAssertNil(store.group(named: "API"))
    }

    func testGroupLookupByHost() {
        _ = addAPIGroup()
        XCTAssertEqual(store.group(for: "api.example.com")?.name, "API")
        XCTAssertNil(store.group(for: "unrelated.com"))
    }

    func testSwitchEnvironmentByName() {
        _ = addAPIGroup()
        store.switchEnvironment(group: "API", to: "Staging")

        XCTAssertEqual(store.activeEnvironment(for: "API")?.name, "Staging")
    }

    func testVariableResolvesFromActiveEnvironment() {
        _ = addAPIGroup()
        XCTAssertEqual(store.variable("MODE"), "prod")

        store.switchEnvironment(group: "API", to: "Staging")
        XCTAssertEqual(store.variable("MODE"), "staging")
    }

    func testVariableReturnsNilForUnknownKey() {
        _ = addAPIGroup()
        XCTAssertNil(store.variable("NOPE"))
    }

    func testRewriteAppliesActiveEnvironment() {
        _ = addAPIGroup()
        store.switchEnvironment(group: "API", to: "Staging")

        let result = store.rewrite(URL(string: "https://api.example.com/users")!)
        XCTAssertEqual(result.url?.host, "staging.example.com")
    }

    func testRewriteReturnsNoneForUnknownHost() {
        _ = addAPIGroup()
        XCTAssertNil(store.rewrite(URL(string: "https://elsewhere.com/x")!).url)
    }

    func testRewriteHandlesNilURL() {
        XCTAssertNil(store.rewrite(nil).url)
    }

    // MARK: - Quick overrides

    func testQuickOverrideRedirectsHost() {
        store.addQuickOverride(from: "api.example.com", to: "http://localhost:8080")

        XCTAssertTrue(store.hasActiveOverride)
        let result = store.rewrite(URL(string: "https://api.example.com/users")!)
        XCTAssertEqual(result.url?.host, "localhost")
    }

    func testQuickOverrideTakesPriorityOverEnvironment() {
        _ = addAPIGroup()
        store.switchEnvironment(group: "API", to: "Staging")
        store.addQuickOverride(from: "api.example.com", to: "http://localhost:9999")

        let result = store.rewrite(URL(string: "https://api.example.com/users")!)
        XCTAssertEqual(result.url?.host, "localhost")
    }

    func testQuickOverrideSourceHostIsNormalized() {
        store.addQuickOverride(from: "API.Example.COM", to: "http://localhost:8080")
        XCTAssertNotNil(store.rewrite(URL(string: "https://api.example.com/x")!).url)
    }

    func testRemoveQuickOverride() {
        store.addQuickOverride(from: "api.example.com", to: "http://localhost:8080")
        store.removeQuickOverride(for: "api.example.com")

        XCTAssertFalse(store.hasActiveOverride)
    }

    func testExpiredQuickOverrideIsNotApplied() {
        // Истёкший override отбрасывается при первом же обращении к rewrite
        store.addQuickOverride(from: "api.example.com", to: "http://localhost:8080", autoDisableAfter: -1)

        let result = store.rewrite(URL(string: "https://api.example.com/users")!)
        XCTAssertNil(result.url)
    }
}
