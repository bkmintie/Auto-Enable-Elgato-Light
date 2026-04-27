import Foundation
import Testing
@testable import AutoEnableElgatoLightCore

@Test func lightsPayloadDecodesAndEncodes() throws {
    let json = #"{"lights":[{"on":1,"brightness":42,"temperature":170}],"numberOfLights":1}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(LightsResponse.self, from: json)

    #expect(decoded.numberOfLights == 1)
    #expect(decoded.lights.first?.state == KeyLightState(on: true, brightness: 42, temperature: 170))

    let encoded = try JSONEncoder().encode(LightsResponse(lights: [LightPayload(state: KeyLightState(on: false, brightness: 12, temperature: 155))]))
    let roundTrip = try JSONDecoder().decode(LightsResponse.self, from: encoded)

    #expect(roundTrip.lights.first?.on == 0)
    #expect(roundTrip.lights.first?.brightness == 12)
    #expect(roundTrip.lights.first?.temperature == 155)
}

@Test func cameraActiveTurnsAllLightsOn() async throws {
    let camera = MockCameraMonitor()
    let discovery = MockDiscovery()
    let client = MockLightClient()
    let controller = LightAutomationController(cameraMonitor: camera, discovery: discovery, client: client, settingsStore: testStore())

    controller.start()
    discovery.emit([.one, .two])
    camera.emit(true)
    try await waitFor { await client.powerCalls().count == 2 }

    let calls = await client.powerCalls()
    #expect(calls.map(\.on) == [true, true])
    #expect(Set(calls.map(\.endpoint)) == [.one, .two])
}

@Test func cameraInactiveStoresSettingsAndTurnsLightsOff() async throws {
    let camera = MockCameraMonitor()
    let discovery = MockDiscovery()
    let client = MockLightClient()
    let store = testStore()
    await client.setMockState(KeyLightState(on: true, brightness: 55, temperature: 190), for: .one)
    let controller = LightAutomationController(cameraMonitor: camera, discovery: discovery, client: client, settingsStore: store)

    controller.start()
    discovery.emit([.one])
    camera.emit(false)
    try await waitFor { await client.powerCalls().count == 1 }

    let calls = await client.powerCalls()
    #expect(store.settings(for: .one) == KeyLightSettings(brightness: 55, temperature: 190))
    #expect(calls.first?.on == false)
    #expect(calls.first?.settings == KeyLightSettings(brightness: 55, temperature: 190))
}

@Test func oneFailedLightDoesNotBlockOthers() async throws {
    let camera = MockCameraMonitor()
    let discovery = MockDiscovery()
    let client = MockLightClient()
    await client.fail(endpoint: .two)
    let controller = LightAutomationController(cameraMonitor: camera, discovery: discovery, client: client, settingsStore: testStore())
    let status = StatusRecorder()
    controller.onStatusChanged = { status.record($0) }

    controller.start()
    discovery.emit([.one, .two])
    camera.emit(true)
    try await waitFor { await client.powerCalls().count == 1 }

    let calls = await client.powerCalls()
    #expect(calls.first?.endpoint == .one)
    try await waitFor {
        if case .degraded = status.last { return true }
        return false
    }
}

@Test func noDiscoveredLightsReportsDegradedState() async throws {
    let camera = MockCameraMonitor()
    let discovery = MockDiscovery()
    let controller = LightAutomationController(cameraMonitor: camera, discovery: discovery, client: MockLightClient(), settingsStore: testStore())
    let status = StatusRecorder()
    controller.onStatusChanged = { status.record($0) }

    controller.start()
    discovery.emit([])
    camera.emit(true)

    try await waitFor {
        if case let .degraded(_, lightCount) = status.last {
            return lightCount == 0
        }
        return false
    }
}

@Test func scannerDiscoversLightFromAccessoryInfo() async throws {
    MockURLProtocol.reset()
    MockURLProtocol.register(
        url: "http://192.0.2.10:9123/elgato/accessory-info",
        statusCode: 200,
        body: #"{"productName":"Elgato Key Light MK.2","displayName":"Desk Light","features":["lights"]}"#
    )

    let scanner = makeScanner(hosts: ["192.0.2.10"])
    let lights = await scanner.scan()

    #expect(lights == [
        KeyLightEndpoint(id: "scan:192.0.2.10:9123", name: "Desk Light", host: "192.0.2.10")
    ])
}

@Test func scannerFallsBackToLightsEndpoint() async throws {
    MockURLProtocol.reset()
    MockURLProtocol.register(
        url: "http://192.0.2.11:9123/elgato/accessory-info",
        statusCode: 404,
        body: #"{}"#
    )
    MockURLProtocol.register(
        url: "http://192.0.2.11:9123/elgato/lights",
        statusCode: 200,
        body: #"{"lights":[{"on":0,"brightness":40,"temperature":156}],"numberOfLights":1}"#
    )

    let scanner = makeScanner(hosts: ["192.0.2.11"])
    let lights = await scanner.scan()

    #expect(lights == [
        KeyLightEndpoint(id: "scan:192.0.2.11:9123", name: "Elgato Key Light", host: "192.0.2.11")
    ])
}

