# Q

Q is a local-first macOS menu-bar application for a three-LED USB-C status device. The current build contains the native application shell, core models, device protocol, a fully interactive virtual device, and the semantic preset foundation for AI Agents, Availability, Meetings, Pomodoro, Builds, and Custom modes.

## Run the Phase 1 app

Requirements: macOS 14 or later and Swift 6.0 or later.

```sh
swift run Q
```

Q appears in the menu bar, intentionally has no Dock icon, and opens Virtual Q on first launch. Its menu can hide or show the device. The preview scene buttons exercise independent LED state and animation. The virtual physical button recognizes single press, double press, and a hold of at least 0.65 seconds.

To create a launchable development app bundle after building:

```sh
sh Scripts/package-app.sh
open .build/Q.app
```

## Verify

```sh
swift build
swift test
```

The Swift package can also be opened directly in Xcode when the full Xcode application is installed.

## Architecture

- `QCore` contains transport-safe `Codable` semantic state and the device layer, independently importable by future app and CLI targets.
- `QModeCatalog` defines the six launch modes, their semantic states, scenes, priorities, and safe default button mappings.
- `QCustomRule` models trigger/condition/scene/action rules for the Phase 2 Custom builder without coupling rules to LED rendering.
- `Device/QDevice.swift` is the hardware-independent boundary used by the rest of the app.
- `Device/VirtualQDevice.swift` implements that boundary and emits button input through `AsyncStream`.
- `UI/VirtualQ` renders LED effects in SwiftUI and forwards physical-style button gestures to the device.
- `App` and `UI/MenuBar` provide the accessory-style menu-bar application shell.

The future serial implementation can conform to `QDevice` without changing integrations, state resolution, or UI consumers.
