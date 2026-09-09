import Foundation
import Testing
@testable import QCore

@Suite("Codex activity state resolver")
struct QCodexActivityResolverTests {
    @Test func mapsAnActiveTurnToWorking() {
        #expect(resolve([.started]) == .working)
    }

    @Test func aPendingApprovalTakesPrecedenceOverEarlierWork() {
        #expect(resolve([.started, .needsUser]) == .waitingForUser)
    }

    @Test func resumingAfterInputReturnsToWorking() {
        #expect(resolve([.started, .needsUser, .resumed]) == .working)
    }

    @Test func mapsTerminalEvents() {
        #expect(resolve([.started, .completed]) == .done)
        #expect(resolve([.started, .failed]) == .error)
    }

    @Test func recognizesAPlainFinalQuestionAsUserInput() {
        #expect(
            QCodexPromptClassifier.requestsUserInput(
                "Should the next Meetings integration be Zoom or Google Meet?"
            )
        )
        #expect(QCodexPromptClassifier.requestsUserInput("I need your input before continuing."))
        #expect(!QCodexPromptClassifier.requestsUserInput("Discord support is now complete."))
    }

    @Test func taskCompletionDoesNotEraseAnUnansweredQuestion() {
        let question = QCodexActivityEvent(kind: .needsUser, date: Date(timeIntervalSince1970: 1))
        let completion = QCodexActivityEvent(kind: .completed, date: Date(timeIntervalSince1970: 2))
        let reply = QCodexActivityEvent(kind: .resumed, date: Date(timeIntervalSince1970: 3))

        #expect(!QCodexActivityResolver.shouldReplace(question, with: completion))
        #expect(QCodexActivityResolver.shouldReplace(question, with: reply))
    }

    @Test func discoversAResumedTaskInsideItsOriginalDateDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("q-codex-discovery-\(UUID().uuidString)", isDirectory: true)
        let oldDirectory = root
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("01", isDirectory: true)
            .appendingPathComponent("02", isDirectory: true)
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let resumed = oldDirectory.appendingPathComponent("resumed.jsonl")
        let stale = oldDirectory.appendingPathComponent("stale.jsonl")
        try Data("{}\n".utf8).write(to: resumed)
        try Data("{}\n".utf8).write(to: stale)

        let now = Date(timeIntervalSince1970: 10_000)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: resumed.path)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-10_000)],
            ofItemAtPath: stale.path
        )

        let files = QCodexSessionDiscovery.recentRolloutFiles(
            in: root,
            now: now,
            activeWithin: 7_200
        )
        #expect(files.count == 1)
        #expect(files.first?.resolvingSymlinksInPath() == resumed.resolvingSymlinksInPath())
    }

    private func resolve(_ kinds: [QCodexActivityKind]) -> QState? {
        let base = Date(timeIntervalSince1970: 1_000)
        return QCodexActivityResolver.state(
            for: kinds.enumerated().map {
                QCodexActivityEvent(kind: $0.element, date: base.addingTimeInterval(Double($0.offset)))
            }
        )
    }
}
