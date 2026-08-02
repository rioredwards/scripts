import AgentAudioPrunerCore
import Darwin
import Foundation

private struct Options {
    var dryRun = false
    var verbose = false

    static func parse(_ arguments: ArraySlice<String>) throws -> Options {
        var options = Options()
        for argument in arguments {
            switch argument {
            case "-n", "--dry-run":
                options.dryRun = true
                options.verbose = true
            case "-v", "--verbose":
                options.verbose = true
            case "-h", "--help":
                print("usage: agent-audio-prune [-n|--dry-run] [-v|--verbose]")
                exit(EXIT_SUCCESS)
            default:
                throw PrunerError.invalidConfiguration("unknown argument '\(argument)'")
            }
        }
        return options
    }
}

private struct LogFile {
    let url: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        url = homeDirectory.appendingPathComponent(".cache/note-on-turn/audio-prune.log")
    }

    func append(_ message: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\(timestamp()) \(message)\n".utf8))
    }
}

private func timestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private let log = LogFile()
do {
    let options = try Options.parse(CommandLine.arguments.dropFirst())
    let configuration = try PrunerConfiguration.load()
    let result = try AgentAudioPruner(configuration: configuration).run(
        dryRun: options.dryRun,
        verbose: options.verbose
    )
    print(result.summary)
    if !options.dryRun { try log.append(result.summary) }
} catch {
    let message = "agent-audio-prune: \(error.localizedDescription)"
    try? log.append("ERROR \(message)")
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(EXIT_FAILURE)
}
