import Foundation
import Network

public final class KeyLightDiscovery: KeyLightDiscovering, @unchecked Sendable {
    public var onLightsChanged: (([KeyLightEndpoint]) -> Void)?

    private let queue = DispatchQueue(label: "AutoEnableElgatoLight.discovery")
    private var nwBrowser: NWBrowser?
    private var netServiceBrowser: BonjourBrowser?
    private var endpoints: [String: KeyLightEndpoint] = [:]
    private var resolvers: [String: ServiceResolver] = [:]
    private var scanTask: Task<Void, Never>?
    private let scanner = LocalNetworkScanner()
    private var nwServiceIDs: Set<String> = []
    private var netServiceIDs: Set<String> = []
    private let serviceType = "_elg._tcp"
    private let netServiceType = "_elg._tcp."
    private let serviceDomain = "local."

    public init() {}

    public func start() {
        queue.async { [weak self] in
            self?.startLocked()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.stopLocked(clearEndpoints: true)
        }
    }

    public func rescan() {
        queue.async { [weak self] in
            self?.stopLocked(clearEndpoints: true)
            self?.publishLocked()
            self?.startLocked()
        }
    }

    private func startLocked() {
        guard nwBrowser == nil && netServiceBrowser == nil else { return }

        startNWBrowserLocked()
        startNetServiceBrowserLocked()
        startScanLocked()
    }

    private func startNWBrowserLocked() {
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let discovery = self else { return }
            discovery.queue.async { [discovery] in
                discovery.updateNW(results: Array(results))
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
        self.nwBrowser = browser
        browser.start(queue: queue)
    }

    private func startNetServiceBrowserLocked() {
        let browser = BonjourBrowser(type: netServiceType, domain: serviceDomain) { [weak self] event in
            guard let discovery = self else { return }
            discovery.queue.async { [discovery] in
                discovery.handleBonjour(event: event)
            }
        }
        netServiceBrowser = browser
        browser.start()
    }

    private func updateNW(results: [NWBrowser.Result]) {
        nwServiceIDs = Set(results.compactMap(\.serviceID))
        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else { continue }
            let id = serviceID(name: name, type: type, domain: domain)
            let displayName = displayName(for: name)

            if endpoints[id] == nil && resolvers[id] == nil {
                resolve(id: id, name: displayName, type: type, domain: domain)
            }
        }

        pruneInactiveServicesLocked()
        publishLocked()
    }

    private func handleBonjour(event: BonjourBrowser.Event) {
        switch event {
        case let .found(name, type, domain):
            let id = serviceID(name: name, type: type, domain: domain)
            netServiceIDs.insert(id)
            if endpoints[id] == nil && resolvers[id] == nil {
                resolve(id: id, name: displayName(for: name), type: type, domain: domain)
            }
        case let .removed(name, type, domain):
            netServiceIDs.remove(serviceID(name: name, type: type, domain: domain))
            pruneInactiveServicesLocked()
        case .stopped:
            netServiceIDs.removeAll()
            pruneInactiveServicesLocked()
        }
        publishLocked()
    }

    private func resolve(id: String, name: String, type: String, domain: String) {
        let resolver = ServiceResolver(name: name, type: normalizedServiceType(type), domain: normalizedDomain(domain)) { [weak self] endpoint in
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

    private func stopLocked(clearEndpoints: Bool) {
        nwBrowser?.cancel()
        nwBrowser = nil
        netServiceBrowser?.stop()
        netServiceBrowser = nil
        scanTask?.cancel()
        scanTask = nil
        resolvers.values.forEach { $0.stop() }
        resolvers.removeAll()
        nwServiceIDs.removeAll()
        netServiceIDs.removeAll()

        if clearEndpoints {
            endpoints.removeAll()
        }
    }

    private func startScanLocked() {
        scanTask?.cancel()
        scanTask = Task { [weak self, scanner] in
            let scannedLights = await scanner.scan()
            guard !Task.isCancelled, let discovery = self else { return }
            discovery.queue.async { [discovery] in
                for light in scannedLights {
                    discovery.endpoints[light.id] = light
                }
                discovery.publishLocked()
            }
        }
    }

    private func pruneInactiveServicesLocked() {
        let activeIDs = nwServiceIDs.union(netServiceIDs)
        endpoints = endpoints.filter { $0.key.hasPrefix("scan:") || activeIDs.contains($0.key) }
        resolvers = resolvers.filter { activeIDs.contains($0.key) }
    }

    private func serviceID(name: String, type: String, domain: String) -> String {
        "\(name).\(normalizedServiceType(type)).\(normalizedDomain(domain))"
    }

    private func displayName(for serviceName: String) -> String {
        serviceName.isEmpty ? "Elgato Key Light" : serviceName
    }

    private func normalizedServiceType(_ type: String) -> String {
        type.hasSuffix(".") ? type : "\(type)."
    }

    private func normalizedDomain(_ domain: String) -> String {
        if domain.isEmpty { return serviceDomain }
        return domain.hasSuffix(".") ? domain : "\(domain)."
    }
}

private extension NWBrowser.Result {
    var serviceID: String? {
        guard case let .service(name, type, domain, _) = endpoint else { return nil }
        let normalizedType = type.hasSuffix(".") ? type : "\(type)."
        let normalizedDomain = domain.isEmpty ? "local." : (domain.hasSuffix(".") ? domain : "\(domain).")
        return "\(name).\(normalizedType).\(normalizedDomain)"
    }
}

private final class BonjourBrowser: NSObject, NetServiceBrowserDelegate {
    enum Event {
        case found(name: String, type: String, domain: String)
        case removed(name: String, type: String, domain: String)
        case stopped
    }

    private let browser = NetServiceBrowser()
    private let type: String
    private let domain: String
    private let eventHandler: (Event) -> Void

    init(type: String, domain: String, eventHandler: @escaping (Event) -> Void) {
        self.type = type
        self.domain = domain
        self.eventHandler = eventHandler
        super.init()
        browser.delegate = self
    }

    func start() {
        RunLoop.main.perform { [browser, type, domain] in
            browser.schedule(in: .main, forMode: .default)
            browser.searchForServices(ofType: type, inDomain: domain)
        }
    }

    func stop() {
        RunLoop.main.perform { [browser] in
            browser.stop()
            browser.remove(from: .main, forMode: .default)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        eventHandler(.found(name: service.name, type: service.type, domain: service.domain))
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        eventHandler(.removed(name: service.name, type: service.type, domain: service.domain))
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        eventHandler(.stopped)
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
        RunLoop.main.perform { [service] in
            service.schedule(in: .main, forMode: .default)
            service.resolve(withTimeout: 5)
        }
    }

    func stop() {
        RunLoop.main.perform { [service] in
            service.stop()
            service.remove(from: .main, forMode: .default)
        }
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
        stop()
        completion(endpoint)
    }
}
