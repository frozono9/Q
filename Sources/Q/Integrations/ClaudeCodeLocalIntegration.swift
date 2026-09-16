import AppKit
import Foundation
import OSLog
import QCore

struct ClaudeCodeIntegrationSnapshot: Sendable {
    var sessions: [QAgentSession]
    var isInstalled: Bool
    var isConnected: Bool
}

enum ClaudeCodeHookConfigurationError: LocalizedError {
    case helperUnavailable
    case invalidSettings

    var errorDescription: String? {
        switch self {
        case .helperUnavailable: "Install Q in Applications before connecting Claude Code."
        case .invalidSettings: "Claude Code settings could not be read safely."
        }
    }
}

struct ClaudeCodeHookInstaller {
    static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PostToolUseFailure", "PermissionRequest", "PermissionDenied", "Stop", "StopFailure",
        "SubagentStart", "SubagentStop", "SessionEnd"
    ]

    private let fileManager = FileManager.default

    var settingsURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/QClaudeHook")
    }

    var isInstalled: Bool {
        let home = fileManager.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ].contains(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    var isConfigured: Bool {
        guard let root = loadSettings(), let hooks = root["hooks"] as? [String: Any] else { return false }
        return Self.events.allSatisfy { event in
            guard let entries = hooks[event] as? [[String: Any]] else { return false }
            return entries.contains(where: Self.containsQHook)
        }
    }

    func install() throws {
        guard fileManager.isExecutableFile(atPath: helperURL.path) else {
            throw ClaudeCodeHookConfigurationError.helperUnavailable
        }
        let settingsExist = fileManager.fileExists(atPath: settingsURL.path)
        guard !settingsExist || loadSettings() != nil else {
            throw ClaudeCodeHookConfigurationError.invalidSettings
        }
        var root = loadSettings() ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let quotedCommand = "\"\(helperURL.path)\""

        for event in Self.events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            guard !entries.contains(where: Self.containsQHook) else { continue }
            entries.append([
                "matcher": "",
                "hooks": [["type": "command", "command": quotedCommand]]
            ])
            hooks[event] = entries
        }
        root["hooks"] = hooks
        try save(root, preserveOriginalBackup: true)
    }

    func uninstall() throws {
        guard !fileManager.fileExists(atPath: settingsURL.path) || loadSettings() != nil else {
            throw ClaudeCodeHookConfigurationError.invalidSettings
        }
        guard var root = loadSettings() else { return }
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for event in Self.events {
            guard let entries = hooks[event] as? [[String: Any]] else { continue }
            let retained = entries.filter { !Self.containsQHook($0) }
            if retained.isEmpty { hooks.removeValue(forKey: event) }
            else { hooks[event] = retained }
        }
        root["hooks"] = hooks
        try save(root, preserveOriginalBackup: false)
    }

    private func loadSettings() -> [String: Any]? {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: settingsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return root
    }

    private func save(_ root: [String: Any], preserveOriginalBackup: Bool) throws {
        guard JSONSerialization.isValidJSONObject(root) else {
            throw ClaudeCodeHookConfigurationError.invalidSettings
        }
        let directory = settingsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if preserveOriginalBackup, fileManager.fileExists(atPath: settingsURL.path) {
            let backup = directory.appendingPathComponent("settings.json.q-backup")
            if !fileManager.fileExists(atPath: backup.path) {
                try? fileManager.copyItem(at: settingsURL, to: backup)
            }
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
    }

    private static func containsQHook(_ value: Any) -> Bool {
        if let string = value as? String { return string.contains("QClaudeHook") }
        if let array = value as? [Any] { return array.contains(where: containsQHook) }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains(where: containsQHook)
        }
        return false
    }
}

