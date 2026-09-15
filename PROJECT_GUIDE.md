# Q — Project and Extension Guide

This document explains what Q is, what the current hardware and macOS app do,
how both halves communicate, and where to make changes when adding a mode,
integration, animation, or button action.

It describes the repository as it exists today:

- macOS app version: **0.1.0**
- firmware version: **0.2.1**
- serial protocol version: **1**
- target hardware: **Seeed Studio XIAO ESP32-C3 + Q production PCB**

## 1. What Q is

Q is a small, local-first ambient status device. It has three RGB LEDs and one
physical button. A native macOS menu-bar app observes activity on the Mac,
turns that activity into semantic states, and renders the selected state on the
physical device over USB-C.

The central interaction is deliberately simple:

> See something on Q → press Q → Q performs the action relevant to that state.

Examples:

- An AI task is working: the LEDs show an amber chase.
- An AI task needs permission or input: all three LEDs breathe blue; pressing Q
  opens that exact Codex task.
- A Discord call is active: the LEDs turn blue; pressing Q toggles mute.
- A Pomodoro is running: purple LEDs progressively fade out as time passes.
- A custom state can display any three colors and make a press open an app, URL,
  or Apple Shortcut.

Q does not require Wi-Fi, Bluetooth, a cloud account, an API key, or a server.
The PCB is powered and controlled through the same USB-C connection.

## 2. Product principles

### Semantic color language

The factory modes share one visual grammar:

| Color | Meaning |
| --- | --- |
| Green | Clear, ready, available, or successful |
| Amber/yellow | Active, transitional, or away |
| Blue | Engaged, focused, or requiring attention |
| Red | Blocked, failed, disconnected, or do not disturb |
| Purple | Deliberate timed focus |
| Opal/off | No active signal |

Animation adds a second dimension:

| Motion | Meaning |
| --- | --- |
| Solid | Stable state |
| Chase | Ongoing activity or transition |
| Slow fade | Awareness or attention |
| Blink | Error or problem |
| Flash | An event just happened |

These meanings are app-level defaults, not hard-coded product restrictions.
Custom modes can use any colors or animations.

### Local-first ownership

- Codex state is read from local Codex session files.
- Discord call state is read from Discord's local log.
- Preferences and custom modes stay in macOS `UserDefaults`.
- LED scenes travel directly over USB serial.
- There is currently no analytics service, cloud relay, or Q account.

### App owns meaning; firmware owns rendering

The app decides that something is “Working,” “Muted,” or “Focus.” The firmware
does not know those concepts. It only receives three LED definitions containing
color, brightness, enabled state, animation, speed, and phase.

This division means most new product behavior can be added entirely in Swift
without reflashing the PCB. Firmware changes are needed only for transport,
button timing, pin mapping, PWM behavior, or genuinely new animation primitives.

## 3. What is working today

### Physical device

- Automatic USB serial discovery.
- Device handshake and protocol-version validation.
- Unique hardware ID derived from the ESP32-C3 eFuse MAC.
- Firmware version reported inside Device Settings.
- Three independently controlled RGB LEDs.
- Global brightness setting persisted per Mac.
- Single, double, and long button gestures.
- Red breathing startup/waiting indication.
- Three green connection pulses after a fresh app handshake.
- Heartbeat and challenge/response watchdog.
- Stable timer-driven PWM at roughly 391 Hz.
- In-app RGBW light test and physical-button test.

### macOS app

- Native Swift/SwiftUI menu-bar application with no Dock icon.
- Persistent Q status-bar icon.
- Automatic launch-at-login registration when installed in `/Applications`.
- A lightweight `QDeviceWatcher` LaunchAgent that can launch a closed Q after a
  compatible module is newly connected.
- Automatic popover presentation after a newly connected PCB completes its
  identity handshake.
- Compact five-second confirmation after every physical button gesture.
- Five factory modes plus any number of custom modes.
- Device identity, firmware, port, brightness, and tests in Settings.
- A hardware-independent internal device model used by app logic and tests.
  The old visible device preview is intentionally no longer shown.

