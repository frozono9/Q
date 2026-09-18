# Q portable desktop — availability preview

The first P2/P3 slice reproduces the Mac panel's hierarchy, Q logo, status,
three lights, button action, availability choices and Settings. Windows/Linux
share this interface; Mac retains its native SwiftUI application.

## Run

Extract the entire desktop archive. Windows: open `QPortable.exe` in its folder.
Linux: run `./q-portable` in the extracted folder (Ubuntu 24.04 x86_64 baseline).
The package includes Electron and the Swift engine/runtime; no compiler, Node,
Python or Swift installation is required. Linux still needs its normal desktop
libraries and permission to open Q's serial device (see PORTABLE_CLI.md).

Close other Q clients/serial monitors first. The application owns the USB port
while it runs. It reconnects only to its verified device ID. Choose Available,
Focus, Busy/DND, Away or Offline; adjust brightness; open Settings to test lights
and see physical button gestures. Single press cycles Available → Focus → Busy
→ Available; from Away/Offline it returns to Available, matching Mac's catalog.

On Windows the close button hides Q to the tray. Open it by clicking its tray
icon; use the power button or tray menu to quit. On Linux closing the window
quits; a normal window/taskbar entry remains available even without tray support.
Exit attempts to turn the lights off. Firmware may subsequently pulse red when
heartbeats stop. Changing availability or brightness cancels a running light test.

Settings are stored outside the extracted folder in Electron's user-data folder
(`%APPDATA%/Q Portable/settings.json` on Windows; `$XDG_CONFIG_HOME/Q Portable`
or `~/.config/Q Portable` on Linux). Replacing the application keeps preferences.
Each write is atomic and keeps the previous valid file as `settings.json.bak`.
Unknown schema versions or corrupt files are preserved and reported, never reset
silently. This version uses schema 1; no migration from Mac UserDefaults is made.

## Architecture decision

Electron provides the Windows/Linux window and tray; HTML/CSS reproduce the Mac
layout with system fonts. The tradeoff is a larger package and Chromium runtime
to maintain. Runtime versions are pinned in package-lock.json. The renderer is
sandboxed, has no Node access and loads only packaged resources. It gets a narrow
validated IPC API, not arbitrary process/network/filesystem access. No HTTP server
or network listener is started. See [Electron security guidance](https://www.electronjs.org/docs/latest/tutorial/security)
and [tray platform differences](https://www.electronjs.org/docs/latest/api/tray).

One child `q serve --settings <absolute path>` process owns the device, models
and persistence. IPC v1 is newline-delimited JSON over inherited stdin/stdout.
Allowed operations: snapshot, setState, setBrightness, press, test, cancelTest.
Snapshots distinguish saved intent from an acknowledged physical scene. EOF
closes the engine; the desktop waits for cleanup on exit. Commands and buffers
are bounded. No shell commands or actions from profiles can be executed here.

`QAvailability` shares the Mac primary cycle and brightness calculation. The
factory catalog supplies states, colors and button rules. Mac adopts these two
small pure helpers without changing its UI, settings or transport. Desktop
dependencies are built only on Windows/Linux and never enter the Mac package.

## Development

Build/package the Swift CLI first using the existing scripts. In Clients/Desktop:

```text
npm ci
Q_ENGINE_PATH=<absolute path to packaged q> npm start
Q_ENGINE_PATH=<absolute path to packaged q> npm test
npm run package
```

Use PowerShell `$env:Q_ENGINE_PATH = 'C:\path\q.exe'` on Windows. Development
tests use temporary settings and an absent port; the real engine handles all
state/persistence requests. Q_DESKTOP_DATA and Q_ENGINE_PORT overrides are
available only to unpackaged development builds. CI also runs the native Linux
PTY tests. Linux GUI CI uses Xvfb, which does not certify every Wayland desktop.

## Scope

This is the first usable P2/P3 slice, not completion of both phases. Pomodoro,
Relaxing, custom modes, connected-app integrations, login startup and firmware
updates are not offered by this preview. Physical Linux USB and manual Mac smoke
checks remain outstanding. Public releases/signing and broader Linux support
remain P4. Development artifacts are produced on the portable branch only.
