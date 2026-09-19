# Portable desktop: first P2/P3 slice

Validated on 18–19 September 2026. This is an experimental availability client,
not completion of P2/P3 or parity with all Mac integrations.

## Automated evidence

[Successful complete run for `36083d2`](https://github.com/frozono9/Q/actions/runs/35291652848):

| Platform/check | Result |
| --- | --- |
| Windows Server 2022, Swift 6.1.2 | 79 Swift tests, optimized engine, 2 desktop checks, desktop package |
| Ubuntu 24.04, Swift 6.1.2 | 79 Swift tests, native PTY transport and desktop protocol tests, 2 desktop checks under Xvfb, desktop package |
| macOS 15, Swift 6.1.2 | 65 Swift tests, optimized existing app products |
| Existing Mac build scripts | Universal binaries, Q.app packaging and signature checks |

The desktop test drives the real Electron renderer, its restricted IPC bridge
and the actual Swift engine. It checks saved state/brightness, restart recovery,
context isolation, settings navigation and graceful exit. It uses an absent
serial port and temporary preferences; it does not pretend to certify hardware.
The Linux PTY test separately exercises acknowledged scenes, physical-button
messages, brightness, test cancellation/restoration, persistence and EOF cleanup.

The final UI revision `a413722` replaces a font-dependent quit glyph with an
embedded SVG. Its [validation and downloadable artifacts](https://github.com/frozono9/Q/actions/runs/35443511998)
include the Windows and Linux packages. Artifacts expire after 14 days; they are
development builds, not GitHub Releases. The `q-cli-<OS>-<commit>` artifact contains
both the CLI archive and the desktop archive.

## Windows hardware session

On 19 September, the extracted `QPortable.exe` package ran on Windows 11 Home
without an installed Swift SDK. The session verified:

- Q `Q-386661B2F180` on COM9, firmware `0.2.2`, protocol 1.
- Physical acknowledgement after choosing Busy/DND and changing brightness to 42%.
- Settings on disk matched the acknowledged UI state.
- Closing the app released COM9: a separate CLI status command could acquire it.
- Reopening restored Busy/DND and 42% brightness and applied them to the device.
- The UI button changed Busy → Available → Focus through the shared rules.
- The user's previous state and brightness were restored after the test.

The local deliverable uses UI commit `a413722` and the CI-built engine from
`c6668bf`; `git diff c6668bf..a413722 -- Sources Package.swift` is empty. Both
revisions are recorded in the package's root and engine `COMMIT.txt` files.
The archive's SHA256 is
`EB86B5CE7BF2FECBC1478E657984BA94657D973B58BB9BDD66B719DE6DA97859`.

The user had already confirmed the P1 Windows CLI tests worked. This session
adds the packaged GUI checks; it does not claim a new physical double/triple
press, suspend/resume or unplug/replug test of the GUI.

## Remaining work

- Physical USB/gestures/reconnection on native Linux and desktop-specific tray checks.
- Manual Mac hardware smoke test; automated Mac regressions are covered.
- Subsequent P2/P3 slices: Pomodoro, Relaxing, custom modes and platform integrations.
- P4 release distribution, signing, broader Linux coverage and update/recovery testing.

All implementation stays on `feature/portable-clients`. No merge, release or
change to `main` is part of this delivery.