### Integrations

- **AI Agents:** local Codex tasks, including working, input/permission,
  completion, failure, exact-task focusing, and up to three simultaneous task
  slots.
- **Meetings:** local Discord desktop call detection and mute/unmute control.
- **Pomodoro:** local focus/break timer with editable durations, pause/resume,
  phase transitions, and progressive LED depletion.
- **Availability:** manually controlled Available, Focus, Busy/DND, Away, and
  Offline states.
- **Relaxing:** a very slow, phase-offset rainbow gradient.
- **Custom:** user-created modes, states, light scenes, and button mappings.

## 4. Important current limitations

The code intentionally leaves room for more integrations, but the following are
not implemented yet:

- AI Agents currently reads **Codex local session rollouts only**. The standalone
  ChatGPT app/browser, Claude, Cursor, and other agent processes do not yet have
  adapters.
- Meetings currently supports **Discord only**. Zoom, Google Meet, Microsoft
  Teams, Slack huddles, and FaceTime do not yet have adapters.
- Discord mute state is updated when Q sends the mute shortcut; the Discord log
  parser itself currently detects call connection/disconnection, not every mute
  transition.
- Availability's automatic mode is only a placeholder; manual states are the
  meaningful behavior today.
- A Builds preset exists in the core model but is not part of the five primary
  modes and has no CI provider integration.
- `.qmode` import/export is implemented, but there is no running MCP server,
  public network API, plugin SDK, or local IPC endpoint yet.
- The app controls one physical Q at a time. If several are connected to one
  Mac, the first valid device found is selected.
- The background watcher recognizes the XIAO's native Espressif USB identity
  (`303A:1001`). Another ESP32-C3 development board using the same native USB
  interface can therefore wake Q, although the app will still reject it unless
  it completes Q's serial handshake.
- Preferences belong to the Mac user, not the PCB. Moving a PCB to another Mac
  does not move its custom modes or button configuration.
- The distributed test DMG is not Apple-notarized. It works, but another Mac may
  require the Gatekeeper “Open Anyway” flow on first launch.

These boundaries matter when designing additions: describe new work as a new
adapter or capability rather than assuming all agent and meeting apps are
already supported.

## 5. End-user setup

The recipient of an already-flashed PCB does **not** need PlatformIO, Xcode, or
the source repository.

1. Open `Q-0.1.0.dmg`.
2. Drag `Q.app` onto the Applications shortcut.
3. Open Q from `/Applications` or Spotlight.
4. If macOS blocks the unsigned/unnotarized app, open **System Settings →
   Privacy & Security**, find the blocked-app message, and choose **Open Anyway**.
5. Connect the Q PCB over a data-capable USB-C cable.
6. Wait for three green pulses. The Q icon should remain visible in the menu bar.
7. Q's popover opens automatically after the device handshake. Open
   **Settings** and confirm:
   - status is Connected;
   - firmware is `0.2.1`;
   - a unique ID beginning with `Q-` is displayed;
   - Test lights cycles red, green, blue, and white;
   - Test button recognizes a physical press.

For Discord mute control, macOS must grant Q Accessibility permission in
**System Settings → Privacy & Security → Accessibility**. Reading call state
does not require that permission; synthesizing Discord's mute shortcut does.

## 6. Factory modes in detail

### AI Agents

AI Agents is externally managed: users cannot manually force its state from the
state UI. Codex activity owns the LEDs.

| State | LEDs | Button |
| --- | --- | --- |
| Idle | Green chase | Open/focus Codex |
| One working task | Amber chase across all three LEDs | Open that task |
| Two or three relevant tasks | One slot per task | Open highest-priority task |
| Needs input/permission | Blue fade | Open the exact task |
| Done | Green flash then solid | Open result |
| Error | Red blink | Open failed task |

For multiple tasks, each task occupies one LED:

- amber fading = working;
- blue fading = needs the user;
- green solid = done;
- red blinking = error.

