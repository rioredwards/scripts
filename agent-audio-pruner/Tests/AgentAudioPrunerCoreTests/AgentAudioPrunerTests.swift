import Foundation
import Testing
@testable import AgentAudioPrunerCore

@Test func keepsNewestFilesWithinBothCaps() {
    let files = [
        AudioFile(url: URL(fileURLWithPath: "/new.mp3"), size: 70, modifiedAt: Date(timeIntervalSince1970: 3)),
        AudioFile(url: URL(fileURLWithPath: "/middle.mp3"), size: 60, modifiedAt: Date(timeIntervalSince1970: 2)),
        AudioFile(url: URL(fileURLWithPath: "/old.mp3"), size: 30, modifiedAt: Date(timeIntervalSince1970: 1)),
    ]

    let plan = AgentAudioPruner.makePlan(files: files, maxBytes: 100, keepCount: 2)

    #expect(plan.kept.map { $0.url.lastPathComponent } == ["new.mp3", "old.mp3"])
    #expect(plan.removed.map { $0.url.lastPathComponent } == ["middle.mp3"])
    #expect(plan.keptBytes == 100)
}

@Test func countCapRemovesOlderFiles() {
    let files = (1...3).map {
        AudioFile(
            url: URL(fileURLWithPath: "/\($0).mp3"),
            size: 10,
            modifiedAt: Date(timeIntervalSince1970: TimeInterval($0))
        )
    }

    let plan = AgentAudioPruner.makePlan(files: files, maxBytes: 1_000, keepCount: 2)

    #expect(plan.kept.map { $0.url.lastPathComponent } == ["3.mp3", "2.mp3"])
    #expect(plan.removed.map { $0.url.lastPathComponent } == ["1.mp3"])
}

@Test func dryRunPlansAudioAndSidecarWithoutTrashing() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.writeAudio("new.mp3", bytes: 70, modifiedAt: 2)
    try fixture.writeAudio("old.mp3", bytes: 60, modifiedAt: 1)
    try fixture.writeSidecar("old.json", audio: "old.mp3")
    var trashed: [URL] = []
    let configuration = try PrunerConfiguration(
        directory: fixture.directory,
        maxBytes: 100,
        keepCount: 10,
        audioExtensions: ["mp3"]
    )
    let pruner = AgentAudioPruner(configuration: configuration) { trashed.append($0) }

    let result = try pruner.run(dryRun: true)

    #expect(result.plan.removed.map { $0.url.lastPathComponent } == ["old.mp3"])
    #expect(result.sidecarsRemoved == 1)
    #expect(trashed.isEmpty)
    #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("old.mp3").path))
}

@Test func mismatchedSidecarIsKeptWhenClaimedAudioRemains() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.writeAudio("kept.mp3", bytes: 10, modifiedAt: 2)
    try fixture.writeAudio("removed.mp3", bytes: 100, modifiedAt: 1)
    try fixture.writeSidecar("removed.json", audio: "kept.mp3")
    var trashed: [String] = []
    let configuration = try PrunerConfiguration(
        directory: fixture.directory,
        maxBytes: 50,
        keepCount: 10,
        audioExtensions: ["mp3"]
    )
    let pruner = AgentAudioPruner(configuration: configuration) { trashed.append($0.lastPathComponent) }

    let result = try pruner.run()

    #expect(result.sidecarsRemoved == 0)
    #expect(trashed == ["removed.mp3"])
}

@Test func invalidConfigurationFailsLoud() {
    #expect(throws: PrunerError.self) {
        try PrunerConfiguration(
            directory: URL(fileURLWithPath: "/audio"),
            maxBytes: 0,
            keepCount: 200,
            audioExtensions: ["mp3"]
        )
    }
}

private final class Fixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-audio-pruner-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func writeAudio(_ name: String, bytes: Int, modifiedAt: TimeInterval) throws {
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: modifiedAt)],
            ofItemAtPath: url.path
        )
    }

    func writeSidecar(_ name: String, audio: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["audio": audio])
        try data.write(to: directory.appendingPathComponent(name))
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
