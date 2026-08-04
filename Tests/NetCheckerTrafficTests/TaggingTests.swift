import XCTest
@testable import NetCheckerTrafficCore

final class TrafficTagRuleTests: XCTestCase {

    private let checkout = URL(string: "https://api.example.com/api/checkout/start")!

    func testSubstringPatternMatches() {
        let rule = TrafficTagRule(tag: "NewFeatureFlow", urlPattern: "/checkout/")
        XCTAssertTrue(rule.matches(url: checkout, method: .post))
    }

    func testWildcardPatternMatches() {
        let rule = TrafficTagRule(tag: "NewFeatureFlow", urlPattern: "*/api/checkout/*")
        XCTAssertTrue(rule.matches(url: checkout, method: .get))
    }

    func testNonMatchingURLIsRejected() {
        let rule = TrafficTagRule(tag: "NewFeatureFlow", urlPattern: "/profile/")
        XCTAssertFalse(rule.matches(url: checkout, method: .get))
    }

    func testMethodNarrowsTheMatch() {
        let rule = TrafficTagRule(tag: "NewFeatureFlow", urlPattern: "/checkout/", method: .post)

        XCTAssertTrue(rule.matches(url: checkout, method: .post))
        XCTAssertFalse(rule.matches(url: checkout, method: .get))
    }

    func testDisabledRuleNeverMatches() {
        let rule = TrafficTagRule(tag: "X", urlPattern: "/checkout/", isEnabled: false)
        XCTAssertFalse(rule.matches(url: checkout, method: .post))
    }

    func testEmptyPatternNeverMatches() {
        let rule = TrafficTagRule(tag: "X", urlPattern: "")
        XCTAssertFalse(rule.matches(url: checkout, method: .post))
    }

    func testMatchingIsCaseInsensitive() {
        let rule = TrafficTagRule(tag: "X", urlPattern: "/CHECKOUT/")
        XCTAssertTrue(rule.matches(url: checkout, method: .post))
    }
}

@MainActor
final class TrafficTaggerTests: XCTestCase {

    private var tagger: TrafficTagger { TrafficTagger.shared }
    private let checkout = URL(string: "https://api.example.com/api/checkout/start")!

    override func setUp() async throws {
        try await super.setUp()
        tagger.clearRules()
        TrafficStore.shared.clear()
    }

    override func tearDown() async throws {
        tagger.clearRules()
        TrafficStore.shared.clear()
        try await super.tearDown()
    }

    func testTagsForMatchingRequest() {
        tagger.tag("NewFeatureFlow", matching: "/checkout/")

        XCTAssertEqual(tagger.tags(for: checkout, method: .post), ["NewFeatureFlow"])
    }

    func testUnmatchedRequestGetsNoTags() {
        tagger.tag("NewFeatureFlow", matching: "/checkout/")

        let other = URL(string: "https://api.example.com/profile")!
        XCTAssertTrue(tagger.tags(for: other, method: .get).isEmpty)
    }

    func testSeveralRulesCanShareOneTagWithoutDuplicating() {
        tagger.tag("NewFeatureFlow", matching: "/checkout/")
        tagger.tag("NewFeatureFlow", matching: "/api/")

        // Оба правила совпадают, но тег должен быть один
        XCTAssertEqual(tagger.tags(for: checkout, method: .post), ["NewFeatureFlow"])
    }

    func testOneRequestCanCarrySeveralTags() {
        tagger.tag("NewFeatureFlow", matching: "/checkout/")
        tagger.tag("Payments", matching: "/checkout/")

        XCTAssertEqual(Set(tagger.tags(for: checkout, method: .post)), ["NewFeatureFlow", "Payments"])
    }

    func testKnownTagsAreDeduplicatedAndSorted() {
        tagger.tag("Beta", matching: "/b/")
        tagger.tag("Alpha", matching: "/a/")
        tagger.tag("Alpha", matching: "/a2/")

        XCTAssertEqual(tagger.knownTags, ["Alpha", "Beta"])
    }