Sessions are sorted by semantic priority, then recency:

1. needs input/permission;
2. error/failure;
3. working;
4. done;
5. idle.

Only the three most relevant sessions are displayed. Completion stays visible
for 10 seconds; an error stays visible for five minutes. When only one relevant
task remains, Q returns to the expressive full-device scene for that one task.

The scanner looks for recent `.jsonl` rollouts beneath `~/.codex/sessions`,
incrementally tails them, and maps task/turn events onto Q states. Pressing Q
opens `codex://threads/<thread-id>`.

### Availability

Availability is manually editable.

| State | LEDs | Contextual press |
| --- | --- | --- |
| Available | Green solid | Set Focus |
| Focus | Blue solid | Set Busy/DND |
| Busy/DND | Red solid | Set Available |
| Away | Amber chase | Set Available |
| Offline | Off | Set Available |

The normal press cycle intentionally covers Available → Focus → Busy →
Available. Away and Offline are explicit states that return to Available on the
next contextual press.

### Meetings

Meetings is externally managed by Discord.

| State | LEDs | Contextual press |
| --- | --- | --- |
| Free | Green solid | Open Discord |
| In meeting | Blue solid | Mute Discord |
| Muted | Blue fade | Unmute Discord |

The integration watches
`~/Library/Application Support/discord/logs/renderer_js.log`. Only Discord's
primary/default RTC connection affects Q; screen-share RTC connections are
ignored. Mute uses Discord's native `Command-Shift-M` shortcut after activating
Discord.

### Pomodoro

Default durations are 25 minutes of focus and 5 minutes of break. Focus can be
configured from 1–180 minutes and break from 1–60 minutes.

| State | LEDs | Contextual press |
| --- | --- | --- |
| Idle | Off | Start focus |
| Focus | Purple progress | Pause |
| Paused | Amber solid | Resume |
| Break | Green progress | End break |
| Finished | Green flash | Start next phase |

Focus and break use the same three-segment progress model. Each LED represents
one third of the phase. The LED due to disappear next gradually loses brightness
through its third instead of switching off abruptly. The perceptual curve uses
an exponent of `0.5`, keeping a small LED visibly present for most of its segment.

Editing a running duration preserves time already spent. Changing a 25-minute
session to 15 minutes after five minutes have elapsed leaves ten minutes; it
does not restart the timer.

### Relaxing

Relaxing has one state: Slow Flow. Every LED runs the same slow rainbow with a
small phase offset (`0.00`, `0.09`, `0.18`) and speed `0.015`, producing a gentle
gradient instead of synchronized color changes.

### Custom modes

Custom modes are described in section 8. Each custom mode may contain any
number of states and may optionally participate in the global double-press mode
cycle.

## 7. Button behavior

Firmware recognizes:

- debounce: 25 ms;
- double-press window: 260 ms;
- long-press threshold: 650 ms.

Global assignments are configured under Settings:

| Gesture | Factory default | Available assignments |
| --- | --- | --- |
| Single press | Contextual action | Contextual, next mode, next state, show status, none |
| Double press | Next mode | Contextual, next mode, next state, show status, none |
| Long press | None | Contextual, next mode, next state, show status, none |

Every recognized gesture shows a small mode/state confirmation for five seconds,
including gestures whose assignment is Show status or None.

Externally managed modes reject manual state cycling. This prevents the app from
claiming an AI task or meeting is in a state that its source did not report.

Custom states can inherit each global gesture or override it independently.

## 8. Extending Q without code

The safest and fastest extension path is the Custom Mode editor.

From the mode menu, choose **New Custom Mode…**. A mode contains:

- a name and SF Symbol icon;
- whether it is included in the double-press mode cycle;
- one or more named states;
- a default state;
- exactly three LED definitions per state;
- single, double, and long-press actions per state.

Each LED supports:

- any RGB color;
- 0–100% brightness;
- enabled/off;
- Solid, Blink, Pulse, Flash, Fade in/out, Chase forward, or Chase backward.

