# Auto Enable Elgato Light

A lightweight macOS menu bar app that automatically turns Elgato Key Lights on when the camera is active and turns them off when the camera stops.

This is built for personal use: no Dock icon, low idle overhead, local-network-only light control, and a small menu bar presence for status and troubleshooting.

## Features

- Detects camera activity with CoreMediaIO property listeners.
- Controls Elgato Key Lights through the local HTTP API on port `9123`.
- Discovers lights with Bonjour/mDNS when available.
- Falls back to a one-shot local HTTP scan when Bonjour discovery is unreliable.
- Supports manual light IP entry as a backup.
- Preserves brightness and color temperature across on/off toggles.
- Includes a Launch at Login menu item.
- Builds without an Xcode project using Swift Package Manager.
- Can package a test DMG.

## Requirements

- macOS 13 or newer.
- Swift toolchain / Xcode Command Line Tools.
- An Elgato Key Light, Ring Light, Light Strip, or compatible Elgato light on the same local network.

## Build

From the repository root:

```bash
make build
```

Run tests:

```bash
make test
```

Build the app bundle:

```bash
make app
```

The app bundle is created at:

```text
.build/Auto Enable Elgato Light.app
```

Run it:

```bash
open ".build/Auto Enable Elgato Light.app"
```

## Package a DMG

```bash
make dmg
```

The DMG is created at:

```text
.build/artifacts/AutoEnableElgatoLight.dmg
```

The DMG includes the app and an Applications symlink for drag-install testing.

## First Launch

The app appears as a lightbulb in the macOS menu bar. It has no Dock icon.

Menu items include:

- Camera status
- Camera device count
- Light status
- Set Light IP...
- Clear Manual Lights
- Rescan Lights
- Launch at Login
- Quit

For a clean autodiscovery test:

1. Quit any running copy of the app.
2. Launch the freshly built app.
3. Choose `Clear Manual Lights`.
4. Choose `Rescan Lights`.
5. Wait a few seconds for Bonjour and local HTTP scan discovery.

## Testing on Other Macs

For personal testing, share the generated DMG.

On the other Mac:

1. Open the DMG.
2. Drag the app to `/Applications`.
3. Right-click the app and choose `Open` the first time.

This app is not currently signed or notarized, so macOS may show Gatekeeper warnings. If needed for local testing:

```bash
xattr -dr com.apple.quarantine "/Applications/Auto Enable Elgato Light.app"
```

Launch at Login generally works best when the app is installed in `/Applications`.

## Diagnostics

The package includes a diagnostics executable.

Watch camera state:

```bash
swift run AutoEnableElgatoLightDiagnostics watch
```

Try Bonjour plus discovery events:

```bash
swift run AutoEnableElgatoLightDiagnostics discover
```

Run the local HTTP scan:

```bash
swift run AutoEnableElgatoLightDiagnostics scan
```

Test a known light IP directly:

```bash
swift run AutoEnableElgatoLightDiagnostics test-light 192.168.1.123
```

## How It Works

The app combines three event sources:

- `CameraActivityMonitor` observes CoreMediaIO camera device state.
- `KeyLightDiscovery` discovers lights with `NWBrowser`, `NetServiceBrowser`, and a one-shot HTTP scan.
- `LightAutomationController` combines camera state and discovered lights, then sends local HTTP requests to each light.

Light state is read from:

```text
GET http://<light-ip>:9123/elgato/lights
```

Light state is changed with:

```text
PUT http://<light-ip>:9123/elgato/lights
```

## Notes

- Discovery and control are local-network-only.
- The fallback scanner is one-shot on launch/rescan; it is not a constant background poller.
- Bonjour may be unreliable on some networks, especially with mDNS filtering, VLANs, VPNs, or router isolation.
- Manual IP entry remains available as a last-resort fallback.
- This is an unofficial project and is not affiliated with or endorsed by Elgato.

## License

MIT. See [LICENSE](LICENSE).

## Project Layout

```text
Sources/AutoEnableElgatoLightApp/          Menu bar app
Sources/AutoEnableElgatoLightCore/         Camera, discovery, HTTP, automation logic
Sources/AutoEnableElgatoLightDiagnostics/  CLI diagnostics
Tests/AutoEnableElgatoLightCoreTests/      Unit tests
scripts/build-app.sh                       App bundle builder
scripts/build-dmg.sh                       DMG builder
```
