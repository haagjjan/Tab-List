import Foundation
import Testing
@testable import TabListCore

@Suite
struct WindowModelsTests {
    @Test
    func testWindowKeyRoundTripsThroughCodable() throws {
        let key = TestFixtures.key(42, pid: 7)

        let data = try JSONEncoder().encode(key)
        let decoded = try JSONDecoder().decode(WindowKey.self, from: data)

        XCTAssertEqual(decoded, key)
    }

    @Test
    func testSnapshotFindsWindowByProcessScopedKey() {
        let first = TestFixtures.window(1, pid: 10)
        let second = TestFixtures.window(1, pid: 20)
        let snapshot = WindowSnapshot(
            generation: 5,
            windows: [first, second],
            visibleSpaceIDs: [1]
        )

        XCTAssertEqual(snapshot.window(for: second.id), second)
        XCTAssertNil(snapshot.window(for: TestFixtures.key(999)))
    }

    @Test
    func testIdenticalWindowIDsFromDifferentProcessesRemainDistinct() {
        let first = TestFixtures.key(1, pid: 10)
        let second = TestFixtures.key(1, pid: 11)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 2)
    }

    @Test
    func testWindowIncarnationDistinguishesRecycledPreviewIdentity() {
        var original = TestFixtures.window(1, pid: 10)
        var recycled = original
        original.incarnation = 4
        recycled.incarnation = 5

        XCTAssertNotEqual(original, recycled)
        XCTAssertEqual(original.id, recycled.id)
    }
}