Each custom gesture supports:

- use the global setting;
- no action;
- next or previous custom state;
- turn all LEDs off;
- open an HTTPS URL;
- open a macOS application by bundle ID or app name;
- run an Apple Shortcut by name.

Apple Shortcuts is the easiest bridge to behavior outside Q. A Shortcut can
control HomeKit, send a message, call an API, manipulate files, or chain other
macOS actions, while Q only needs the Shortcut's name.

### Sharing `.qmode` files

The editor can export a mode as JSON with a `.qmode` extension. Another user can
import it from Settings or the mode menu. The formal contract lives at
`Docs/custom-mode.schema.json`.

The recommended way to author a `.qmode` is:

1. create a similar mode in the visual editor;
2. export it;
3. edit the resulting JSON;
4. validate it against the schema;
5. import it as a new mode.

Use unique UUIDs for the mode, every state, and every scene. `defaultStateID`
must match one of the state IDs. Colors and brightness use values from `0.0` to
`1.0`.

## 9. Repository map

```text
Q/
├── Config/Info.plist                 App metadata and version
├── Config/app.q.device-watcher.plist Embedded LaunchAgent definition
├── Docs/custom-mode.schema.json      Public .qmode JSON contract
├── Firmware/
│   ├── platformio.ini                XIAO build/upload configuration
│   └── src/main.cpp                  Firmware, PWM, serial, button, watchdog
├── Resources/Brand/                  Source and generated icon assets
├── Scripts/
│   ├── install-app.sh                Install local build in /Applications
│   ├── package-app.sh                Assemble and sign Q.app
│   ├── create-dmg.sh                 Create drag-to-Applications DMG
│   ├── release-dmg.sh                Universal release pipeline
│   └── notarize-dmg.sh               Apple notarization/stapling
├── Sources/Q/
│   ├── App/                           Lifecycle and central app model
│   ├── Device/                        Hardware abstraction and USB protocol
│   ├── Integrations/                  Codex and Discord adapters
│   ├── Models/                        Modes, states, scenes, actions, timers
│   └── UI/                            Menu popover and custom editor
├── Sources/QDeviceWatcher/            USB watcher that can launch a closed Q
└── Tests/QTests/                      Unit and behavior tests
```

The Swift package has three targets:

- `QCore`: transport-safe models and device layer;
- `Q`: AppKit/SwiftUI shell, integrations, and UI;
- `QDeviceWatcher`: background USB presence watcher and app launcher.

The main coordination point is `Sources/Q/App/QAppModel.swift`. Integrations
send semantic data into this model. It resolves the selected state, applies
global brightness, updates the internal device model, and mirrors the resulting
scene to `SerialQDevice` when hardware is connected.

```text
Codex files / Discord log / timer / user action
                       │
                       ▼
                semantic QState
                       │
                       ▼
                QAppModel + preset
                       │
                       ▼
             QScene (exactly 3 LEDs)
                       │
              ┌────────┴────────┐
              ▼                 ▼
       internal model     SerialQDevice
                                │ USB
                                ▼
                         ESP32-C3 firmware
                                │
                                ▼
                           physical LEDs
```

## 10. Hardware

The production board contains:

| Quantity | Part | Designators | Notes |
| ---: | --- | --- | --- |
| 1 | Seeed Studio XIAO ESP32-C3 | U1 | Main MCU and native USB serial |
| 3 | TUOZHAN P4-1615G2B2R4TS2-06T-001-24 RGB LED | LED1–LED3 | Common-anode, LCSC C7496855 |
| 9 | 330 Ω 0603 resistor | R1–R9 | One resistor per color channel, LCSC C279996 |
| 1 | TS3320A tactile switch | SW2 | Active-low button, LCSC C2681475 |

### Verified pin map

| Physical LED | Red | Green | Blue |
| --- | --- | --- | --- |
| LED1 | GPIO3 / D1 | GPIO4 / D2 | GPIO5 / D3 |
| LED2 | GPIO6 / D4 | GPIO7 / D5 | GPIO21 / D6 |
| LED3 | GPIO20 / D7 | GPIO2 / D0 | GPIO10 / D10 |

