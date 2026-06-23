import Foundation

// Applies a skill update. Two lanes:
//  - .npmCli: launches the vendor updater (e.g. `npx impeccable skills update`,
//    `uipro update --ai claude`) via Process.
//  - .githubSingleFile: re-downloads SKILL.md through SkillInstaller (backup first).
//
// Security: this is the only place AgencyOS launches an external process. Defense
// in depth so a tampered manifest still cannot run an arbitrary binary:
//  - the executable name must be in `allowedExe`,
//  - it is resolved to an absolute path inside a fixed set of bin dirs,
//  - arguments are passed as an array (never a shell string -> no injection),
//  - args come from the manifest, never from scanned skill content.
enum SkillUpdater {
    struct Result: Sendable {
        var success: Bool
        var output: String
    }

    static let allowedExe: Set<String> = ["npx", "uipro", "npm", "node", "git"]

    static let searchDirs: [String] = [
        "\(NSHomeDirectory())/.npm-global/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin"
    ]

    static func resolve(_ exe: String) -> String? {
        guard allowedExe.contains(exe) else { return nil }
        for dir in searchDirs {
            let path = "\(dir)/\(exe)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    static func apply(_ source: SkillSource) async -> Result {
        switch source.kind {
        case .npmCli:           return await runCLI(source)
        case .githubSingleFile: return await reinstallSingleFile(source)
        case .plugin, .unknown: return Result(success: false, output: "No update path for this skill.")
        }
    }

    static let timeoutSeconds: Double = 120

    // Thread-safe accumulator for the process pipe (the readability handler runs
    // on a background queue while the launcher thread waits on the process).
    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
        var string: String { lock.lock(); defer { lock.unlock() }; return String(data: data, encoding: .utf8) ?? "" }
    }

    private static func runCLI(_ source: SkillSource) async -> Result {
        guard let exe = source.updateExe, let path = resolve(exe) else {
            return Result(success: false,
                          output: "Updater '\(source.updateExe ?? "?")' not found or not allowed.")
        }
        let args = source.updateArgs
        let timeout = timeoutSeconds
        // Bridge the blocking runner onto a background queue; the synchronous
        // DispatchSemaphore watchdog below is not permitted in an async context.
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runProcessSync(path: path, args: args, exe: exe, timeout: timeout))
            }
        }
    }

    // Synchronous process runner with an output drain + timeout watchdog. Runs on
    // a background queue (NOT an async context), so the semaphore wait is allowed.
    private static func runProcessSync(path: String, args: [String], exe: String, timeout: Double) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        // Append the inherited PATH (and the resolved exe's own dir) so a
        // GUI-launched app can still find node / version-manager shims that are
        // not in our fixed searchDirs.
        var env = ProcessInfo.processInfo.environment
        let exeDir = (path as NSString).deletingLastPathComponent
        let inherited = env["PATH"] ?? ""
        env["PATH"] = (([exeDir] + searchDirs).joined(separator: ":"))
            + (inherited.isEmpty ? "" : ":" + inherited)
        process.environment = env

        // Close stdin so an interactive prompt ("Ok to proceed?") reads EOF and
        // aborts instead of blocking the update forever.
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Drain continuously (avoids the 64KB pipe-buffer deadlock) into a
        // lock-guarded box; signal completion via the termination handler.
        let box = OutputBox()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { box.append(chunk) }
        }
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return Result(success: false, output: "Failed to launch \(exe): \(error.localizedDescription)")
        }

        // Watchdog: terminate if it overruns the timeout (network stall or a
        // prompt that stdin-EOF did not resolve).
        let timedOut = done.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 5)
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        let output = box.string
        let success = !timedOut && process.terminationStatus == 0
        return Result(success: success,
                      output: timedOut ? "Timed out after \(Int(timeout))s.\n" + output : output)
    }

    private static func reinstallSingleFile(_ source: SkillSource) async -> Result {
        let dir = SkillScanner.skillsURL.appendingPathComponent(source.folder)
        let skillFile = dir.appendingPathComponent("SKILL.md")
        if FileManager.default.fileExists(atPath: skillFile.path) {
            _ = ConfigWriter.makeBackup(skillFile)
        }
        let result = await SkillInstaller.install(repo: source.ref, explicitURL: nil, folder: source.folder)
        switch result {
        case .installed:        return Result(success: true, output: "Updated \(source.folder) from \(source.ref).")
        case .notFound:         return Result(success: false, output: "No SKILL.md found upstream.")
        case .failed(let msg):  return Result(success: false, output: "Update failed: \(msg)")
        }
    }
}
