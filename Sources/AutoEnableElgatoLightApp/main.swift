import AppKit
import AutoEnableElgatoLightCore
import ServiceManagement

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let controller = LightAutomationController()
    private let menu = NSMenu()
    private let cameraItem = NSMenuItem(title: "Camera: Unknown", action: nil, keyEquivalent: "")
    private let cameraDevicesItem = NSMenuItem(title: "Camera Devices: Unknown", action: nil, keyEquivalent: "")
    private let lightsItem = NSMenuItem(title: "Lights: Discovering", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private var currentStatus: AutomationStatus = .discovering

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureMenu()

        controller.onStatusChanged = { [weak self] status in
            DispatchQueue.main.async {
                self?.currentStatus = status
                self?.render(status)
            }
        }
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: "Auto Enable Elgato Light")
        statusItem.button?.imagePosition = .imageOnly
        statusItem.menu = menu
    }

    private func configureMenu() {
        cameraItem.isEnabled = false
        cameraDevicesItem.isEnabled = false
        lightsItem.isEnabled = false
        launchAtLoginItem.target = self

        menu.addItem(cameraItem)
        menu.addItem(cameraDevicesItem)
        menu.addItem(lightsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Set Light IP...", action: #selector(setLightIP), keyEquivalent: "i").targeting(self))
        menu.addItem(NSMenuItem(title: "Clear Manual Lights", action: #selector(clearManualLights), keyEquivalent: "").targeting(self))
        menu.addItem(NSMenuItem(title: "Rescan Lights", action: #selector(rescanLights), keyEquivalent: "r").targeting(self))
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q").targeting(self))

        renderLaunchAtLogin()
    }

    private func render(_ status: AutomationStatus) {
        switch status {
        case .idle:
            cameraItem.title = "Camera: Idle"
            lightsItem.title = "Lights: Not running"
            statusItem.button?.image = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: nil)
        case .discovering:
            cameraItem.title = "Camera: Watching"
            lightsItem.title = "Lights: Discovering"
            statusItem.button?.image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: nil)
        case let .cameraActive(lightCount):
            cameraItem.title = "Camera: Active"
            lightsItem.title = "Lights: \(lightCount) on"
            statusItem.button?.image = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: nil)
        case let .cameraInactive(lightCount):
            cameraItem.title = "Camera: Inactive"
            lightsItem.title = "Lights: \(lightCount) off"
            statusItem.button?.image = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: nil)
        case let .degraded(message, lightCount):
            cameraItem.title = "Camera: \(currentStatusCameraLabel)"
            lightsItem.title = lightCount == 0 ? "Lights: Offline" : "Lights: \(lightCount), issue"
            lightsItem.toolTip = message
            statusItem.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        }
        renderCameraDevices()
    }

    private func renderCameraDevices() {
        let devices = controller.currentCameraDevices()
        let runningCount = devices.filter(\.isRunning).count
        cameraDevicesItem.title = "Camera Devices: \(runningCount)/\(devices.count) active"
        cameraDevicesItem.toolTip = devices.map { device in
            let name = device.name.isEmpty ? "Unnamed camera" : device.name
            return "\(name) running=\(device.isRunning)"
        }.joined(separator: "\n")
    }

    private var currentStatusCameraLabel: String {
        switch currentStatus {
        case .cameraActive:
            return "Active"
        default:
            return "Watching"
        }
    }

    @objc private func rescanLights() {
        controller.rescanLights()
    }

    @objc private func setLightIP() {
        let alert = NSAlert()
        alert.messageText = "Set Elgato Key Light IP"
        alert.informativeText = "Enter the IP address shown in Elgato Control Center."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "192.168.1.123"
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            controller.addManualLight(host: input.stringValue)
        }
    }

    @objc private func clearManualLights() {
        controller.clearManualLights()
        controller.rescanLights()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at Login Error"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        renderLaunchAtLogin()
    }

    private func renderLaunchAtLogin() {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

private extension NSMenuItem {
    func targeting(_ target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}