@Test func scannerIgnoresNonLightDevices() async throws {
    MockURLProtocol.reset()
    MockURLProtocol.register(
        url: "http://192.0.2.12:9123/elgato/accessory-info",
        statusCode: 200,
        body: #"{"productName":"Elgato Stream Deck","features":["buttons"]}"#
    )
    MockURLProtocol.register(
        url: "http://192.0.2.12:9123/elgato/lights",
        statusCode: 404,
        body: #"{}"#
    )

    let scanner = makeScanner(hosts: ["192.0.2.12"])
    let lights = await scanner.scan()

    #expect(lights.isEmpty)
}

private func testStore() -> SettingsStore {
    let suite = UserDefaults(suiteName: "AutoEnableElgatoLightTests.\(UUID().uuidString)")!
    return SettingsStore(defaults: suite)
}

private func makeScanner(hosts: [String]) -> LocalNetworkScanner {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return LocalNetworkScanner(session: session, maxConcurrentProbes: 4, candidateHostProvider: { hosts })
}

private struct Timeout: Error {}

private func waitFor(_ condition: @escaping () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    throw Timeout()
}

private extension KeyLightEndpoint {
    static let one = KeyLightEndpoint(id: "one", name: "One", host: "192.0.2.1")
    static let two = KeyLightEndpoint(id: "two", name: "Two", host: "192.0.2.2")
}

private final class MockCameraMonitor: CameraActivityMonitoring, @unchecked Sendable {
    var onActivityChanged: ((Bool) -> Void)?
    var onDevicesChanged: (([CameraDeviceSnapshot]) -> Void)?
    func start() {}
    func stop() {}
    func emit(_ active: Bool) { onActivityChanged?(active) }
}

private final class MockDiscovery: KeyLightDiscovering, @unchecked Sendable {
    var onLightsChanged: (([KeyLightEndpoint]) -> Void)?
    func start() {}
    func stop() {}
    func rescan() {}
    func emit(_ lights: [KeyLightEndpoint]) { onLightsChanged?(lights) }
}

private actor MockLightClient: KeyLightControlling {
    struct PowerCall: Equatable {
        var endpoint: KeyLightEndpoint
        var on: Bool
        var settings: KeyLightSettings?
    }

    private var states: [KeyLightEndpoint: KeyLightState] = [:]
    private var failures: Set<KeyLightEndpoint> = []
    private var calls: [PowerCall] = []

    func setMockState(_ state: KeyLightState, for endpoint: KeyLightEndpoint) {
        states[endpoint] = state
    }

    func fail(endpoint: KeyLightEndpoint) {
        failures.insert(endpoint)
    }

    func powerCalls() -> [PowerCall] {
        calls
    }

    func getState(for endpoint: KeyLightEndpoint) async throws -> KeyLightState {
        if failures.contains(endpoint) { throw URLError(.cannotConnectToHost) }
        return states[endpoint] ?? KeyLightState(on: true, brightness: 40, temperature: 162)
    }

    func setPower(_ on: Bool, for endpoint: KeyLightEndpoint, preserving settings: KeyLightSettings?) async throws {
        if failures.contains(endpoint) { throw URLError(.cannotConnectToHost) }
        calls.append(PowerCall(endpoint: endpoint, on: on, settings: settings))
    }

    func setState(_ state: KeyLightState, for endpoint: KeyLightEndpoint) async throws {
        if failures.contains(endpoint) { throw URLError(.cannotConnectToHost) }
        states[endpoint] = state
    }
}

private final class StatusRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [AutomationStatus] = []

    var last: AutomationStatus? {
        lock.withLock { statuses.last }
    }

    func record(_ status: AutomationStatus) {
        lock.withLock { statuses.append(status) }
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private struct MockResponse: Sendable {
        var statusCode: Int
        var data: Data
    }

    private final class ResponseStore: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [String: MockResponse] = [:]

        func reset() {
            lock.withLock {
                responses.removeAll()
            }
        }

        func register(url: String, statusCode: Int, body: String) {
            lock.withLock {
                responses[url] = MockResponse(statusCode: statusCode, data: Data(body.utf8))
            }
        }

        func response(for url: String) -> MockResponse? {
            lock.withLock {
                responses[url]
            }
        }
    }

    private static let store = ResponseStore()

    static func reset() {
        store.reset()
    }

    static func register(url: String, statusCode: Int, body: String) {
        store.register(url: url, statusCode: statusCode, body: body)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = Self.store.response(for: url.absoluteString)

        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }

        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
