import CoreGraphics
import Foundation
import TabListCore

/// Assigns a stable, process-scoped identifier to each window of one process.
///
/// A window keeps the identifier it was first given for as long as its token —
/// in production an `AXUIElement` — stays alive. That is what lets selection,
/// MRU order, and a pending close survive a refresh. Identity is generic over
/// the token so the assignment rules can be tested without Accessibility.
struct WindowIdentityTable<Token> {
    /// Ordinals live above every realistic WindowServer identifier so the two
    /// identity sources can never collide inside one process.
    static var ordinalBase: CGWindowID { 0x8000_0000 }

    private let isSameToken: (Token, Token) -> Bool
    private var assigned: [(
        token: Token,
        id: CGWindowID,
        source: WindowIdentitySource
    )] = []
    private var nextOrdinal: CGWindowID = Self.ordinalBase

    init(isSameToken: @escaping (Token, Token) -> Bool) {
        self.isSameToken = isSameToken
    }

    var assignedCount: Int {
        assigned.count
    }

    mutating func identifier(
        for token: Token,
        windowServerID: CGWindowID?
    ) -> (id: CGWindowID, source: WindowIdentitySource) {
        if let existing = assigned.first(where: { isSameToken($0.token, token) }) {
            return (existing.id, existing.source)
        }
        if let windowServerID, windowServerID != 0 {
            assigned.append((token, windowServerID, .windowServerID))
            return (windowServerID, .windowServerID)
        }
        let identifier = nextOrdinal
        nextOrdinal &+= 1
        assigned.append((token, identifier, .accessibilityOrdinal))
        return (identifier, .accessibilityOrdinal)
    }

    mutating func retainOnly(_ tokens: [Token]) {
        assigned.removeAll { entry in
            !tokens.contains { isSameToken($0, entry.token) }
        }
    }
}