    func testRemoveRule() {
        tagger.tag("X", matching: "/checkout/")
        let id = tagger.rules[0].id
        tagger.removeRule(id: id)

        XCTAssertTrue(tagger.tags(for: checkout, method: .post).isEmpty)
    }

    func testDisablingRuleStopsTagging() {
        tagger.tag("X", matching: "/checkout/")
        var rule = tagger.rules[0]
        rule.isEnabled = false
        tagger.updateRule(rule)

        XCTAssertTrue(tagger.tags(for: checkout, method: .post).isEmpty)
    }

    // MARK: - Применение к записанному трафику

    func testReapplyTagsExistingRecords() {
        let record = TrafficRecord(request: RequestData(url: checkout, method: .post))
        TrafficStore.shared.add(record)

        tagger.tag("NewFeatureFlow", matching: "/checkout/")
        tagger.reapplyToStoredTraffic()

        XCTAssertEqual(
            TrafficStore.shared.record(for: record.id)?.metadata.tags,
            ["NewFeatureFlow"]
        )
    }

    func testReapplyDoesNotDuplicateExistingTags() {
        let record = TrafficRecord(request: RequestData(url: checkout, method: .post))
        TrafficStore.shared.add(record)

        tagger.tag("NewFeatureFlow", matching: "/checkout/")
        tagger.reapplyToStoredTraffic()
        tagger.reapplyToStoredTraffic()

        XCTAssertEqual(TrafficStore.shared.record(for: record.id)?.metadata.tags.count, 1)
    }

    func testReapplyLeavesUnrelatedRecordsAlone() {
        let other = TrafficRecord(
            request: RequestData(url: URL(string: "https://api.example.com/profile")!, method: .get)
        )
        TrafficStore.shared.add(other)

        tagger.tag("NewFeatureFlow", matching: "/checkout/")
        tagger.reapplyToStoredTraffic()

        XCTAssertTrue(TrafficStore.shared.record(for: other.id)?.metadata.tags.isEmpty ?? false)
    }
}

/// Ручная пометка: выделить запросы в списке и навесить тег
@MainActor
final class ManualTaggingTests: XCTestCase {

    private var store: TrafficStore { TrafficStore.shared }
    private var tagger: TrafficTagger { TrafficTagger.shared }

    override func setUp() async throws {
        try await super.setUp()
        store.clear()
        tagger.clearRules()
        for tag in tagger.customTags { tagger.forgetTag(tag) }
    }

    override func tearDown() async throws {
        store.clear()
        tagger.clearRules()
        for tag in tagger.customTags { tagger.forgetTag(tag) }
        try await super.tearDown()
    }

    @discardableResult
    private func addRecord(_ path: String) -> TrafficRecord {
        let record = TrafficRecord(
            request: RequestData(url: URL(string: "https://api.example.com\(path)")!, method: .get)
        )
        store.add(record)
        return record
    }

    func testTagSeveralRecordsAtOnce() {
        let first = addRecord("/a")
        let second = addRecord("/b")
        addRecord("/c")

        store.addTag("NewFeatureFlow", to: [first.id, second.id])

        XCTAssertEqual(store.record(for: first.id)?.metadata.tags, ["NewFeatureFlow"])
        XCTAssertEqual(store.record(for: second.id)?.metadata.tags, ["NewFeatureFlow"])
        XCTAssertEqual(store.usedTags, ["NewFeatureFlow"])
    }

    func testTaggingTwiceDoesNotDuplicate() {
        let record = addRecord("/a")

        store.addTag("Flow", to: [record.id])
        store.addTag("Flow", to: [record.id])

        XCTAssertEqual(store.record(for: record.id)?.metadata.tags.count, 1)
    }

    func testRemoveTag() {
        let record = addRecord("/a")
        store.addTag("Flow", to: [record.id])
        store.removeTag("Flow", from: [record.id])

        XCTAssertTrue(store.record(for: record.id)?.metadata.tags.isEmpty ?? false)
    }

