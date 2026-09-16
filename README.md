# Q

Current private-beta release: **Q 0.2.2**, paired with **firmware 0.2.2**.

For the complete product, hardware, architecture, protocol, contributor, and
extension guide, see [`PROJECT_GUIDE.md`](PROJECT_GUIDE.md).

Q connects automatically to local Codex agent sessions. It watches the
live local rollout event stream, maps agent activity to Q's semantic states, and
opens the exact Codex thread through its native `codex://threads/<id>` deep link.
No separate API key or cloud relay is required.

Meeting mode integrates with Discord, Zoom, Google Meet, and Microsoft Teams.
Discord uses its local RTC log; Zoom, Meet, and Teams are recognized from their
accessible call controls, so merely opening an app does not create a false call.
The provider can follow the active call automatically or be pinned to Discord,
Zoom, Google Meet, or Teams. A contextual long press is push-to-talk: Q unmutes
the chosen provider while held and mutes it again on release.

The mode selected by the user exclusively owns the LEDs and button. Integrations
continue observing their own state in the background, but a meeting never
replaces AI Agents (or any other selected mode). Each physical module can also
be given a persistent name keyed to its stable hardware identifier.

Q is a local-first macOS menu-bar application for a three-LED USB-C status device. The focused MVP ships with five factory modes: AI Agents, Availability, Meetings, Pomodoro, and Relaxing. Users can also create any number of Custom modes; they appear only after creation and can be included in or excluded from the button's mode cycle individually.

## First run and support

The menu-bar app opens a first-run setup check that verifies the physical Q,
firmware compatibility, Accessibility permission, Codex, optional Discord, the
three LEDs, and the physical button. Settings can reopen this check at any time.

“Copy diagnostic report” copies only app, macOS, hardware, permission, and
integration status. It deliberately excludes prompts, chat text, task names,
and other private content.

When older firmware is detected, the app offers an in-app update. The release
contains the complete firmware payload and a universal flashing tool, so
recipients do not need PlatformIO. Q disconnects its normal serial session,
flashes the already-identified Q port, reconnects, and verifies the expected
version before declaring success. Keep Q connected during the update; a failed
update remains retryable from the same card.

## Install Q

Requirements: macOS 14 or later and Swift 6.0 or later.

Build and install the real application bundle:

```sh
swift build
sh Scripts/install-app.sh
```

If Apple's installed Swift compiler and SwiftPM manifest runtime are temporarily
out of sync, `sh Scripts/build-local.sh release` is the supported direct-compiler
fallback. The DMG release script detects that toolchain condition automatically.

Q is installed at `/Applications/Q.app`, appears in Spotlight and Finder with its
own icon, and keeps its Q control in the macOS menu bar without adding a Dock
icon. The installed app registers itself to reopen automatically at login and
registers a lightweight LaunchAgent that can launch Q when a module is connected.
Opening Q again from Spotlight or Finder reveals its popover when it is already
running.

For development without installing, use `swift run Q`. To create only a local
launchable bundle, run `sh Scripts/package-app.sh` and open `.build/Q.app`.

The production XIAO ESP32-C3 firmware lives in `Firmware`. Once flashed, Q finds
the device over USB automatically, mirrors every app scene to the physical LEDs,
and accepts single-, double-, and long-button presses. See `Firmware/README.md`
for the one-command PlatformIO upload flow and the verified PCB pin map.

## Distribute Q

Q ships as the familiar drag-to-Applications disk image used by independent Mac
apps. `Scripts/release-dmg.sh` builds a universal Apple silicon + Intel release,
packages and Developer-ID signs `Q.app`, creates a compressed `Q-<version>.dmg`
containing Q beside an Applications shortcut, and verifies the image.

For a public release, first save Apple notary credentials once:

```sh
xcrun notarytool store-credentials Q-notary
```

Then build, notarize, staple, and Gatekeeper-check the complete release:

```sh
Q_NOTARY_PROFILE=Q-notary sh Scripts/release-dmg.sh
```

The finished download appears under `Dist`. Without `Q_NOTARY_PROFILE`, the same
command creates a signed local test DMG but intentionally skips notarization.

The app keeps a virtual device model internally for shared behavior and testing,
but the product UI is focused on the connected physical device. The current
contextual button action is always shown in the popover.

General Settings configures the physical button's single, double, and long press
independently. Factory defaults use the contextual action for single press,
cycle to the next primary mode for double press, and use the contextual action
for long press. In AI Agents, a long press focuses the active Codex task and
holds Codex's own `composer.startDictation` command until the physical button
is released. macOS Accessibility is used only to deliver Codex's built-in
Control-Shift-D binding; macOS system Dictation is never invoked.
In AI Agents Idle, single press opens the most recently modified local Codex
conversation directly.
In Meetings, long press temporarily unmutes the selected provider and release
mutes it again. Auto follows the active call; a manual provider selection makes
the button deterministic when several meeting apps are open.
Every press normally shows a compact five-second mode and state confirmation
beside the menu-bar Q. The AI Agents dictation hold remains silent so it starts
without a competing popup. Settings are persisted locally.

Custom modes are built in a native visual editor. Each profile can contain
multiple named states, and every state defines the color, brightness, enabled
status, and animation of all three LEDs. Single, double, and long presses can
move between states, switch the lights off, open an HTTPS URL or application,
or run an Apple Shortcut. Profiles use one local `Codable` model, providing the
same declarative boundary that future AI, MCP, and SDK adapters can generate.
The editor imports and exports `.qmode` JSON files; the public contract is
documented in `Docs/custom-mode.schema.json`.

The supplied Q artwork is used consistently for the app icon, menu-bar item, and in-app identity. To regenerate the derived icon assets after replacing `Resources/Brand/qgadget.png`, install ImageMagick and run `sh Scripts/generate-brand-assets.sh`.

## Verify

```sh
swift build
swift test
```

The Swift package can also be opened directly in Xcode when the full Xcode application is installed.

## Architecture

- `QCore` contains transport-safe `Codable` semantic state and the device layer, independently importable by future app and CLI targets.
- `QModeCatalog` defines the five primary MVP modes, their semantic states, scenes, priorities, and safe default button mappings.
- `QAgentSlotResolver` assigns the three most relevant agent sessions to physical LED slots using semantic priority and recency.
- `QPomodoroConfiguration` provides configurable local focus/break timing and the standard duration presets.
- `QCustomModeDefinition` is the persisted declarative format for user-created modes, states, scenes, and safe button actions.
- `Device/QDevice.swift` is the hardware-independent boundary used by the rest of the app.
- `Device/VirtualQDevice.swift` provides the on-screen preview.
- `Device/SerialQDevice.swift` discovers the physical USB device, mirrors scenes, and forwards its button events.
- `UI/VirtualQ` renders LED effects in SwiftUI and forwards physical-style button gestures to the device.
- `App` and `UI/MenuBar` provide the accessory-style menu-bar application shell.

The physical and virtual devices share the same `QDevice` contract, so integrations, state resolution, and custom modes drive both identically.

## Factory visual grammar

- Green means clear, ready, or successful.
- Yellow means active, transitional, or away.
- Blue means engaged, attention, or focus.
- Red means blocked, error, or do not disturb.
- Purple means deliberate timed focus.
- Opal means physically off.

Solid light is stable, chase is ongoing, slow fade requests awareness, blink signals a problem, and flash marks a new event. These are app-level factory presets—not firmware behavior—so later persistence can make every scene and mapping user-editable.
