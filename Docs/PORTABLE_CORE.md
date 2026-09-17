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
dependencies, public API renames or edits to Mac UI/integration sources.
`Scripts/build-local.sh` still compiles the same source directories directly.

All existing model/resolver/protocol tests run on every host. The three tests
in `VirtualQDeviceTests.swift` remain enabled on Mac; the other hosts exclude
that file because the current virtual device uses Combine and OSLog. This does
not replace future tests for Windows/Linux device implementations.

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
Mac job tests original commit `5c7a1e5`, then builds the current universal
binaries with the unchanged direct-compiler fallback, packages Q.app and checks
both architectures and the ad-hoc signature.

Windows Server CI validates compilation and tests, not the Windows 11 end-user
experience. Linux CI similarly does not establish desktop or hardware support.
No workflow in this change publishes a release, installs an app, flashes Q,
changes main or changes repository protection settings.

## Validation status

At implementation time, the local Windows workstation and its Ubuntu WSL
distribution did not have Swift installed. Validation is delegated to the
workflow, with results to be recorded after execution. Writing the workflow
alone is not evidence of a passing build.

P0 remains incomplete until successful runs are recorded and the Mac hardware/
interactive smoke test in the implementation plan is completed. The next
implementation phase is P1: transport and CLI, not a UI rewrite.
