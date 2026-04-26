import Foundation

public protocol CameraActivityMonitoring: AnyObject, Sendable {
    var onActivityChanged: ((Bool) -> Void)? { get set }
    var onDevicesChanged: (([CameraDeviceSnapshot]) -> Void)? { get set }
    func start()
    func stop()
}

public protocol KeyLightDiscovering: AnyObject, Sendable {
    var onLightsChanged: (([KeyLightEndpoint]) -> Void)? { get set }
    func start()
    func stop()
    func rescan()
}

public protocol KeyLightControlling: Sendable {
    func getState(for endpoint: KeyLightEndpoint) async throws -> KeyLightState
    func setPower(_ on: Bool, for endpoint: KeyLightEndpoint, preserving settings: KeyLightSettings?) async throws
    func setState(_ state: KeyLightState, for endpoint: KeyLightEndpoint) async throws
}
