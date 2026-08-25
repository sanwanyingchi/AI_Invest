import Foundation

/// Persists only user-entered positions. Broker snapshots remain owned by the sync layer.
/// This store is retained only to migrate data created before SQLite was introduced.
final class ManualHoldingStore {
    private let defaults: UserDefaults
    private let storageKey = "manual-holdings-v2"
    private let migrationKey = "manual-holdings-migrated-to-sqlite-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadForMigration() -> [Holding]? {
        guard !defaults.bool(forKey: migrationKey) else { return nil }
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode([Holding].self, from: data)
    }

    func markMigrationCompleted() {
        defaults.set(true, forKey: migrationKey)
    }
}
