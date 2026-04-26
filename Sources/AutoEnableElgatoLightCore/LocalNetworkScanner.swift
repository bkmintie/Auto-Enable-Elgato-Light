import Foundation

public final class LocalNetworkScanner: @unchecked Sendable {
    private struct AccessoryInfo: Decodable {
        var productName: String?
        var displayName: String?
        var features: [String]?
    }

    private let client: URLSession
    private let decoder = JSONDecoder()
    private let timeout: TimeInterval
    private let maxConcurrentProbes: Int

    public init(timeout: TimeInterval = 0.45, maxConcurrentProbes: Int = 32) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        self.client = URLSession(configuration: configuration)
        self.timeout = timeout
        self.maxConcurrentProbes = maxConcurrentProbes
    }

    public func scan() async -> [KeyLightEndpoint] {
        let hosts = candidateHosts()
        guard !hosts.isEmpty else { return [] }

        return await withTaskGroup(of: KeyLightEndpoint?.self) { group in
            var iterator = hosts.makeIterator()
            var active = 0
            var found: [KeyLightEndpoint] = []

            func enqueueNext() {
                guard let host = iterator.next() else { return }
                active += 1
                group.addTask { [weak self] in
                    await self?.probe(host: host)
                }
            }

            for _ in 0..<min(maxConcurrentProbes, hosts.count) {
                enqueueNext()
            }

            while active > 0 {
                if let endpoint = await group.next() {
                    if let endpoint {
                        found.append(endpoint)
                    }
                    active -= 1
                    enqueueNext()
                } else {
                    active = 0
                }
            }

            return found.sorted { $0.host < $1.host }
        }
    }

    private func probe(host: String) async -> KeyLightEndpoint? {
        if let endpoint = await probeAccessoryInfo(host: host) {
            return endpoint
        }
        if await probeLights(host: host) {
            return KeyLightEndpoint(id: "scan:\(host):9123", name: "Elgato Key Light", host: host)
        }
        return nil
    }

    private func probeAccessoryInfo(host: String) async -> KeyLightEndpoint? {
        guard let url = URL(string: "http://\(host):9123/elgato/accessory-info") else { return nil }

        do {
            let (data, response) = try await client.data(from: url)
            guard isOK(response) else { return nil }
            let info = try decoder.decode(AccessoryInfo.self, from: data)
            guard isLightingAccessory(info) else { return nil }

            let name = info.displayName?.isEmpty == false
                ? info.displayName!
                : (info.productName?.isEmpty == false ? info.productName! : "Elgato Key Light")
            return KeyLightEndpoint(id: "scan:\(host):9123", name: name, host: host)
        } catch {
            return nil
        }
    }

    private func probeLights(host: String) async -> Bool {
        guard let url = URL(string: "http://\(host):9123/elgato/lights") else { return false }

        do {
            let (data, response) = try await client.data(from: url)
            guard isOK(response) else { return false }
            _ = try decoder.decode(LightsResponse.self, from: data)
            return true
        } catch {
            return false
        }
    }

    private func isOK(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    private func isLightingAccessory(_ info: AccessoryInfo) -> Bool {
        if info.features?.contains(where: { $0.lowercased() == "lights" }) == true {
            return true
        }

        let product = (info.productName ?? "").lowercased()
        return product.contains("key light")
            || product.contains("ring light")
            || product.contains("light strip")
            || product.contains("elgato")
    }

    private func candidateHosts() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return [] }
        defer { freeifaddrs(interfaces) }

        var hosts = Set<String>()
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard let address = ipv4(interface.ifa_addr), let netmask = ipv4(interface.ifa_netmask) else { continue }

            for host in hostsNear(address: address, netmask: netmask) {
                hosts.insert(host)
            }
        }

        return hosts.sorted()
    }

    private func hostsNear(address: UInt32, netmask: UInt32) -> [String] {
        let network = address & netmask
        let broadcast = network | ~netmask
        let totalHosts = broadcast > network ? broadcast - network - 1 : 0

        guard totalHosts > 0 else { return [] }

        if totalHosts <= 254 {
            return ((network + 1)..<broadcast)
                .filter { $0 != address }
                .map(ipv4String)
        }

        let prefix24 = address & 0xFF_FF_FF_00
        return ((prefix24 + 1)..<(prefix24 + 255))
            .filter { $0 != address }
            .map(ipv4String)
    }

    private func ipv4(_ socketAddress: UnsafePointer<sockaddr>?) -> UInt32? {
        guard let socketAddress else { return nil }
        let address = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            $0.pointee.sin_addr.s_addr
        }
        return UInt32(bigEndian: address)
    }

    private func ipv4String(_ address: UInt32) -> String {
        [
            (address >> 24) & 0xFF,
            (address >> 16) & 0xFF,
            (address >> 8) & 0xFF,
            address & 0xFF
        ]
        .map(String.init)
        .joined(separator: ".")
    }
}
