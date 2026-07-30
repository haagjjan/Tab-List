/// Deterministic, value-only LRU accounting for caches whose payload objects
/// must stay inside a framework-owning actor.
public struct BoundedCostLRU<Key: Hashable & Sendable>: Sendable {
    public struct Insertion: Equatable, Sendable {
        public let accepted: Bool
        public let evicted: [Key]

        public init(accepted: Bool, evicted: [Key]) {
            self.accepted = accepted
            self.evicted = evicted
        }
    }

    private struct Entry: Sendable {
        let cost: Int
        var lastAccess: UInt64
    }

    public let totalCostLimit: Int
    public let countLimit: Int
    public private(set) var totalCost = 0

    private var entries: [Key: Entry] = [:]
    private var accessSequence: UInt64 = 0

    public init(totalCostLimit: Int, countLimit: Int) {
        self.totalCostLimit = max(1, totalCostLimit)
        self.countLimit = max(1, countLimit)
    }

    public var count: Int {
        entries.count
    }

    public func contains(_ key: Key) -> Bool {
        entries[key] != nil
    }

    @discardableResult
    public mutating func touch(_ key: Key) -> Bool {
        guard var entry = entries[key] else { return false }
        advanceSequence()
        entry.lastAccess = accessSequence
        entries[key] = entry
        return true
    }

    public mutating func insert(_ key: Key, cost: Int) -> Insertion {
        guard cost > 0, cost <= totalCostLimit else {
            return Insertion(accepted: false, evicted: [])
        }

        if let previous = entries.removeValue(forKey: key) {
            totalCost -= previous.cost
        }

        var evicted: [Key] = []
        while !entries.isEmpty,
              entries.count >= countLimit
                || totalCost + cost > totalCostLimit {
            guard let oldest = entries.min(
                by: { $0.value.lastAccess < $1.value.lastAccess }
            ), let removed = entries.removeValue(forKey: oldest.key) else {
                break
            }
            totalCost -= removed.cost
            evicted.append(oldest.key)
        }

        advanceSequence()
        entries[key] = Entry(cost: cost, lastAccess: accessSequence)
        totalCost += cost
        return Insertion(accepted: true, evicted: evicted)
    }

    public mutating func removeAll() {
        entries.removeAll(keepingCapacity: false)
        totalCost = 0
        accessSequence = 0
    }

    private mutating func advanceSequence() {
        if accessSequence == .max {
            let ordered = entries.sorted {
                $0.value.lastAccess < $1.value.lastAccess
            }
            for (index, pair) in ordered.enumerated() {
                entries[pair.key]?.lastAccess = UInt64(index + 1)
            }
            accessSequence = UInt64(ordered.count)
        }
        accessSequence &+= 1
    }
}
