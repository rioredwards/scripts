import Foundation

public struct PrunerConfiguration: Equatable {
    public let directory: URL
    public let maxBytes: Int64
    public let keepCount: Int
    public let audioExtensions: Set<String>

    public init(
        directory: URL,
        maxBytes: Int64,
        keepCount: Int,
        audioExtensions: Set<String>
    ) throws {
        guard maxBytes > 0 else { throw PrunerError.invalidConfiguration("maxBytes must be positive") }
        guard keepCount > 0 else { throw PrunerError.invalidConfiguration("keepCount must be positive") }
        guard !audioExtensions.isEmpty else {
            throw PrunerError.invalidConfiguration("audioExtensions must not be empty")
        }

        self.directory = directory.standardizedFileURL
        self.maxBytes = maxBytes
        self.keepCount = keepCount
        self.audioExtensions = Set(audioExtensions.map { $0.lowercased() })
    }

    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> PrunerConfiguration {
        let defaultBase = homeDirectory
            .appendingPathComponent("Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/agent-audio")
        let base = environment["AGENT_AUDIO_BASE_DIR"].map(URL.init(fileURLWithPath:)) ?? defaultBase
        let directory = environment["AGENT_AUDIO_FILE_DIR"].map(URL.init(fileURLWithPath:))
            ?? base.appendingPathComponent("recent")
        let maxMB = try positiveInteger(
            environment["AGENT_AUDIO_FILE_MAX_MB"] ?? "300",
            name: "AGENT_AUDIO_FILE_MAX_MB"
        )
        let keepCount = try positiveInteger(
            environment["AGENT_AUDIO_FILE_KEEP"] ?? "200",
            name: "AGENT_AUDIO_FILE_KEEP"
        )
        let (maxBytes, overflow) = Int64(maxMB).multipliedReportingOverflow(by: 1_048_576)
        guard !overflow else {
            throw PrunerError.invalidConfiguration("AGENT_AUDIO_FILE_MAX_MB is too large")
        }

        let extensions = Set(
            (environment["AGENT_AUDIO_FILE_PRUNE_EXTS"] ?? "mp3 aiff aif wav aac caf m4a")
                .split(whereSeparator: \Character.isWhitespace)
                .map { $0.lowercased() }
        )
        return try PrunerConfiguration(
            directory: directory,
            maxBytes: maxBytes,
            keepCount: keepCount,
            audioExtensions: extensions
        )
    }

    private static func positiveInteger(_ value: String, name: String) throws -> Int {
        guard let parsed = Int(value), parsed > 0 else {
            throw PrunerError.invalidConfiguration("\(name) must be a positive integer, got '\(value)'")
        }
        return parsed
    }
}

public struct AudioFile: Equatable {
    public let url: URL
    public let size: Int64
    public let modifiedAt: Date

    public init(url: URL, size: Int64, modifiedAt: Date) {
        self.url = url
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

public struct PrunePlan: Equatable {
    public let kept: [AudioFile]
    public let removed: [AudioFile]

    public var keptBytes: Int64 { kept.reduce(0) { $0 + $1.size } }
    public var freedBytes: Int64 { removed.reduce(0) { $0 + $1.size } }
}

public struct PruneResult: Equatable {
    public let plan: PrunePlan
    public let sidecarsRemoved: Int
    public let warnings: [String]
    public let dryRun: Bool

    public var summary: String {
        let prefix = dryRun ? "DRY RUN: " : ""
        return String(
            format: "%@kept %d audio files (%.1f MB), removed %d (%.1f MB), removed %d sidecars",
            prefix,
            plan.kept.count,
            Double(plan.keptBytes) / 1_048_576,
            plan.removed.count,
            Double(plan.freedBytes) / 1_048_576,
            sidecarsRemoved
        )
    }
}

public enum PrunerError: LocalizedError {
    case invalidConfiguration(String)
    case missingDirectory(URL)
    case unreadableDirectory(URL, Error)
    case missingMetadata(URL, String)
    case invalidSidecar(URL, String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return "invalid configuration: \(message)"
        case let .missingDirectory(url):
            return "audio directory does not exist: \(url.path)"
        case let .unreadableDirectory(url, error):
            return "cannot read audio directory \(url.path): \(error.localizedDescription)"
        case let .missingMetadata(url, field):
            return "missing \(field) metadata for \(url.path)"
        case let .invalidSidecar(url, message):
            return "invalid sidecar \(url.path): \(message)"
        }
    }
}

public final class AgentAudioPruner {
    public typealias TrashItem = (URL) throws -> Void

