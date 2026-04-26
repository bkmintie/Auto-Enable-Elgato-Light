import Foundation
import Network

public final class KeyLightDiscovery: KeyLightDiscovering, @unchecked Sendable {
    public var onLightsChanged: (([KeyLightEndpoint]) -> Void)?

    private let queue = DispatchQueue(label: "AutoEnableElgatoLight.discovery")
    private var browser: NWBrowser?
    private var endpoints: [String: KeyLightEndpoint] = [:]
    private var resolvers: [String: ServiceResolver] = [:]
    private let serviceType = "_elg._tcp"

    public init() {}

    public func start() {
        queue.async { [weak self] in
            self?.startLocked()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.browser?.cancel()
            self?.browser = nil
            self?.endpoints.removeAll()
            self?.resolvers.removeAll()
        }
    }

    public func rescan() {
        queue.async { [weak self] in
            self?.browser?.cancel()
            self?.browser = nil
            self?.endpoints.removeAll()
            self?.resolvers.removeAll()
            self?.publishLocked()
            self?.startLocked()
        }
    }

    private func startLocked() {
        guard browser == nil else { return }

        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: "local."), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let discovery = self else { return }
            discovery.queue.async { [discovery] in
                discovery.update(results: Array(results))
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                guard let discovery = self else { return }
                discovery.queue.asyncAfter(deadline: .now() + 5) { [discovery] in
                    discovery.rescan()
                }
            }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    private func update(results: [NWBrowser.Result]) {
        var next: [String: KeyLightEndpoint] = [:]

        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else { continue }
            let id = "\(name).\(type).\(domain)"
            let displayName = name.isEmpty ? "Elgato Key Light" : name

            if let existing = endpoints[id] {
                next[id] = existing
            } else if resolvers[id] == nil {
                resolve(id: id, name: displayName, type: type, domain: domain)
            }
        }

        let activeIDs = Set(results.compactMap(\.serviceID))
        endpoints = endpoints.filter { activeIDs.contains($0.key) }
        resolvers = resolvers.filter { activeIDs.contains($0.key) }
        publishLocked()
    }

    private func resolve(id: String, name: String, type: String, domain: String) {
        let resolver = ServiceResolver(name: name, type: type, domain: domain) { [weak self] endpoint in
            guard let discovery = self else { return }
            discovery.queue.async { [discovery] in
                discovery.resolvers[id] = nil
                guard let endpoint else { return }
                discovery.endpoints[id] = KeyLightEndpoint(
                    id: id,
                    name: endpoint.name,
                    host: endpoint.host,
                    port: endpoint.port
                )
                discovery.publishLocked()
            }
        }
        resolvers[id] = resolver
        resolver.start()
    }

    private func publishLocked() {
        let lights = endpoints.values.sorted { $0.name < $1.name }
        onLightsChanged?(lights)
    }
}

private extension NWBrowser.Result {
    var serviceID: String? {
        guard case let .service(name, type, domain, _) = endpoint else { return nil }
        return "\(name).\(type).\(domain)"
    }
}

private final class ServiceResolver: NSObject, NetServiceDelegate {
    struct ResolvedEndpoint {
        var name: String
        var host: String
        var port: Int
    }

    private let service: NetService
    private let completion: (ResolvedEndpoint?) -> Void
    private var completed = false

    init(name: String, type: String, domain: String, completion: @escaping (ResolvedEndpoint?) -> Void) {
        self.service = NetService(domain: domain, type: type, name: name)
        self.completion = completion
        super.init()
        self.service.delegate = self
    }

    func start() {
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        finish(
            ResolvedEndpoint(
                name: sender.name,
                host: sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? sender.name,
                port: sender.port > 0 ? sender.port : 9123
            )
        )
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        finish(nil)
    }

    private func finish(_ endpoint: ResolvedEndpoint?) {
        guard !completed else { return }
        completed = true
        service.stop()
        completion(endpoint)
    }
}