The button is GPIO8 / D8 using the XIAO's internal pull-up.

The LEDs are common-anode: electrically, HIGH is off and LOW is on. That
inversion is isolated in firmware. App colors and brightness retain normal
semantics, so `brightness = 1.0` always means fully bright to Swift code.

The ESP32-C3 has fewer hardware LEDC channels than Q's nine RGB channels. The
firmware therefore uses a hardware-timer-driven software PWM engine:

- 128 brightness levels;
- a 20 µs timer step;
- approximately 391 Hz complete PWM refresh;
- direct GPIO register writes so all nine channels update together;
- channel calibration `{ red: 0.55, green: 0.20, blue: 1.00 }` to compensate
  for the fitted LED's much brighter green die.

Changing the PCB pin routing, LED electrical topology, or component choice
requires reviewing `kPins`, `kButtonPin`, common-anode inversion, and
`kChannelCalibration` in `Firmware/src/main.cpp`.

## 11. USB serial protocol

Q uses newline-terminated ASCII at 115200 baud. Protocol version 1 is purposely
small enough to inspect in a serial terminal.

### App → firmware

| Message | Meaning |
| --- | --- |
| `H|1` | Handshake request |
| `P|1` | App heartbeat |
| `S|<led1>|<led2>|<led3>` | Apply complete three-LED scene |

Each LED segment is:

```text
red,green,blue,brightness,enabled,animation,speedMilli,phaseMilli
```

- RGB and brightness: integers `0...255`;
- enabled: `0` or `1`;
- speed and phase: floating-point values multiplied by 1000 and sent as integers.

Animation codes must remain synchronized between Swift and firmware:

| Code | Animation |
| ---: | --- |
| 0 | Solid |
| 1 | Blink |
| 2 | Pulse |
| 3 | Flash |
| 4 | Flash then solid |
| 5 | Fade in/out |
| 6 | Chase forward |
| 7 | Chase backward |
| 8 | Bounce |
| 9 | Progress |
| 10 | Alternating |
| 11 | Gradient shift |
| 12 | Rainbow |

### Firmware → app

| Message | Meaning |
| --- | --- |
| `Q|1|0.2.1|Q-<chip-id>` | Identity/handshake response |
| `A|scene` | Scene accepted |
| `E|scene` | Malformed scene |
| `E|length` | Input line overflow |
| `B|single` | Single press |
| `B|double` | Double press |
| `B|long` | Long press |
| `C|heartbeat` | Firmware asks a potentially delayed app to reply now |

### Connection lifecycle

1. At power-up, firmware sets all common-anode outputs safely off and starts a
   slow red waiting pulse.
2. The app scans supported `/dev/cu.*` names every two seconds.
3. It opens a candidate, waits 800 ms, sends `H|1`, and waits for a valid Q
   identity rather than trusting the filename.
4. Firmware reports its protocol, version, and chip ID, then plays three green
   pulses.
5. The app sends the current scene and a heartbeat every second from a dedicated
   serial queue.
6. After eight seconds without traffic, firmware keeps the current scene visible
   and sends `C|heartbeat` challenges every two seconds.
7. A live app immediately answers with `P|1`. Only 30 seconds of unanswered
   challenges cause firmware to return to the red waiting pulse.

This two-stage watchdog prevents a delayed macOS task from producing a false
red disconnect flash while still detecting a genuinely dead app.

Q normally remains running as a lightweight login item, which allows a USB
connection to reveal the popover. If the user explicitly chooses **Quit Q**, the
separate `QDeviceWatcher` remains idle in the background. It respects the quit
while the current module stays attached, then launches Q after a genuine
disconnect/reconnect transition.

For a breaking protocol change, increment the protocol version in both
`QSerialProtocol.version` and firmware, and decide whether the app must retain
backward compatibility with already-distributed PCBs.

