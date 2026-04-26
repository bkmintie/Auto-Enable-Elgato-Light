import AutoEnableElgatoLightCore
import Foundation

@main
struct Diagnostics {
    static func main() async {
        let command = CommandLine.arguments.dropFirst().first ?? "watch"

        switch command {
        case "camera":
            await runCamera(seconds: 2)
        case "discover":
            await runDiscovery(seconds: 8)
        case "scan":
            await runScan()
        case "test-light":
            await testLight()
        case "watch":
            await runCamera(seconds: 20)
        default:
            print("Usage: AutoEnableElgatoLightDiagnostics [camera|discover|scan|watch|test-light <ip>]")
        }
    }

    private static func runCamera(seconds: UInt64) async {
        let monitor = CameraActivityMonitor()
        monitor.onDevicesChanged = { devices in
            print("Camera devices: \(devices.count)")
            for device in devices {
                let name = device.name.isEmpty ? "(unnamed)" : device.name
                let model = device.model.isEmpty ? "(no model)" : device.model
                print("- id=\(device.id) running=\(device.isRunning) name=\(name) model=\(model)")
            }
        }
        monitor.onActivityChanged = { active in
            print("Camera active: \(active)")
        }
        monitor.start()
        try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
        monitor.stop()
    }

    private static func runDiscovery(seconds: UInt64) async {
        let discovery = KeyLightDiscovery()
        discovery.onLightsChanged = { lights in
            print("Lights: \(lights.count)")
            for light in lights {
                print("- \(light.name) \(light.host):\(light.port) id=\(light.id)")
            }
        }
        discovery.start()
        try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
        discovery.stop()
    }

    private static func runScan() async {
        let lights = await LocalNetworkScanner().scan()
        print("Scanned lights: \(lights.count)")
        for light in lights {
            print("- \(light.name) \(light.host):\(light.port) id=\(light.id)")
        }
    }

    private static func testLight() async {
        guard CommandLine.arguments.count >= 3 else {
            print("Usage: AutoEnableElgatoLightDiagnostics test-light <ip>")
            return
        }
        let host = CommandLine.arguments[2]
        let endpoint = KeyLightEndpoint(id: "manual:\(host):9123", name: "Manual Key Light", host: host)
        let client = KeyLightClient()

        do {
            let state = try await client.getState(for: endpoint)
            print("Current state: on=\(state.on) brightness=\(state.brightness) temperature=\(state.temperature)")
            try await client.setPower(true, for: endpoint, preserving: state.settings)
            print("Turned on \(host)")
        } catch {
            print("Light test failed: \(error.localizedDescription)")
        }
    }
}
