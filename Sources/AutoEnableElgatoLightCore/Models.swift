import Foundation

public struct KeyLightEndpoint: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var host: String
    public var port: Int

    public init(id: String, name: String, host: String, port: Int = 9123) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
    }
}

public struct KeyLightSettings: Codable, Equatable, Sendable {
    public var brightness: Int
    public var temperature: Int

    public init(brightness: Int, temperature: Int) {
        self.brightness = brightness
        self.temperature = temperature
    }

    public static let fallback = KeyLightSettings(brightness: 40, temperature: 162)
}

public struct KeyLightState: Codable, Equatable, Sendable {
    public var on: Bool
    public var brightness: Int
    public var temperature: Int

    public init(on: Bool, brightness: Int, temperature: Int) {
        self.on = on
        self.brightness = brightness
        self.temperature = temperature
    }

    public var settings: KeyLightSettings {
        KeyLightSettings(brightness: brightness, temperature: temperature)
    }
}

public struct CameraDeviceSnapshot: Equatable, Sendable {
    public var id: UInt32
    public var name: String
    public var model: String
    public var isRunning: Bool

    public init(id: UInt32, name: String, model: String, isRunning: Bool) {
        self.id = id
        self.name = name
        self.model = model
        self.isRunning = isRunning
    }
}

public enum AutomationStatus: Equatable, Sendable {
    case idle
    case discovering
    case cameraActive(lightCount: Int)
    case cameraInactive(lightCount: Int)
    case degraded(message: String, lightCount: Int)
}

public struct LightsResponse: Codable, Equatable, Sendable {
    public var lights: [LightPayload]
    public var numberOfLights: Int

    public init(lights: [LightPayload], numberOfLights: Int? = nil) {
        self.lights = lights
        self.numberOfLights = numberOfLights ?? lights.count
    }
}

public struct LightPayload: Codable, Equatable, Sendable {
    public var on: Int
    public var brightness: Int
    public var temperature: Int

    public init(on: Int, brightness: Int, temperature: Int) {
        self.on = on
        self.brightness = brightness
        self.temperature = temperature
    }

    public init(state: KeyLightState) {
        self.on = state.on ? 1 : 0
        self.brightness = state.brightness
        self.temperature = state.temperature
    }

    public var state: KeyLightState {
        KeyLightState(on: on != 0, brightness: brightness, temperature: temperature)
    }
}