## 12. Building the macOS app

Requirements:

- macOS 14 or newer;
- Xcode/Swift toolchain compatible with Swift 6;
- Git.

```sh
git clone https://github.com/frozono9/Q.git
cd Q
swift build
swift test
sh Scripts/install-app.sh
```

`install-app.sh` packages the executable, signs it with an available local
identity (or ad-hoc signing as fallback), copies it to `/Applications/Q.app`,
registers it with Launch Services, and opens it.

If Swift Package Manager reports `PackageDescription` linker errors, the active
Command Line Tools and Swift installation do not match. Check:

```sh
xcode-select -p
swift --version
xcodebuild -version
```

With full Xcode installed, select its toolchain:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### Creating a DMG

For a local build already packaged as `.build/Q.app`:

```sh
sh Scripts/create-dmg.sh
```

The result appears under `Dist/` and contains only `Q.app` and an Applications
shortcut.

For a universal arm64 + x86_64 release:

```sh
sh Scripts/release-dmg.sh
```

Without a paid Apple Developer workflow, the DMG can be shared privately but
recipients may need Open Anyway. With Developer ID and saved notary credentials:

```sh
xcrun notarytool store-credentials Q-notary
Q_NOTARY_PROFILE=Q-notary sh Scripts/release-dmg.sh
```

## 13. Building and flashing firmware

Install PlatformIO Core, connect one XIAO, and run:

```sh
cd Firmware
pio run
pio run --target upload
```

When more than one serial device exists, specify the exact port:

```sh
ls /dev/cu.usbmodem*
pio run --target upload --upload-port /dev/cu.usbmodem101
```

Quit Q before flashing so it releases the serial port. After upload, reopen Q;
it should reconnect automatically and display the firmware version and unique ID
in Settings.

Useful PlatformIO configuration is in `Firmware/platformio.ini`:

- board: `seeed_xiao_esp32c3`;
- framework: Arduino;
- native USB CDC enabled at boot;
- monitor: 115200 baud;
- upload: 921600 baud.

Never flash a different board target without checking pins and voltage first.

## 14. Adding a new agent integration

The existing Codex adapter is the reference implementation:
`Sources/Q/Integrations/CodexLocalIntegration.swift`.

A new adapter should:

1. Observe a reliable local source: documented API, local event stream, log, or
   accessibility state.
2. Produce stable `QAgentSession` values containing:
   - globally unique session ID;
   - source name;
   - human-readable display name;
   - semantic `QState`;
   - context needed to focus the exact task;
   - accurate update time.
3. Map source events onto `.working`, `.waitingForUser`, `.done`, or `.error`.
4. Poll or subscribe away from the main UI path.
5. Deliver snapshots on the main actor.
6. Add exact focusing behavior for the selected session.
7. Add parser, resolver, stale-session, and multi-agent tests.

Before combining Codex, Claude, ChatGPT, and other sources, refactor
`QAppModel` to maintain sessions **per source** and merge them. Do not let the
latest adapter callback replace all sessions from the other adapters. A sensible
shape is:

```swift
private var agentSessionsBySource: [String: [QAgentSession]] = [:]

func updateAgentSessions(source: String, sessions: [QAgentSession]) {
    agentSessionsBySource[source] = sessions
    updateAgentSessions(Array(agentSessionsBySource.values.joined()))
}
```

Use stable IDs such as `claude:<conversation-id>` to avoid collisions. Preserve
the current priority/recency resolver unless the product semantics intentionally
change.

Do not infer “needs you” merely because a window exists. Prefer explicit
permission/input events; false blue alerts destroy trust in the device.

## 15. Adding a meeting integration

The Discord adapter is the reference implementation:
`Sources/Q/Integrations/DiscordLocalIntegration.swift`.

A Zoom, Meet, Teams, or Slack adapter should normalize source-specific state to:

- `.available` — no active meeting;
- `.meeting` — in a call and unmuted/unknown mute state;
- `.muted` — in a call and explicitly muted.

