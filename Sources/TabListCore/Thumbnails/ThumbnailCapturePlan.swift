public struct ThumbnailCapturePlan: Equatable, Sendable {
    public let immediate: [WindowKey]
    public let visible: [WindowKey]
    public let remaining: [WindowKey]

    public init(
        allKeys: [WindowKey],
        priorityKeys: [WindowKey],
        visibleKeys: [WindowKey]
    ) {
        let knownKeys = Set(allKeys)
        var assigned: Set<WindowKey> = []

        func takeKnownUnique(_ keys: [WindowKey]) -> [WindowKey] {
            keys.filter { key in
                knownKeys.contains(key) && assigned.insert(key).inserted
            }
        }

        immediate = takeKnownUnique(priorityKeys)
        visible = takeKnownUnique(visibleKeys)
        remaining = takeKnownUnique(allKeys)
    }

    public var isEmpty: Bool {
        immediate.isEmpty && visible.isEmpty && remaining.isEmpty
    }
}