actor ClaudeCodeEventScanner {
    private let fileManager = FileManager.default
    private let installer = ClaudeCodeHookInstaller()
    private let activeRetention: TimeInterval = 2 * 60 * 60
    private let completedRetention: TimeInterval = 10
    private let errorRetention: TimeInterval = 5 * 60
    private let maxTailBytes: UInt64 = 2 * 1_024 * 1_024

    private var eventLogURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Q/claude-events.jsonl")
    }

    func scan(now: Date = .now) -> ClaudeCodeIntegrationSnapshot {
        let installed = installer.isInstalled
        let connected = installer.isConfigured
        guard connected else {
            return ClaudeCodeIntegrationSnapshot(sessions: [], isInstalled: installed, isConnected: false)
        }
        let events = readRecentEvents()
        var latestByIdentity: [String: ClaudeHookEvent] = [:]
        for event in events {
            let identity = event.agentID.map { "\(event.sessionID):\($0)" } ?? event.sessionID
            if latestByIdentity[identity].map({ $0.date < event.date }) ?? true {
                latestByIdentity[identity] = event
            }
        }
        let sessions = latestByIdentity.compactMap { identity, event -> QAgentSession? in
            guard let state = state(for: event.event) else { return nil }
            let age = now.timeIntervalSince(event.date)
            if state == .done, age > completedRetention { return nil }
            if (state == .error || state == .failed), age > errorRetention { return nil }
            if age > activeRetention { return nil }
            let project = event.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            let agentSuffix = event.agentType.map { " · \($0)" } ?? ""
            var context: [String: String] = ["sessionID": event.sessionID]
            if let cwd = event.cwd { context["cwd"] = cwd }
            if let transcript = event.transcriptPath { context["transcriptPath"] = transcript }
            if let bundleID = terminalBundleID(for: event) { context["terminalBundleID"] = bundleID }
            return QAgentSession(
                id: identity,
                source: "Claude Code",
                displayName: "\(project?.isEmpty == false ? project! : "Claude")\(agentSuffix)",
                state: state,
                context: context,
                updatedAt: event.date
            )
        }
        return ClaudeCodeIntegrationSnapshot(
            sessions: sessions,
            isInstalled: installed,
            isConnected: connected
        )
    }

    private func state(for event: String) -> QState? {
        switch event {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionDenied", "SubagentStart": .working
        case "PermissionRequest": .permissionRequired
        case "Stop", "SubagentStop": .done
        case "StopFailure": .failed
        default: nil
        }
    }

    private func terminalBundleID(for event: ClaudeHookEvent) -> String? {
        if let bundleID = event.terminalBundleID, bundleID != "app.q" { return bundleID }
        switch event.terminalProgram?.lowercased() {
        case "apple_terminal": return "com.apple.Terminal"
        case "iterm.app": return "com.googlecode.iterm2"
        case "vscode": return "com.microsoft.VSCode"
        case "warpterminal": return "dev.warp.Warp-Stable"
        case "ghostty": return "com.mitchellh.ghostty"
        default: return nil
        }
    }

    private func readRecentEvents() -> [ClaudeHookEvent] {
        guard let handle = try? FileHandle(forReadingFrom: eventLogURL) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > maxTailBytes ? size - maxTailBytes : 0
        try? handle.seek(toOffset: offset)
        var data = (try? handle.readToEnd()) ?? Data()
        if offset > 0, let newline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(...newline)
        }
        return data.split(separator: 0x0A).compactMap { line in
            try? JSONDecoder().decode(ClaudeHookEvent.self, from: Data(line))
        }
    }
}

private struct ClaudeHookEvent: Decodable {
    var event: String
    var sessionID: String
    var agentID: String?
    var agentType: String?
    var cwd: String?
    var transcriptPath: String?
    var terminalBundleID: String?
    var terminalProgram: String?
    var timestamp: String

    var date: Date {
        ISO8601DateFormatter().date(from: timestamp) ?? .distantPast
    }

    enum CodingKeys: String, CodingKey {
        case event, timestamp, cwd
        case sessionID = "session_id"
        case agentID = "agent_id"
        case agentType = "agent_type"
        case transcriptPath = "transcript_path"
        case terminalBundleID = "terminal_bundle_id"
        case terminalProgram = "terminal_program"
    }
}

@MainActor
final class ClaudeCodeLocalIntegration {
    private let scanner = ClaudeCodeEventScanner()
    private let installer = ClaudeCodeHookInstaller()
    private let logger = Logger(subsystem: "app.q", category: "claude-code-integration")
    private var monitoringTask: Task<Void, Never>?

    func start(onUpdate: @escaping @MainActor @Sendable (ClaudeCodeIntegrationSnapshot) -> Void) {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [scanner] in
            while !Task.isCancelled {
                onUpdate(await scanner.scan())
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func installHooks() throws {
        try installer.install()
        logger.notice("Connected Claude Code hooks")
    }

    func removeHooks() throws {
        try installer.uninstall()
        logger.notice("Removed Q from Claude Code hooks")
    }

    func focus(_ session: QAgentSession) {
        if let bundleID = session.context["terminalBundleID"],
           let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            application.activate(options: [.activateAllWindows])
            return
        }
        if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: terminalURL, configuration: .init())
        }
    }
}
