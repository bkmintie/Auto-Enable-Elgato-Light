import Foundation

public final class SettingsStore: @unchecked Sendable {
    private enum Keys {
        static let lastKnownSettings = "lastKnownSettings"
        static let lastKnownEndpoints = "lastKnownEndpoints"
        static let manualEndpoints = "manualEndpoints"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func settings(for endpoint: KeyLightEndpoint) -> KeyLightSettings? {
        lock.withLock {
            settingsMap()[endpoint.id]
        }
    }

    public func save(settings: KeyLightSettings, for endpoint: KeyLightEndpoint) {
        lock.withLock {
            var map = settingsMap()
            map[endpoint.id] = settings
            saveSettingsMap(map)
        }
    }

    public func endpoints() -> [KeyLightEndpoint] {
        lock.withLock {
            guard let data = defaults.data(forKey: Keys.lastKnownEndpoints) else { return [] }
            return (try? decoder.decode([KeyLightEndpoint].self, from: data)) ?? []
        }
    }

    public func save(endpoints: [KeyLightEndpoint]) {
        lock.withLock {
            guard let data = try? encoder.encode(endpoints) else { return }
            defaults.set(data, forKey: Keys.lastKnownEndpoints)
        }
    }

    public func manualEndpoints() -> [KeyLightEndpoint] {
        lock.withLock {
            guard let data = defaults.data(forKey: Keys.manualEndpoints) else { return [] }
            return (try? decoder.decode([KeyLightEndpoint].self, from: data)) ?? []
        }
    }

    public func save(manualEndpoints: [KeyLightEndpoint]) {
        lock.withLock {
            guard let data = try? encoder.encode(manualEndpoints) else { return }
            defaults.set(data, forKey: Keys.manualEndpoints)
        }
    }

    private func settingsMap() -> [String: KeyLightSettings] {
        guard let data = defaults.data(forKey: Keys.lastKnownSettings) else { return [:] }
        return (try? decoder.decode([String: KeyLightSettings].self, from: data)) ?? [:]
    }

    private func saveSettingsMap(_ map: [String: KeyLightSettings]) {
        guard let data = try? encoder.encode(map) else { return }
        defaults.set(data, forKey: Keys.lastKnownSettings)
    }
}