    private let configuration: PrunerConfiguration
    private let fileManager: FileManager
    private let trashItem: TrashItem

    public init(
        configuration: PrunerConfiguration,
        fileManager: FileManager = .default,
        trashItem: TrashItem? = nil
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        self.trashItem = trashItem ?? { url in
            var resultingURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        }
    }

    public static func makePlan(
        files: [AudioFile],
        maxBytes: Int64,
        keepCount: Int
    ) -> PrunePlan {
        let sorted = files.sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.url.lastPathComponent < $1.url.lastPathComponent
        }

        var kept: [AudioFile] = []
        var removed: [AudioFile] = []
        var total: Int64 = 0

        for file in sorted {
            let (nextTotal, overflow) = total.addingReportingOverflow(file.size)
            if !overflow, nextTotal <= maxBytes, kept.count < keepCount {
                kept.append(file)
                total = nextTotal
            } else {
                removed.append(file)
            }
        }
        return PrunePlan(kept: kept, removed: removed)
    }

    public func run(dryRun: Bool = false, verbose: Bool = false) throws -> PruneResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: configuration.directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw PrunerError.missingDirectory(configuration.directory)
        }

        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: configuration.directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: []
            )
        } catch {
            throw PrunerError.unreadableDirectory(configuration.directory, error)
        }

        let regularFiles = try urls.filter { url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true
        }
        let audioFiles = try regularFiles.compactMap { url -> AudioFile? in
            guard configuration.audioExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let size = values.fileSize else { throw PrunerError.missingMetadata(url, "size") }
            guard let modifiedAt = values.contentModificationDate else {
                throw PrunerError.missingMetadata(url, "modification date")
            }
            return AudioFile(url: url, size: Int64(size), modifiedAt: modifiedAt)
        }

        let plan = Self.makePlan(
            files: audioFiles,
            maxBytes: configuration.maxBytes,
            keepCount: configuration.keepCount
        )
        let removedAudioURLs = Set(plan.removed.map(\.url))
        let remainingFilenames = Set(
            regularFiles
                .filter { !removedAudioURLs.contains($0) }
                .map(\.lastPathComponent)
        )
        let remainingAudioStems = Set(
            plan.kept.map { $0.url.deletingPathExtension().lastPathComponent }
        )

        var sidecarsToRemove: [URL] = []
        var warnings: [String] = []
        for sidecar in regularFiles where sidecar.pathExtension.lowercased() == "json" {
            do {
                switch try sidecarClaim(sidecar) {
                case let .filename(filename):
                    if !remainingFilenames.contains(filename) { sidecarsToRemove.append(sidecar) }
                case .none:
                    if !remainingAudioStems.contains(sidecar.deletingPathExtension().lastPathComponent) {
                        sidecarsToRemove.append(sidecar)
                    }
                }
            } catch {
                warnings.append(error.localizedDescription)
            }
        }

        if verbose || dryRun {
            for warning in warnings { print("warning: \(warning)") }
            for url in sidecarsToRemove.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                print("  \(dryRun ? "would trash" : "trashing") sidecar \(url.lastPathComponent)")
            }
            for file in plan.removed {
                print("  \(dryRun ? "would trash" : "trashing") audio \(file.url.lastPathComponent)")
            }
        }

        if !dryRun {
            for sidecar in sidecarsToRemove.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                try trashItem(sidecar)
            }
            for file in plan.removed {
                try trashItem(file.url)
            }
        }

        return PruneResult(
            plan: plan,
            sidecarsRemoved: sidecarsToRemove.count,
            warnings: warnings,
            dryRun: dryRun
        )
    }

    private enum SidecarClaim {
        case filename(String)
        case none
    }

    private func sidecarClaim(_ url: URL) throws -> SidecarClaim {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PrunerError.invalidSidecar(url, error.localizedDescription)
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PrunerError.invalidSidecar(url, "malformed JSON")
        }
        guard let dictionary = object as? [String: Any] else {
            throw PrunerError.invalidSidecar(url, "top level is not an object")
        }
        guard let rawClaim = dictionary["audio"] else { return .none }
        guard let filename = rawClaim as? String,
              !filename.isEmpty,
              filename == URL(fileURLWithPath: filename).lastPathComponent,
              !filename.contains("/") else {
            throw PrunerError.invalidSidecar(url, "audio must be a filename")
        }
        return .filename(filename)
    }
}
