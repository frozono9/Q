# Q

Q connects automatically to local Codex/ChatGPT agent sessions. It watches the
live local rollout event stream, maps agent activity to Q's semantic states, and
opens the exact Codex thread through its native `codex://threads/<id>` deep link.
No separate API key or cloud relay is required.

Meeting mode currently integrates with the local Discord desktop client. Q reads
Discord's primary RTC connection log to detect calls, ignores screen-share RTC
connections, and can invoke Discord's native mute shortcut after macOS grants Q
Accessibility control. Meeting states remain read-only in Q.

Q is a local-first macOS menu-bar application for a three-LED USB-C status device. The focused MVP exposes four primary modes: AI Agents, Availability, Meetings, and Pomodoro. Custom state/rule architecture remains available for the advanced editor without becoming another everyday mode.

## Install Q

Requirements: macOS 14 or later and Swift 6.0 or later.

Build and install the real application bundle:

```sh
swift build
sh Scripts/install-app.sh
```

Q is installed at `/Applications/Q.app`, appears in Spotlight and Finder with its
own icon, and keeps its Q control in the macOS menu bar without adding a Dock
icon. The installed app registers itself to reopen automatically at login.
Opening Q again from Spotlight or Finder reveals its popover when it is already
running.

For development without installing, use `swift run Q`. To create only a local
launchable bundle, run `sh Scripts/package-app.sh` and open `.build/Q.app`.

The menu can hide or show the virtual device. The MVP uses one contextual button
press; the current action is always shown in the popover.

General Settings configures the physical button's single, double, and long press
independently. Factory defaults use the contextual action for single press,
cycle to the next primary mode for double press, and leave long press unassigned.
Every press shows a compact five-second mode and state confirmation beside the
menu-bar Q. Settings are persisted locally.

The supplied Q artwork is used consistently for the app icon, menu-bar item, and in-app identity. To regenerate the derived icon assets after replacing `Resources/Brand/qgadget.png`, install ImageMagick and run `sh Scripts/generate-brand-assets.sh`.

## Verify

```sh
swift build
swift test
```

The Swift package can also be opened directly in Xcode when the full Xcode application is installed.

## Architecture

- `QCore` contains transport-safe `Codable` semantic state and the device layer, independently importable by future app and CLI targets.
- `QModeCatalog` defines the four primary MVP modes, their semantic states, scenes, priorities, and safe default button mappings.
- `QAgentSlotResolver` assigns the three most relevant agent sessions to physical LED slots using semantic priority and recency.
- `QPomodoroConfiguration` provides configurable local focus/break timing and the standard duration presets.
- `QCustomRule` models trigger/condition/scene/action rules for the Phase 2 Custom builder without coupling rules to LED rendering.
- `Device/QDevice.swift` is the hardware-independent boundary used by the rest of the app.
- `Device/VirtualQDevice.swift` implements that boundary and emits button input through `AsyncStream`.
- `UI/VirtualQ` renders LED effects in SwiftUI and forwards physical-style button gestures to the device.
- `App` and `UI/MenuBar` provide the accessory-style menu-bar application shell.

The future serial implementation can conform to `QDevice` without changing integrations, state resolution, or UI consumers.

## Factory visual grammar

- Green means clear, ready, or successful.
- Yellow means active, transitional, or away.
- Blue means engaged, attention, or focus.
- Red means blocked, error, or do not disturb.
- Purple means deliberate timed focus.
- Opal means physically off.

Solid light is stable, chase is ongoing, slow fade requests awareness, blink signals a problem, and flash marks a new event. These are app-level factory presets—not firmware behavior—so later persistence can make every scene and mapping user-editable.
