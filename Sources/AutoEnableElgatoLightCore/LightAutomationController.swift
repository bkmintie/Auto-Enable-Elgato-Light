import Foundation

public final class LightAutomationController: @unchecked Sendable {
    public var onStatusChanged: ((AutomationStatus) -> Void)?

    private let cameraMonitor: CameraActivityMonitoring
    private let discovery: KeyLightDiscovering
    private let client: KeyLightControlling
    private let settingsStore: SettingsStore
    private let queue = DispatchQueue(label: "AutoEnableElgatoLight.controller")
    private var lights: [KeyLightEndpoint]
    private var discoveredLights: [KeyLightEndpoint] = []
    private var manualLights: [KeyLightEndpoint]
    private var cameraDevices: [CameraDeviceSnapshot] = []
    private var cameraActive = false
    private var debounceTask: Task<Void, Never>?
    private var started = false

    public init(
        cameraMonitor: CameraActivityMonitoring,
        discovery: KeyLightDiscovering,
        client: KeyLightControlling,
        settingsStore: SettingsStore = SettingsStore()
    ) {
        self.cameraMonitor = cameraMonitor
        self.discovery = discovery
        self.client = client
        self.settingsStore = settingsStore
        self.manualLights = settingsStore.manualEndpoints()
        self.lights = Self.mergedLights(discovered: settingsStore.endpoints(), manual: manualLights)
    }

    public convenience init(settingsStore: SettingsStore = SettingsStore()) {
        self.init(
            cameraMonitor: CameraActivityMonitor(),
            discovery: KeyLightDiscovery(),
            client: KeyLightClient(),
            settingsStore: settingsStore
        )
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, !started else { return }
            started = true
            publish(.discovering)

            cameraMonitor.onActivityChanged = { [weak self] active in
                guard let controller = self else { return }
                controller.queue.async { [controller] in
                    controller.cameraActive = active
                    controller.scheduleApply()
                }
            }

            cameraMonitor.onDevicesChanged = { [weak self] devices in
                guard let controller = self else { return }
                controller.queue.async { [controller] in
                    controller.cameraDevices = devices
                    controller.publish(controller.statusForCurrentState())
                }
            }

            discovery.onLightsChanged = { [weak self] lights in
                guard let controller = self else { return }
                controller.queue.async { [controller] in
                    controller.discoveredLights = lights.isEmpty ? controller.settingsStore.endpoints() : lights
                    if !lights.isEmpty {
                        controller.settingsStore.save(endpoints: lights)
                    }
                    controller.lights = Self.mergedLights(discovered: controller.discoveredLights, manual: controller.manualLights)
                    controller.publish(controller.statusForCurrentState())
                    controller.scheduleApply()
                }
            }

            cameraMonitor.start()
            discovery.start()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            started = false
            debounceTask?.cancel()
            cameraMonitor.stop()
            discovery.stop()
            publish(.idle)
        }
    }

    public func rescanLights() {
        publish(.discovering)
        discovery.rescan()
    }

    public func addManualLight(host: String, port: Int = 9123) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return }

        queue.async { [weak self] in
            guard let self else { return }
            let endpoint = KeyLightEndpoint(
                id: "manual:\(trimmedHost):\(port)",
                name: "Manual Key Light",
                host: trimmedHost,
                port: port
            )
            manualLights.removeAll { $0.id == endpoint.id || ($0.host == endpoint.host && $0.port == endpoint.port) }
            manualLights.append(endpoint)
            settingsStore.save(manualEndpoints: manualLights)
            lights = Self.mergedLights(discovered: discoveredLights, manual: manualLights)
            publish(statusForCurrentState())
            scheduleApply()
        }
    }

    public func clearManualLights() {
        queue.async { [weak self] in
            guard let self else { return }
            manualLights.removeAll()
            settingsStore.save(manualEndpoints: [])
            lights = Self.mergedLights(discovered: discoveredLights, manual: manualLights)
            publish(statusForCurrentState())
        }
    }

    public func currentStatus() -> AutomationStatus {
        queue.sync {
            statusForCurrentState()
        }
    }

    public func currentCameraDevices() -> [CameraDeviceSnapshot] {
        queue.sync {
            cameraDevices
        }
    }

    private func scheduleApply() {
        debounceTask?.cancel()
        let active = cameraActive
        let targets = lights
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            await self?.apply(cameraActive: active, to: targets)
        }
    }

    private func apply(cameraActive active: Bool, to targets: [KeyLightEndpoint]) async {
        guard !targets.isEmpty else {
            publish(.degraded(message: "No lights discovered", lightCount: 0))
            return
        }

        var failures: [String] = []

        await withTaskGroup(of: String?.self) { group in
            for endpoint in targets {
                group.addTask { [client, settingsStore] in
                    do {
                        if active {
                            let stored = settingsStore.settings(for: endpoint) ?? KeyLightSettings.fallback
                            try await client.setPower(true, for: endpoint, preserving: stored)
                        } else {
                            if let state = try? await client.getState(for: endpoint) {
                                settingsStore.save(settings: state.settings, for: endpoint)
                            }
                            let stored = settingsStore.settings(for: endpoint) ?? KeyLightSettings.fallback
                            try await client.setPower(false, for: endpoint, preserving: stored)
                        }
                        return nil
                    } catch {
                        return "\(endpoint.name): \(error.localizedDescription)"
                    }
                }
            }

            for await failure in group {
                if let failure {
                    failures.append(failure)
                }
            }
        }

        if failures.isEmpty {
            publish(active ? .cameraActive(lightCount: targets.count) : .cameraInactive(lightCount: targets.count))
        } else {
            publish(.degraded(message: failures.joined(separator: ", "), lightCount: targets.count))
        }
    }

    private func statusForCurrentState() -> AutomationStatus {
        if lights.isEmpty {
            return .degraded(message: "No lights discovered", lightCount: 0)
        }
        return cameraActive ? .cameraActive(lightCount: lights.count) : .cameraInactive(lightCount: lights.count)
    }

    private func publish(_ status: AutomationStatus) {
        onStatusChanged?(status)
    }

    private static func mergedLights(discovered: [KeyLightEndpoint], manual: [KeyLightEndpoint]) -> [KeyLightEndpoint] {
        var merged: [String: KeyLightEndpoint] = [:]
        for light in discovered + manual {
            merged["\(light.host):\(light.port)"] = light
        }
        return merged.values.sorted { $0.name < $1.name }
    }
}
