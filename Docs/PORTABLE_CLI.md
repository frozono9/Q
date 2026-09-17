# Q portable CLI — experimental P1

Windows and Linux only. The Mac app keeps its existing runtime and transport.
The CLI uses the existing QCore models and serial encoder, plus native Windows
COM/Linux termios adapters. It does not flash firmware or install a service.

## Run

Extract the Windows ZIP into a folder, then run `q.exe` from PowerShell in that
folder. Linux development packages target Ubuntu 24.04 x86_64: extract the tar
archive and run its `q` launcher. No Swift compiler is required for these packages.

```text
q list
q status
q lights traffic --seconds 10
q lights rainbow --brightness 0.5
q off
q watch --seconds 30
q test
```

In PowerShell use `./q.exe`; on Linux use `./q`. `lights`, `off` and `watch` run
until Ctrl+C unless `--seconds` is specified. `test` displays red, green, blue,
white and traffic for three seconds each after the green connection pulses.
Lights/test attempt an acknowledged off scene on normal exit. The firmware can
return to red waiting pulses once the process stops sending heartbeats; a one-shot
command cannot keep the firmware in its connected state indefinitely.

`status` prints identity JSON, `watch` prints gesture JSON, and connection/error
messages go to stderr. `list` lists compatible USB candidates without opening
them; matching VID/PID alone is not proof that a candidate is Q.

## Selection and reconnection

Automatic discovery filters native Espressif USB serial interfaces (303A:1001),
then verifies Q's protocol and stable ID. Unknown/incompatible firmware never
receives a light scene. With multiple Q units, select one explicitly:

```text
q status --id Q-386661B2F180
q lights blue --port COM9 --seconds 5
q watch --port /dev/ttyACM0
```

An explicit port is used for the first connection. Reconnection is pinned to the
verified ID and re-discovers its current port. It cannot silently switch to a
different Q. The last acknowledged scene is restored after reconnecting; no
scene is restored when watch/status did not set one. Reconnect attempts back off
for two seconds and normal input polls have bounded timeouts.

Only one process can own a port. Stop another CLI instance or serial monitor
before connecting. Do not run the Mac app and CLI against the same physical Q.

## Linux permissions

If opening `/dev/ttyACM0` reports permission denied, check ownership with
`ls -l /dev/ttyACM0` and your groups with `id`. Ubuntu commonly grants serial
access to the `dialout` group; an administrator can grant that membership, followed
by a new login. Do not make the device world-writable or run Q as root routinely.

WSL does not automatically expose a USB device connected to Windows. Test with
a device attached to Linux, or configure USB forwarding separately. A PTY test
validates the Linux adapter but does not establish physical USB support in WSL.

## Development and scope

```text
swift build --product q
swift test
swift run q status
```

`Scripts/test-portable-pty.py <path-to-q>` exercises the Linux native adapter with
a pseudo-terminal, including fragmented identity, gestures, heartbeat, scenes,
cleanup and competing processes. Unit tests cover framing bounds, invalid data,
acknowledgements, protocol rejection, device selection and reconnect identity.

No GUI, automatic firmware upgrade, background service, Meetings control or
agent integration is included. Packaging here is for development/hardware tests;
the end-user distribution work remains in P4. Physical button and unplug/replug
results must be recorded separately from simulator/CI results.

## Validation record

On 17 September 2026, [CI for `157d2ab`](https://github.com/frozono9/Q/actions/runs/35261259265)
passed 75 tests on each of Windows and Linux, 63 on Mac, the native Linux PTY
integration and the existing universal Mac build/package checks. CI produced
development ZIP/tar packages with their Swift runtime dependencies and checksums.

The Windows package ran on Windows 11 Home (10.0.26200) without Swift installed. Q
identified itself on COM9 as `Q-386661B2F180`, firmware `0.2.2`, protocol `1`.
The `test` command received acknowledgements for red, green, blue, white and
traffic scenes and exited successfully. A 90-second watch captured short press,
long press and release twice. Physically unplugging/replugging USB produced a
disconnect and successful reconnection to the same stable ID. A competing
`status` process was denied access while watch owned the port.

The Linux package ran on Ubuntu 24.04.3 under WSL without Swift installed and
passed the PTY integration using the packaged launcher. This exercises native
termios I/O, all five gesture messages, heartbeat, scene acknowledgements,
cleanup and exclusive access, but is not a physical Linux USB test.

The final code revision, [`de34b2a`](https://github.com/frozono9/Q/actions/runs/35262685101),
passed the same CI matrix and regenerated both packages. It writes each JSON
event directly to stdout so a consuming process receives it immediately; the
Linux PTY test now checks delivery while watch is still running. It also reports
failure to confirm the off scene during cleanup.

P1 is not fully signed off: physical USB on native Linux, hardware double/triple
press, suspend/resume and heartbeat-loss recovery still need recorded results.
Mac interactive hardware validation also remains pending. These packages are
experimental CLI clients; shared mode coordination, settings and UI are P2/P3.
