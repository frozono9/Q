# Q beta reliability matrix

Run this matrix on every beta candidate. Record the Mac, macOS version, Q app
version, firmware version, device identifier, provider version, result, and a
copied Q diagnostic report. “Pass” means the external application visibly
reached the requested state; sending a shortcut without confirmation is not a
pass.

## Button and device lifecycle

| Scenario | Expected result |
| --- | --- |
| Single press in every mode | Exactly one contextual action and one confirmation |
| Double press | Exactly one mode advance; no single action leaks through |
| Triple press | One new Codex task; no mode change or single action |
| Long press and release | One begin and one release against the same target |
| Duplicate long event | Ignored while a hold is active |
| Release without long | No action and no stale state |
| Disconnect while held | Release state is cleared; reconnect remains usable |
| Reconnect Q | Red waiting sequence, handshake, three green pulses, current scene restored |
| Mac sleep/wake | Q reconnects without duplicated button events |
| Rapid ten-gesture sequence | Events remain ordered and the app stays responsive |

## Meetings — repeat for Discord, Zoom, Google Meet, and Teams

| Starting condition | Action | Expected result |
| --- | --- | --- |
| App closed | Single/hold | Honest unavailable result; no other app receives shortcut |
| App open, no call | Single/hold | No false active-call state |
| Active and muted | Single | Unmuted and confirmed, or explicitly unconfirmed |
| Active and unmuted | Single | Muted and confirmed, or explicitly unconfirmed |
| Active and muted | Hold | Unmuted only while held, then muted |
| Active and unmuted | Hold | Remains usable and ends muted |
| Another app frontmost | Single/hold | Correct provider receives the action |
| User manually toggles mute | Observe | Q converges to the real state |
| Call ends during hold | Release | No late unmute; unavailable/failed is reported |
| Provider changed during hold | Release | Original provider is muted; new provider is untouched |
| Accessibility removed | Any control | Permission required; never claims success |
| Two providers active | Auto | Most recent active call wins deterministically |
| Two providers active | Pinned | Only the pinned provider is controlled |

## AI agents

| Scenario | Expected result |
| --- | --- |
| One Codex task working | Full-device amber chase |
| One Claude Code task working | Full-device amber chase |
| Codex + Claude working | One fading amber slot per task |
| Permission request | Blue attention state and exact source shown |
| One of two tasks finishes | Finished slot disappears after retention; remaining task becomes full-device working |
| Task error | Red error state; copied diagnostics identify source without content |
| Press on Codex task | Exact Codex task opens |
| Press on Claude task | Its terminal application comes forward |
| Claude hooks removed | Claude sessions disappear; Codex is unaffected |

## Distribution and upgrade

| Scenario | Expected result |
| --- | --- |
| Fresh Mac, DMG | Drag Q to Applications and launch with documented Open Anyway step |
| First launch | Guided device, Accessibility, Codex, Claude Code, and meeting checks |
| Existing preferences | Upgrade preserves name, brightness, modes, and provider pin |
| Firmware 0.2.2 | In-app update reaches and verifies firmware 0.2.3 |
| Firmware update interrupted | Clear retry/recovery path; app does not claim success |
| Copy report | Contains versions, permissions, integrations, and recent technical events only |

## Release evidence

For each candidate, retain:

- the exact commit and DMG SHA-256;
- `sh Scripts/run-reliability-checks.sh` output;
- one completed matrix per tester/Mac;
- known unconfirmed-provider behavior;
- whether the artifact is ad-hoc signed, Developer ID signed, and/or notarized.
