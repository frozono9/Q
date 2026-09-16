# Q 0.3.0 private beta

Q 0.3.0 is the first beta intended for testing on other Macs. It pairs with Q
firmware 0.2.3.

## What is new

- Claude Code integration using official lifecycle hooks.
- Combined Codex and Claude Code multi-agent LED slots.
- Permission requests appear as Q's blue Needs You state.
- Bounded recent-activity diagnostics with confirmed, unconfirmed, and failed outcomes.
- Hardened meeting push-to-talk lifecycle and provider retention.
- Ordered, compact Settings and inactivity-aware menu-bar popover.
- Reproducible universal DMG verification and a formal physical reliability matrix.

## Claude Code privacy

The bundled `QClaudeHook` stores only event name, session identifier, project
directory, timestamp, and terminal identity. It deliberately discards prompts,
commands, tool inputs, responses, and transcript content. Connecting Claude Code
creates `~/.claude/settings.json.q-backup` before merging Q's hook entries.

## Installation

1. Open `Q-0.3.0.dmg` and drag Q into Applications.
2. Launch Q. If macOS blocks the private beta, use System Settings → Privacy &
   Security → Open Anyway.
3. Complete Set up Q and grant Accessibility.
4. In Settings → Connected apps, connect Claude Code if it is installed.
5. Connect the physical Q over USB-C and install firmware 0.2.3 if offered.

## Known limits

- This private build is not Apple-notarized unless the DMG was produced with a
  Developer ID and `Q_NOTARY_PROFILE`.
- Q can bring Claude Code's terminal application forward, but terminal APIs do
  not guarantee focusing an exact tab on every terminal.
- Some meeting providers can accept a mute shortcut without exposing the final
  microphone state. Q labels those results as unconfirmed rather than successful.
