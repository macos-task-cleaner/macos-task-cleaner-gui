import Foundation
import AppKit

public class MTCBridge {
    public static let shared = MTCBridge()

    private var cachedBinaryPath: String?
    private let lock = NSLock()

    public func findMTCBinary() -> String? {
        lock.lock()
        if let cached = cachedBinaryPath, FileManager.default.isExecutableFile(atPath: cached) {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let bundleInternal = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mtc").path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            bundleInternal,
            "\(home)/.local/bin/mtc",
            "\(home)/.local/bin/taskcleaner",
            "/usr/local/bin/mtc",
            "/opt/homebrew/bin/mtc",
            "/usr/local/bin/taskcleaner"
        ]

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                lock.lock()
                cachedBinaryPath = path
                lock.unlock()
                return path
            }
        }

        // Try `which mtc`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["mtc"]
        let pipe = Pipe()
        process.standardOutput = pipe

        if let _ = try? process.run() {
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty && FileManager.default.isExecutableFile(atPath: output) {
                lock.lock()
                cachedBinaryPath = output
                lock.unlock()
                return output
            }
        }

        return nil
    }

    public func fetchSummary() -> DryRunSummary? {
        guard let mtc = findMTCBinary() else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: mtc)
        process.arguments = ["--json", "--dry-run"]
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let decoder = JSONDecoder()
            return try decoder.decode(DryRunSummary.self, from: data)
        } catch {
            return nil
        }
    }

    public func executeClean(force: Bool = false, purge: Bool = false) -> Bool {
        guard let mtc = findMTCBinary() else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: mtc)
        var args = ["--execute"]
        if force {
            args.append("--force")
        }
        if purge {
            args.append("--purge")
        }
        process.arguments = args

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func addToWhitelist(identifier: String) -> Bool {
        guard let mtc = findMTCBinary() else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: mtc)
        process.arguments = ["-a", identifier]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func removeFromWhitelist(identifier: String) -> Bool {
        guard let mtc = findMTCBinary() else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: mtc)
        process.arguments = ["-r", identifier]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func terminateProcess(pid: Int, force: Bool = false) -> Bool {
        guard let mtc = findMTCBinary() else {
            if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
                _ = app.terminate()
                usleep(400_000)
                if !app.isTerminated {
                    _ = app.forceTerminate()
                }
                return true
            }
            return kill(pid_t(pid), SIGKILL) == 0
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: mtc)
        var args = ["-t", String(pid)]
        if force {
            args.append("--force")
        }
        process.arguments = args

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func openConfigFile() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let mtcConfig = home.appendingPathComponent(".config/mtc/config.toml")
        let legacyConfig = home.appendingPathComponent(".config/taskcleaner/config.toml")

        let target = FileManager.default.fileExists(atPath: mtcConfig.path) ? mtcConfig : legacyConfig

        if FileManager.default.fileExists(atPath: target.path) {
            NSWorkspace.shared.open(target)
        } else {
            // Run `mtc --init-config` to generate it
            if let mtc = findMTCBinary() {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: mtc)
                process.arguments = ["--init-config"]
                try? process.run()
                process.waitUntilExit()
            }
            NSWorkspace.shared.open(mtcConfig)
        }
    }
}