It should also expose:

- whether the source application/session is available;
- an action to focus the meeting;
- a supported, permission-aware mute toggle.

With multiple providers, add an aggregator rather than allowing whichever
provider last polled to overwrite the others. An active meeting should outrank a
free provider. If two meetings are somehow active, define deterministic recency
or provider priority.

Browser-based Google Meet needs a different approach from Discord. Prefer a
browser extension, documented browser automation interface, or explicit local
companion signal over brittle pixel inspection.

## 16. Adding a built-in mode

To make a sixth factory mode:

1. Add its case to `QMode` in `Sources/Q/Models/QMode.swift`.
2. Add it to `QMode.primaryModes` if users should see and cycle through it.
3. Define its `QModePreset`, state IDs, scenes, priorities, and contextual button
   rules in `QModeCatalog`.
4. Decide whether it is externally managed. If yes, manual state selection must
   remain disabled.
5. Add initial state storage and state-resolution logic in `QAppModel`.
6. Add UI labels/details in `QMenuBarView`.
7. Implement every new `QButtonAction` that the mode uses.
8. Add catalog, state-transition, action, and scene tests.

The dormant Builds preset can be promoted this way once a real GitHub Actions,
Xcode, or local build adapter exists.

## 17. Adding a button action

There are two action layers:

- `QButtonAction`: internal actions used by factory presets;
- `QCustomActionKind`: safe actions exposed to custom-mode users.

For a factory action, add the enum case and implement it in
`QAppModel.performLocalAction`. For a user-facing custom action, also add:

- display name and value requirements in `QCustomActionKind`;
- editor controls;
- execution logic in `performCustomAction`;
- the new value in `Docs/custom-mode.schema.json`;
- compatibility tests for existing `.qmode` files.

Treat custom actions as an input boundary. Validate URLs, app identifiers, file
paths, and commands. The current custom editor deliberately exposes Apple
Shortcuts instead of arbitrary shell commands.

## 18. Adding a firmware animation

Only add a firmware animation when existing primitives cannot express the
effect.

1. Add the Swift case to `QAnimation`.
2. Assign the next stable code in `QSerialProtocol.animationCode`.
3. Add the matching numeric enum entry in firmware without renumbering existing
   values.
4. Implement its intensity/color behavior in `animationIntensity` or
   `updateRenderedLevels`.
5. Decide whether it belongs in the Custom Mode editor.
6. Extend the `.qmode` schema if exposed publicly.
7. Add protocol encoding tests and test it on real hardware at low and high
   brightness.

Renumbering animation codes silently changes the meaning of scenes sent by older
apps, so existing codes are part of the protocol contract.

## 19. Future MCP or SDK boundary

The declarative `QCustomModeDefinition` model is the best existing foundation
for an MCP tool or SDK. A future local service could expose narrowly scoped
operations such as:

- list devices and connection health;
- list/create/update custom modes;
- set a custom mode/state;
- display a temporary scene with an expiry;
- subscribe to physical button events;
- register an integration source and publish semantic state.

Recommended safety rules:

- bind local IPC to the current user, not a public network interface;
- require explicit expiry for temporary scenes;
- identify and isolate each external source;
- validate all three LEDs and action payloads against the schema;
- let externally managed sources update only modes they own;
- keep firmware transport inaccessible to untrusted network clients;
- preserve a manual way to recover the device from a bad integration.

Do not bolt MCP directly onto `SerialQDevice`. The app model should remain the
arbiter of ownership, priority, brightness, and button behavior.

## 20. Tests and validation

Run the app suite after every behavior change:

```sh
swift test
```

Current tests cover:

- mode catalog and model behavior;
- Codex activity classification and session discovery;
- multi-agent slot ordering and scenes;
- Discord RTC log parsing;
- Pomodoro duration resizing and brightness progression;
- custom-mode encoding/decoding;
- serial identity, heartbeat, button, and scene encoding;
- device abstraction behavior.

Compile firmware after every firmware or protocol edit:

