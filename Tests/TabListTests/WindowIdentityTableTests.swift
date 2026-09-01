import CoreGraphics
import TabListCore
import Testing
@testable import TabList

private final class Token: Equatable {
    let name: String

    init(_ name: String) {
        self.name = name
    }

    static func == (lhs: Token, rhs: Token) -> Bool {
        lhs === rhs
    }
}

private func makeTable() -> WindowIdentityTable<Token> {
    WindowIdentityTable(isSameToken: { $0 === $1 })
}

@Suite
struct WindowIdentityTableTests {
    @Test
    func testWindowServerIdentifierIsPreferredAndRemembered() {
        var table = makeTable()
        let token = Token("window")

        let identity = table.identifier(for: token, windowServerID: 4_211)

        XCTAssertEqual(identity.id, 4_211)
        XCTAssertEqual(identity.source, .windowServerID)
        XCTAssertEqual(table.assignedCount, 1)
    }

    @Test
    func testOrdinalSurvivesWindowServerMappingBecomingAvailable() {
        var table = makeTable()
        let token = Token("window")
        let original = table.identifier(for: token, windowServerID: nil)

        let refreshed = table.identifier(for: token, windowServerID: 4_211)

        XCTAssertEqual(refreshed.id, original.id)
        XCTAssertEqual(refreshed.source, .accessibilityOrdinal)
    }

    @Test
    func testWindowServerIdentifierSurvivesATransientMappingFailure() {
        var table = makeTable()
        let token = Token("window")
        let original = table.identifier(for: token, windowServerID: 4_211)

        let refreshed = table.identifier(for: token, windowServerID: nil)

        XCTAssertEqual(refreshed.id, original.id)
        XCTAssertEqual(refreshed.source, .windowServerID)
    }

    @Test
    func testZeroWindowServerIdentifierFallsBackToAnOrdinal() {
        var table = makeTable()

        let identity = table.identifier(for: Token("window"), windowServerID: 0)

        XCTAssertEqual(identity.source, .accessibilityOrdinal)
        XCTAssertGreaterThanOrEqual(
            identity.id,
            WindowIdentityTable<Token>.ordinalBase
        )
    }

    @Test
    func testOrdinalsAreStableForTheSameTokenAcrossRefreshes() {
        var table = makeTable()
        let first = Token("a")
        let second = Token("b")

        let firstIdentity = table.identifier(for: first, windowServerID: nil)
        let secondIdentity = table.identifier(for: second, windowServerID: nil)

        table.retainOnly([first, second])

        XCTAssertEqual(
            table.identifier(for: first, windowServerID: nil).id,
            firstIdentity.id
        )
        XCTAssertEqual(
            table.identifier(for: second, windowServerID: nil).id,
            secondIdentity.id
        )
        XCTAssertNotEqual(firstIdentity.id, secondIdentity.id)
    }

    @Test
    func testOrdinalsNeverCollideWithRealWindowServerIdentifiers() {
        var table = makeTable()
        let tokens = (0 ..< 50).map { Token("window-\($0)") }

        let identifiers = tokens.map {
            table.identifier(for: $0, windowServerID: nil).id
        }

        XCTAssertEqual(Set(identifiers).count, tokens.count)
        XCTAssertTrue(
            identifiers.allSatisfy {
                $0 >= WindowIdentityTable<Token>.ordinalBase
            }
        )
    }

    @Test
    func testRetainOnlyDropsTokensThatNoLongerExist() {
        var table = makeTable()
        let surviving = Token("surviving")
        let closed = Token("closed")
        _ = table.identifier(for: surviving, windowServerID: nil)
        _ = table.identifier(for: closed, windowServerID: nil)

        table.retainOnly([surviving])

        XCTAssertEqual(table.assignedCount, 1)
    }

    @Test
    func testAReturningTokenNeverInheritsAClosedWindowIdentifier() {
        var table = makeTable()
        let closed = Token("closed")
        let closedIdentifier = table.identifier(
            for: closed,
            windowServerID: nil
        ).id

        table.retainOnly([])
        let replacement = Token("replacement")

        XCTAssertNotEqual(
            table.identifier(for: replacement, windowServerID: nil).id,
            closedIdentifier
        )
    }

    @Test
    func testMixedIdentitySourcesShareOneProcessWithoutCollision() {
        var table = makeTable()
        let mapped = Token("mapped")
        let unmapped = Token("unmapped")

        let mappedIdentity = table.identifier(
            for: mapped,
            windowServerID: 12
        )
        let unmappedIdentity = table.identifier(
            for: unmapped,
            windowServerID: nil
        )

        XCTAssertNotEqual(mappedIdentity.id, unmappedIdentity.id)
        XCTAssertEqual(mappedIdentity.source, .windowServerID)
        XCTAssertEqual(unmappedIdentity.source, .accessibilityOrdinal)
    }
}
