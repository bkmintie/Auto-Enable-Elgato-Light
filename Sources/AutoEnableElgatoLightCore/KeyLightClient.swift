import Foundation

public final class KeyLightClient: KeyLightControlling {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func getState(for endpoint: KeyLightEndpoint) async throws -> KeyLightState {
        var request = URLRequest(url: lightsURL(for: endpoint))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validate(response)
        let payload = try decoder.decode(LightsResponse.self, from: data)
        return payload.lights.first?.state ?? KeyLightState(on: false, brightness: KeyLightSettings.fallback.brightness, temperature: KeyLightSettings.fallback.temperature)
    }

    public func setPower(_ on: Bool, for endpoint: KeyLightEndpoint, preserving settings: KeyLightSettings?) async throws {
        let settings = settings ?? KeyLightSettings.fallback
        try await setState(
            KeyLightState(on: on, brightness: settings.brightness, temperature: settings.temperature),
            for: endpoint
        )
    }

    public func setState(_ state: KeyLightState, for endpoint: KeyLightEndpoint) async throws {
        var request = URLRequest(url: lightsURL(for: endpoint))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(LightsResponse(lights: [LightPayload(state: state)]))

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    private func lightsURL(for endpoint: KeyLightEndpoint) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = "/elgato/lights"
        return components.url!
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
