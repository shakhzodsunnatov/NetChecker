import XCTest
@testable import NetCheckerTrafficCore

final class NetworkConditionProfileTests: XCTestCase {

    func testNegativeLatencyIsClampedToZero() {
        XCTAssertEqual(NetworkConditionProfile(name: "x", latency: -5).latency, 0)
    }

    func testPacketLossIsClampedToUnitRange() {
        XCTAssertEqual(NetworkConditionProfile(name: "x", packetLossRate: -1).packetLossRate, 0)
        XCTAssertEqual(NetworkConditionProfile(name: "x", packetLossRate: 42).packetLossRate, 1)
    }

    func testBandwidthIsClampedToAtLeastOneByte() {
        XCTAssertEqual(NetworkConditionProfile(name: "x", downloadBytesPerSecond: 0).downloadBytesPerSecond, 1)
    }

    func testNilBandwidthStaysNil() {
        XCTAssertNil(NetworkConditionProfile(name: "x").downloadBytesPerSecond)
    }

    func testOfflineProfileIsOffline() {
        XCTAssertTrue(NetworkConditionProfile.offline.isOffline)
        XCTAssertFalse(NetworkConditionProfile.threeG.isOffline)
    }

    func testNoneProfileIsTransparent() {
        XCTAssertTrue(NetworkConditionProfile.none.isTransparent)
        XCTAssertFalse(NetworkConditionProfile.edge.isTransparent)
    }

    func testSummaryDescribesOffline() {
        XCTAssertEqual(NetworkConditionProfile.offline.summary, "Соединение недоступно")
    }

    func testSummaryDescribesTransparent() {
        XCTAssertEqual(NetworkConditionProfile.none.summary, "Без ограничений")
    }

    func testSummaryListsEachConstraint() {
        let profile = NetworkConditionProfile(
            name: "Test",
            latency: 0.25,
            downloadBytesPerSecond: 100_000,
            packetLossRate: 0.1
        )
        XCTAssertTrue(profile.summary.contains("250 мс"))
        XCTAssertTrue(profile.summary.contains("10%"))
    }

    func testBuiltInProfilesAreMarkedAndUnique() {
        XCTAssertTrue(NetworkConditionProfile.builtIn.allSatisfy(\.isBuiltIn))
        XCTAssertEqual(Set(NetworkConditionProfile.builtIn.map(\.id)).count,
                       NetworkConditionProfile.builtIn.count)
    }

    func testProfileSurvivesCodableRoundTrip() throws {
        let original = NetworkConditionProfile.threeG
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NetworkConditionProfile.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}

final class NetworkConditionSnapshotTests: XCTestCase {

    func testDisabledSnapshotIsInactive() {
        XCTAssertFalse(NetworkConditionSnapshot.disabled.isActive)
    }

    func testEnabledButEmptySnapshotIsInactive() {
        let snapshot = NetworkConditionSnapshot(
            isEnabled: true, latency: 0, downloadBytesPerSecond: nil, packetLossRate: 0
        )
        XCTAssertFalse(snapshot.isActive)
    }

    func testSnapshotWithLatencyIsActive() {
        let snapshot = NetworkConditionSnapshot(
            isEnabled: true, latency: 0.5, downloadBytesPerSecond: nil, packetLossRate: 0
        )
        XCTAssertTrue(snapshot.isActive)
    }

    // MARK: - Потери пакетов

    func testDisabledSnapshotNeverDropsRequests() {
        let snapshot = NetworkConditionSnapshot(
            isEnabled: false, latency: 0, downloadBytesPerSecond: nil, packetLossRate: 1
        )
        XCTAssertFalse(snapshot.shouldDropRequest())
    }

    func testFullPacketLossAlwaysDrops() {
        let snapshot = NetworkConditionSnapshot(
            isEnabled: true, latency: 0, downloadBytesPerSecond: nil, packetLossRate: 1
        )
        for _ in 0..<20 {
            XCTAssertTrue(snapshot.shouldDropRequest())
        }
    }

    func testZeroPacketLossNeverDrops() {
        let snapshot = NetworkConditionSnapshot(
            isEnabled: true, latency: 0, downloadBytesPerSecond: nil, packetLossRate: 0
        )
        for _ in 0..<20 {
            XCTAssertFalse(snapshot.shouldDropRequest())
        }
    }

    // MARK: - Дробление тела ответа