```sh
cd Firmware
pio run
```

For a release candidate, perform this physical checklist:

1. cold boot shows red breathing;
2. app connection shows exactly three green pulses;
3. current scene returns after the pulses;
4. RGBW test lights all three packages correctly;
5. brightness works from minimum to maximum without objectionable flicker;
6. single, double, and long press are recognized;
7. unplug/replug reconnects automatically;
8. Codex working, needs-user, done, error, and multi-agent states behave correctly;
9. Discord join/leave and mute/unmute behave correctly;
10. Pomodoro focus, pause, resume, break, completion, and live duration edits work;
11. every custom animation/action used in the release is tested;
12. DMG installation is tested on a Mac that has never installed Q.

## 21. Diagnostics

### Check whether macOS sees a XIAO

```sh
ls -l /dev/cu.usbmodem*
```

### Check which process owns the serial port

```sh
lsof /dev/cu.usbmodem101
```

Quit Q before PlatformIO uploads. Quit serial monitors before reopening Q.

### View Q logs

```sh
log stream --style compact --predicate 'subsystem == "app.q"'
```

Recent history:

```sh
log show --last 10m --style compact --predicate 'subsystem == "app.q"'
```

Useful categories include `serial-device`, `application`, `codex-integration`,
`codex-scanner`, `discord-integration`, and `status-item`.

### Device remains red

Check, in order:

1. the cable carries data, not power only;
2. `/dev/cu.usbmodem*` exists;
3. another process does not own the port;
4. Q is running from `/Applications`;
5. firmware and app use protocol version 1;
6. logs show `Physical Q connected`.

### Random red flash

Firmware 0.2.1 includes the challenge/response grace period that fixes transient
heartbeat misses. Confirm Settings reports 0.2.1. Older firmware should be
reflashed.

### Wrong colors or one dead channel

Run Test lights. If the failure always follows one physical color/channel, check
the LED orientation, solder joint, resistor, and matching GPIO. If all LEDs show
the same color imbalance, tune `kChannelCalibration` before assuming a PCB fault.

### App icon exists but menu-bar Q does not

Q is an accessory app (`LSUIElement = true`), so no Dock icon is expected while
running. Reopen Q from Applications/Spotlight to reveal its popover. If the menu
bar is crowded, temporarily close another status item or check around the notch.

## 22. Data, permissions, and security

- Q reads local Codex session files and Discord's local renderer log.
- Q uses Accessibility only to synthesize Discord's mute shortcut.
- Q opens deep links, apps, HTTPS URLs, and named Apple Shortcuts when requested.
- Custom-mode data, gesture settings, and brightness are stored in the current
  user's defaults domain for bundle ID `app.q`.
- No secrets should be placed inside `.qmode` files; they are portable JSON.
- Do not commit Apple notary credentials, signing certificates, user session
  files, or generated private configuration.

There is currently no `LICENSE` file in the repository. Before distributing the
source broadly or accepting public contributions, choose and add an explicit
license. Private testing among collaborators is technically possible without
one, but reuse rights remain unclear.

## 23. Suggested next milestones

The highest-value next work is:

1. test the app/firmware pair with several people and different Macs;
2. collect structured failures for USB reconnects, Gatekeeper, permissions, and
   menu-bar visibility;
3. add a ChatGPT/Claude-style agent-source aggregator without regressing Codex;
4. add Zoom/Meet/Teams integrations behind one meeting-state aggregator;
5. expose a safe local SDK/MCP service around semantic states and custom modes;
6. add preference export/import so a user's setup can move between Macs;
7. add automated release builds and a documented versioning policy;
8. add an explicit open-source license if the project will be shared publicly;
9. pursue Developer ID signing/notarization only when public distribution makes
   the annual Apple account worthwhile.

The most important product constraint is trust: Q is useful only when a glance
at three pixels reliably means what the user believes it means. New integrations
should therefore prioritize explicit state, deterministic ownership, graceful
staleness, and physical-device testing over adding many loosely inferred modes.
