import CoreMediaIO
import Foundation

public final class CameraActivityMonitor: CameraActivityMonitoring, @unchecked Sendable {
    public var onActivityChanged: ((Bool) -> Void)?
    public var onDevicesChanged: (([CameraDeviceSnapshot]) -> Void)?

    private let queue = DispatchQueue(label: "AutoEnableElgatoLight.camera")
    private var devices: [CMIOObjectID] = []
    private var listeners: [(CMIOObjectID, CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)] = []
    private var hardwareListener: (CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)?
    private var lastState: Bool?

    public init() {}

    public func start() {
        queue.async { [weak self] in
            self?.installHardwareListener()
            self?.installListeners()
            self?.publishDeviceSnapshots()
            self?.publishCurrentState(force: true)
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    private func installListeners() {
        stopDeviceListenersLocked()
        devices = discoverCameraDevices()

        for device in devices {
            var address = runningAddress()
            let listener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let monitor = self else { return }
                monitor.queue.asyncAfter(deadline: .now() + 0.2) { [monitor] in
                    monitor.publishDeviceSnapshots()
                    monitor.publishCurrentState()
                }
            }
            let status = CMIOObjectAddPropertyListenerBlock(device, &address, queue, listener)
            if status == noErr {
                listeners.append((device, address, listener))
            }
        }
    }

    private func installHardwareListener() {
        guard hardwareListener == nil else { return }
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let listener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let monitor = self else { return }
            monitor.queue.asyncAfter(deadline: .now() + 0.5) { [monitor] in
                monitor.installListeners()
                monitor.publishDeviceSnapshots()
                monitor.publishCurrentState(force: true)
            }
        }
        let status = CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, queue, listener)
        if status == noErr {
            hardwareListener = (address, listener)
        }
    }

    private func publishCurrentState(force: Bool = false) {
        let active = devices.contains { isRunning(device: $0) }
        guard force || active != lastState else { return }
        lastState = active
        onActivityChanged?(active)
    }

    private func publishDeviceSnapshots() {
        onDevicesChanged?(devices.map(snapshot(for:)))
    }

    private func discoverCameraDevices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var ids = Array(repeating: CMIOObjectID(), count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, dataSize, &dataUsed, &ids) == noErr else {
            return []
        }

        return ids.filter(isInputDevice)
    }

    private func isInputDevice(_ device: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
            mScope: CMIOObjectPropertyScope(kCMIODevicePropertyScopeInput),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        return CMIOObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize) == noErr && dataSize > 0
    }

    private func isLikelyBuiltInCamera(_ device: CMIOObjectID) -> Bool {
        let name = stringProperty(kCMIOObjectPropertyName, for: device).lowercased()
        let model = stringProperty(kCMIODevicePropertyModelUID, for: device).lowercased()
        let haystack = "\(name) \(model)"
        return haystack.contains("facetime")
            || haystack.contains("isight")
            || haystack.contains("built-in")
            || haystack.contains("built in")
            || haystack.contains("continuity camera")
    }

    private func snapshot(for device: CMIOObjectID) -> CameraDeviceSnapshot {
        CameraDeviceSnapshot(
            id: UInt32(device),
            name: stringProperty(kCMIOObjectPropertyName, for: device),
            model: stringProperty(kCMIODevicePropertyModelUID, for: device),
            isRunning: isRunning(device: device)
        )
    }

    private func stringProperty(_ selector: Int, for device: CMIOObjectID) -> String {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var value: CFString = "" as CFString
        var dataUsed: UInt32 = 0
        let size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            CMIOObjectGetPropertyData(device, &address, 0, nil, size, &dataUsed, pointer)
        }
        return status == noErr ? value as String : ""
    }

    private func isRunning(device: CMIOObjectID) -> Bool {
        var address = runningAddress()
        var value: UInt32 = 0
        var dataUsed: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &dataUsed,
            &value
        )
        return status == noErr && value != 0
    }

    private func runningAddress() -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
    }

    private func stopLocked() {
        stopDeviceListenersLocked()
        if let (address, listener) = hardwareListener {
            var mutableAddress = address
            CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &mutableAddress, queue, listener)
            hardwareListener = nil
        }
        lastState = nil
    }

    private func stopDeviceListenersLocked() {
        for (device, address, listener) in listeners {
            var mutableAddress = address
            CMIOObjectRemovePropertyListenerBlock(device, &mutableAddress, queue, listener)
        }
        listeners.removeAll()
        devices.removeAll()
    }
}