    func testNoBandwidthLimitDeliversSingleChunk() {
        let snapshot = NetworkConditionSnapshot(
            isEnabled: true, latency: 0, downloadBytesPerSecond: nil, packetLossRate: 0
        )
        let data = Data(repeating: 0, count: 5_000)
        let chunks = snapshot.downloadChunks(for: data)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].delay, 0)
        XCTAssertEqual(chunks[0].chunk.count, 5_000)
    }

    func testChunksReassembleToOriginalData() {
        let snapshot = NetworkConditionSnapshot(
            isEnabled: true, latency: 0, downloadBytesPerSecond: 10_000, packetLossRate: 0
        )
        let data = Data((0..<50_000).map { UInt8($0 % 251) })
        let chunks = snapshot.downloadChunks(for: data)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.reduce(Data()) { $0 + $1.chunk }, data)
    }

    func testTotalDelayApproximatesTransferTime() {
        let bytesPerSecond = 10_000
        let snapshot = NetworkConditionSnapshot(
            isEnabled: true, latency: 0, downloadBytesPerSecond: bytesPerSecond, packetLossRate: 0
        )
        let data = Data(repeating: 0, count: 50_000)

        let totalDelay = snapshot.downloadChunks(for: data).reduce(0) { $0 + $1.delay }
        // 50 000 байт при 10 000 байт/с — примерно пять секунд
        XCTAssertEqual(totalDelay, 5.0, accuracy: 0.001)
    }

    func testSmallBodyIsDeliveredAsOneDelayedChunk() {
        let snapshot = NetworkConditionSnapshot(
            isEnabled: true, latency: 0, downloadBytesPerSecond: 10_000, packetLossRate: 0
        )
        let data = Data(repeating: 0, count: 100)
        let chunks = snapshot.downloadChunks(for: data)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].delay, 0.01, accuracy: 0.0001)
    }

    func testEmptyBodyProducesNoWork() {
        let snapshot = NetworkConditionSnapshot(
            isEnabled: true, latency: 0, downloadBytesPerSecond: 10_000, packetLossRate: 0
        )
        let chunks = snapshot.downloadChunks(for: Data())

        XCTAssertEqual(chunks.count, 1)
        XCTAssertTrue(chunks[0].chunk.isEmpty)
    }
}

@MainActor
final class NetworkConditionerTests: XCTestCase {

    private var conditioner: NetworkConditioner { NetworkConditioner.shared }
    private var savedProfile: NetworkConditionProfile = .none
    private var savedEnabled = false

    override func setUp() async throws {
        try await super.setUp()
        savedProfile = conditioner.activeProfile
        savedEnabled = conditioner.isEnabled
        conditioner.apply(.none)
        conditioner.disable()
    }

    override func tearDown() async throws {
        for profile in conditioner.customProfiles {
            conditioner.removeProfile(id: profile.id)
        }
        conditioner.activeProfile = savedProfile
        conditioner.isEnabled = savedEnabled
        try await super.tearDown()
    }

    func testApplyingProfileEnablesSimulation() {
        conditioner.apply(.threeG)

        XCTAssertTrue(conditioner.isEnabled)
        XCTAssertEqual(conditioner.activeProfile, .threeG)
    }

    func testApplyingTransparentProfileLeavesSimulationOff() {
        conditioner.apply(.none)
        XCTAssertFalse(conditioner.isEnabled)
    }

    func testDisableTurnsSimulationOff() {
        conditioner.apply(.edge)
        conditioner.disable()

        XCTAssertFalse(conditioner.isEnabled)
    }

    func testSnapshotTracksActiveProfile() {
        conditioner.apply(.threeG)

        let snapshot = NetworkConditionState.current
        XCTAssertTrue(snapshot.isEnabled)
        XCTAssertEqual(snapshot.latency, NetworkConditionProfile.threeG.latency)
        XCTAssertEqual(snapshot.downloadBytesPerSecond, NetworkConditionProfile.threeG.downloadBytesPerSecond)
    }

    func testSnapshotIsClearedWhenDisabled() {
        conditioner.apply(.threeG)
        conditioner.disable()

        XCTAssertFalse(NetworkConditionState.current.isEnabled)
    }

    func testAllProfilesIncludesBuiltInAndCustom() {
        let custom = NetworkConditionProfile(name: "Тестовый", latency: 1)
        conditioner.addProfile(custom)

        XCTAssertEqual(conditioner.allProfiles.count, NetworkConditionProfile.builtIn.count + 1)
    }

    func testAddedProfileIsNeverMarkedBuiltIn() {
        conditioner.addProfile(NetworkConditionProfile(name: "Подделка", isBuiltIn: true))
        XCTAssertEqual(conditioner.customProfiles.first?.isBuiltIn, false)
    }

    func testUpdateProfileChangesStoredCopy() {
        var custom = NetworkConditionProfile(name: "Тестовый", latency: 1)
        conditioner.addProfile(custom)
        custom.name = "Обновлённый"
        conditioner.updateProfile(custom)

        XCTAssertEqual(conditioner.customProfiles.first?.name, "Обновлённый")
    }

    func testRemovingActiveProfileResetsToNone() {
        let custom = NetworkConditionProfile(name: "Тестовый", latency: 1)
        conditioner.addProfile(custom)
        conditioner.apply(custom)
        conditioner.removeProfile(id: custom.id)

        XCTAssertEqual(conditioner.activeProfile, .none)
        XCTAssertFalse(conditioner.isEnabled)
    }
}
