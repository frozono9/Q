import Darwin
import Foundation

// Claude Code sends rich hook payloads on stdin. Q intentionally persists only
// lifecycle metadata and discards prompts, tool inputs, commands, and output.
let input = FileHandle.standardInput.readDataToEndOfFile()
guard let payload = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
      let event = payload["hook_event_name"] as? String,
      let sessionID = payload["session_id"] as? String else {
    exit(0)
}

let environment = ProcessInfo.processInfo.environment
var record: [String: Any] = [
    "timestamp": ISO8601DateFormatter().string(from: Date()),
    "event": event,
    "session_id": sessionID
]
for key in ["agent_id", "agent_type", "cwd", "transcript_path"] {
    if let value = payload[key] as? String {
        record[key] = value
    }
}
if let bundleID = environment["__CFBundleIdentifier"] {
    record["terminal_bundle_id"] = bundleID
}
if let terminal = environment["TERM_PROGRAM"] {
    record["terminal_program"] = terminal
}

guard var encoded = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else {
    exit(0)
}
encoded.append(0x0A)

let support = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Q", isDirectory: true)
try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
let logURL = support.appendingPathComponent("claude-events.jsonl")
if let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
   let size = (attributes[.size] as? NSNumber)?.uint64Value,
   size > 5 * 1_024 * 1_024 {
    let previous = support.appendingPathComponent("claude-events.previous.jsonl")
    try? FileManager.default.removeItem(at: previous)
    try? FileManager.default.moveItem(at: logURL, to: previous)
}

let descriptor = open(logURL.path, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR)
guard descriptor >= 0 else { exit(0) }
defer { close(descriptor) }
encoded.withUnsafeBytes { bytes in
    guard let base = bytes.baseAddress else { return }
    _ = write(descriptor, base, bytes.count)
}
