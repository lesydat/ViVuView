import Foundation

/// Least-recently-used cache bounded by total cost in bytes. Not thread-safe; wrap it in a lock when shared.
public struct ByteLRU<Key: Hashable, Value> {
    private struct Entry {
        var value: Value
        var cost: Int
        var tick: UInt64
    }

    public private(set) var budget: Int
    public private(set) var totalCost = 0
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0

    public init(budget: Int) { self.budget = budget }

    public var count: Int { entries.count }

    public mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        clock += 1
        entry.tick = clock
        entries[key] = entry
        return entry.value
    }

    /// Looks without counting as a use.
    public func peek(_ key: Key) -> Value? { entries[key]?.value }

    public func contains(_ key: Key) -> Bool { entries[key] != nil }

    /// Inserts and evicts the least recently used entries until the cost fits. Returns what was evicted.
    @discardableResult
    public mutating func insert(_ value: Value, for key: Key, cost: Int) -> [Key] {
        if let old = entries[key] { totalCost -= old.cost }
        clock += 1
        entries[key] = Entry(value: value, cost: cost, tick: clock)
        totalCost += cost
        return trim(keeping: key)
    }

    @discardableResult
    public mutating func remove(_ key: Key) -> Value? {
        guard let entry = entries.removeValue(forKey: key) else { return nil }
        totalCost -= entry.cost
        return entry.value
    }

    public mutating func removeAll() {
        entries.removeAll()
        totalCost = 0
    }

    /// Changes the budget (settings, memory pressure) and evicts as needed.
    @discardableResult
    public mutating func setBudget(_ newBudget: Int) -> [Key] {
        budget = newBudget
        return trim(keeping: nil)
    }

    private mutating func trim(keeping protected: Key?) -> [Key] {
        guard totalCost > budget else { return [] }
        var evicted: [Key] = []
        let order = entries.sorted { $0.value.tick < $1.value.tick }
        for (key, entry) in order where totalCost > budget {
            if key == protected { continue }
            entries[key] = nil
            totalCost -= entry.cost
            evicted.append(key)
        }
        return evicted
    }
}
