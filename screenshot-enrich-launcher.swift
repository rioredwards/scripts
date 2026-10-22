// A stable app identity for the background worker's iCloud permission.
import Foundation
let worker = Process()
worker.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
worker.arguments = Array(CommandLine.arguments.dropFirst())
do {
    try worker.run()
    worker.waitUntilExit()
    exit(worker.terminationStatus)
} catch {
    FileHandle.standardError.write(Data("Screenshot Enrich: \(error)\n".utf8))
    exit(1)
}