    func testAllRecordsHaveTagReportsPartialSelection() {
        let first = addRecord("/a")
        let second = addRecord("/b")

        store.addTag("Flow", to: [first.id])

        XCTAssertTrue(store.allRecords([first.id], haveTag: "Flow"))
        XCTAssertFalse(store.allRecords([first.id, second.id], haveTag: "Flow"))
    }

    func testEmptySelectionIsNotConsideredTagged() {
        XCTAssertFalse(store.allRecords([], haveTag: "Flow"))
    }

    func testBlankTagIsIgnored() {
        let record = addRecord("/a")
        store.addTag("   ", to: [record.id])

        XCTAssertTrue(store.record(for: record.id)?.metadata.tags.isEmpty ?? false)
    }

    func testTagIsTrimmed() {
        let record = addRecord("/a")
        store.addTag("  Flow  ", to: [record.id])

        XCTAssertEqual(store.record(for: record.id)?.metadata.tags, ["Flow"])
    }

    func testUsedTagsAreDeduplicatedAndSorted() {
        let first = addRecord("/a")
        let second = addRecord("/b")

        store.addTag("Beta", to: [first.id])
        store.addTag("Alpha", to: [first.id, second.id])

        XCTAssertEqual(store.usedTags, ["Alpha", "Beta"])
    }

    // MARK: - Реестр имён

    func testRegisteredTagSurvivesClearingTraffic() {
        let record = addRecord("/a")
        tagger.registerTag("NewFeatureFlow")
        store.addTag("NewFeatureFlow", to: [record.id])

        store.clear()

        // Имя должно остаться доступным для следующей пометки
        XCTAssertTrue(tagger.knownTags.contains("NewFeatureFlow"))
    }

    func testKnownTagsCombineRulesManualAndTraffic() {
        tagger.tag("FromRule", matching: "/x/")
        tagger.registerTag("Manual")

        let record = addRecord("/a")
        store.addTag("FromTraffic", to: [record.id])

        XCTAssertEqual(tagger.knownTags, ["FromRule", "FromTraffic", "Manual"])
    }

    func testRegisteringSameTagTwiceKeepsOneEntry() {
        tagger.registerTag("Flow")
        tagger.registerTag("Flow")

        XCTAssertEqual(tagger.customTags, ["Flow"])
    }

    func testBlankTagIsNotRegistered() {
        tagger.registerTag("   ")
        XCTAssertTrue(tagger.customTags.isEmpty)
    }
}

final class TrafficFilterTagTests: XCTestCase {

    private func record(url: String, tags: [String]) -> TrafficRecord {
        var metadata = TrafficMetadata(from: URL(string: url)!)
        metadata.tags = tags

        return TrafficRecord(
            state: .completed,
            request: RequestData(url: URL(string: url)!, method: .get),
            response: ResponseData(statusCode: 200),
            metadata: metadata
        )
    }

    private lazy var records: [TrafficRecord] = [
        record(url: "https://api.example.com/checkout", tags: ["NewFeatureFlow"]),
        record(url: "https://api.example.com/pay", tags: ["NewFeatureFlow", "Payments"]),
        record(url: "https://api.example.com/profile", tags: [])
    ]

    func testFilterByTag() {
        var filter = TrafficFilter()
        filter.tags = ["NewFeatureFlow"]

        XCTAssertEqual(filter.apply(to: records).count, 2)
    }

    func testFilterMatchesAnyOfTheSelectedTags() {
        var filter = TrafficFilter()
        filter.tags = ["Payments", "Unused"]

        XCTAssertEqual(filter.apply(to: records).count, 1)
    }

    func testEmptyTagSetDoesNotFilter() {
        var filter = TrafficFilter()
        filter.tags = []

        XCTAssertEqual(filter.apply(to: records).count, records.count)
    }

    func testUntaggedRecordsAreExcludedWhenFiltering() {
        var filter = TrafficFilter()
        filter.tags = ["NewFeatureFlow"]

        XCTAssertFalse(filter.apply(to: records).contains { $0.path == "/profile" })
    }
}
