# Portable core: P0 implementation

This branch makes the existing Q models and serial protocol available to Swift
on Windows and Linux while keeping the Mac application and its source paths.
It does not yet provide a Windows/Linux application or serial transport.

## Decision: compose the existing module by host

`Package.swift` retains the `QCore` module and adds a library product for it.
On macOS it includes the same models and devices as before, plus all three
existing executable products. On Windows/Linux it excludes only the two
Apple-specific device implementations and does not declare the Mac executables.

The `QDevice` contract, `QDeviceError`, button events, `QSerialProtocol` and every
model compile from the same files. There are no copied models, new runtime
dependencies, public API renames or Mac UI/integration rewrites.
`Scripts/build-local.sh` still compiles the same source directories directly.
The Mac serial adapter has one compiler-compatibility fix: three explicit
`self.` references in the heartbeat error closure, with unchanged behavior.
Two additional Mac build fixes make the meeting logger's `self.provider`
explicit and isolate the shared NSImage assets to the main actor.

All existing model/resolver/protocol tests run on every host. The three tests
in `VirtualQDeviceTests.swift` remain enabled on Mac; the other hosts exclude
that file because the current virtual device uses Combine and OSLog. This does
not replace future tests for Windows/Linux device implementations.
The hold-lifecycle tests evaluate mutating operations before passing results to
Testing macros; Swift 6.1.2 cannot expand the original direct `#require` calls.
The operations and assertions remain the same.

This is a small first boundary, not the final application architecture. Mac
still has device adapters in QCore, and application coordination still lives
in QAppModel. Further extraction belongs to P2 and should be driven by concrete
portable features. The `#if os(macOS)` in the manifest selects a native host
build; cross-compiling Mac from Windows/Linux is not supported by this setup.

## Build and test

Install the Swift toolchain and platform prerequisites for development, then:

```sh
swift build --target QCore
swift test
swift build --configuration release
```

On Mac, the last command also builds Q, QDeviceWatcher and QClaudeHook. On
Windows/Linux it builds the shared library; there is no Q executable yet.
These development prerequisites are not the eventual end-user install flow.

## CI and baseline

The `Portable core` workflow runs on this branch, relevant pull requests and
manual dispatch. Swift 6.1.2 is the initial CI baseline (Xcode 16.4 on Mac);
the package keeps its existing Swift tools minimum of 6.0 and macOS minimum of 14.
Passing CI on 6.1.2 does not establish a new claim that every compiler version
between 6.0 and the latest release has been tested.

The matrix uses Ubuntu 24.04, Windows Server 2022 and macOS 15 hosted runners.
It builds the core, executes tests and builds optimized products. A separate
Mac job builds the current universal binaries with the unchanged direct-compiler
fallback, packages Q.app and checks both architectures and the ad-hoc signature.

Windows Server CI validates compilation and tests, not the Windows 11 end-user
experience. Linux CI similarly does not establish desktop or hardware support.
No workflow in this change publishes a release, installs an app, flashes Q,
changes main or changes repository protection settings.

## Validation status

At implementation time, the local Windows workstation and its Ubuntu WSL
distribution did not have Swift installed. Validation runs on GitHub Actions.

The first run tested original commit `5c7a1e5` separately and demonstrated an
existing Mac compile failure under Swift 6.1.2: `SerialQDevice.swift:202-204`
requires explicit `self` after a weak capture in its nested heartbeat task.
The same diagnostics appeared on the portable branch before the fix. See the
[baseline run](https://github.com/frozono9/Q/actions/runs/35245506474).
The original baseline is not repeatedly tested in subsequent runs; those runs
validate the current branch, including the minimal fix. No change was made to main.

Executing the portable tests also exposed an existing vocabulary bug: substring
matching classified Spanish "Desactivar micrófono" as "Activar micrófono".
Microphone phrases now match at word boundaries; the existing failing assertion
is retained and additional tests cover opposite actions with shortcut suffixes.

The [successful validation run](https://github.com/frozono9/Q/actions/runs/35246362606)
tested commit `8da41c0206453865d590afbcedd98f8f74eb87f8` on 17 September 2026:

| Check | Result |
| --- | --- |
| macOS 15 arm64, Swift 6.1.2 | Core build, 63 tests and optimized app products passed |
| Ubuntu 24.04 x86_64, Swift 6.1.2 | Core build, 60 tests and optimized library build passed |
| Windows Server 2022 x64, Swift 6.1.2 | Core build, 60 tests and optimized library build passed |
| Existing Mac direct-compiler script | Built universal arm64 + x86_64 binaries |
| Existing Mac app packaging | Q.app packaged; both architectures and ad-hoc signature verified |

The three-test difference is the existing Mac virtual-device suite. No model or
protocol test was removed to get a passing run. These are build/test results,
not a portable client release or a hardware certification.

The automated P0 checks are complete. The Mac hardware/interactive smoke test
in the implementation plan still needs a person with a Mac and Q; no physical
Mac session was available here. P0 is not fully signed off until that result
is recorded. The next implementation phase is P1: transport and CLI, not a UI
rewrite. Windows 11 hardware testing, Linux hardware testing, portable UI and
end-user packages remain outstanding.
