import Foundation
import AppKit

public enum CliInstallLocation: String, CaseIterable, Identifiable {
    case userLocalBin = "user_local_bin"
    case systemUsrLocalBin = "system_usr_local_bin"

    public var id: String { rawValue }

    public var directoryURL: URL {
        switch self {
        case .userLocalBin:
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
        case .systemUsrLocalBin:
            return URL(fileURLWithPath: "/usr/local/bin")
        }
    }

    public var mtcSymlinkURL: URL {
        directoryURL.appendingPathComponent("mtc")
    }

    public var taskcleanerSymlinkURL: URL {
        directoryURL.appendingPathComponent("taskcleaner")
    }
}

public enum CliStatus: Equatable {
    case notInstalled
    case installed(location: CliInstallLocation, destinationPath: String, isInPath: Bool)
    case broken(location: CliInstallLocation, errorDescription: String)
}

public enum TerminalEmulator: String, CaseIterable, Identifiable {
    case ghostty = "Ghostty"
    case iterm2 = "iTerm2"
    case warp = "Warp"
    case alacritty = "Alacritty"
    case kitty = "kitty"
    case appleTerminal = "Terminal"

    public var id: String { rawValue }

    public var bundleIdentifier: String {
        switch self {
        case .ghostty: return "com.mitchellh.ghostty"
        case .iterm2: return "com.googlecode.iterm2"
        case .warp: return "dev.warp.Warp-Stable"
        case .alacritty: return "org.alacritty"
        case .kitty: return "net.kovidgoyal.kitty"
        case .appleTerminal: return "com.apple.Terminal"
        }
    }

    public var isInstalled: Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    public var isRunning: Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    public var displayName: String {
        switch self {
        case .ghostty: return "Ghostty"
        case .iterm2: return "iTerm2"
        case .warp: return "Warp"
        case .alacritty: return "Alacritty"
        case .kitty: return "Kitty"
        case .appleTerminal: return "Terminal"
        }
    }
}

public final class CliIntegrationManager {
    public static let shared = CliIntegrationManager()

    private let preferredTerminalKey = "TaskCleaner_PreferredTerminal"

    private init() {}

    /// 获取系统中已安装的终端模拟器列表
    public var installedTerminals: [TerminalEmulator] {
        let all = TerminalEmulator.allCases.filter { $0.isInstalled }
        return all.isEmpty ? [.appleTerminal] : all
    }

    /// 获取用户偏好或自动探测的最佳终端
    public var preferredTerminal: TerminalEmulator {
        get {
            // 1. 用户手动设置的偏好
            if let saved = UserDefaults.standard.string(forKey: preferredTerminalKey),
               let emulator = TerminalEmulator(rawValue: saved),
               emulator.isInstalled {
                return emulator
            }

            // 2. LaunchServices 默认关联感知 (检测用户是否将 .command 或终端脚本默认关联到某个终端)
            let tempCommandUrl = URL(fileURLWithPath: "/tmp/detect_term.command")
            if let handlerUrl = NSWorkspace.shared.urlForApplication(toOpen: tempCommandUrl),
               let bundle = Bundle(url: handlerUrl),
               let bundleId = bundle.bundleIdentifier {
                for emulator in TerminalEmulator.allCases {
                    if emulator.bundleIdentifier == bundleId && emulator.isInstalled {
                        return emulator
                    }
                }
            }

            // 3. 运行态感知：检测当前是否已有特定第三方终端正在运行
            for emulator in installedTerminals {
                if emulator.isRunning && emulator != .appleTerminal {
                    return emulator
                }
            }

            // 3. 优先级探测（优先现代第三方终端：Ghostty -> iTerm2 -> Warp -> Alacritty -> Kitty -> Terminal）
            let priorityOrder: [TerminalEmulator] = [.ghostty, .iterm2, .warp, .alacritty, .kitty, .appleTerminal]
            for emulator in priorityOrder {
                if emulator.isInstalled {
                    return emulator
                }
            }

            return .appleTerminal
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: preferredTerminalKey)
        }
    }

    public func setPreferredTerminal(_ emulator: TerminalEmulator) {
        self.preferredTerminal = emulator
    }

    /// 检测当前系统 PATH 中是否能直接寻址到指定的目录
    public func isLocationInPath(_ location: CliInstallLocation) -> Bool {
        let dirPath = location.directoryURL.path
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let parts = envPath.split(separator: ":").map { String($0) }
        if parts.contains(dirPath) {
            return true
        }

        // 进一步检查 ~/.zshrc 或 ~/.bash_profile
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let zshrc = "\(home)/.zshrc"
        if let content = try? String(contentsOfFile: zshrc, encoding: .utf8) {
            if content.contains(".local/bin") {
                return true
            }
        }
        return false
    }

    /// 判定目标目录当前用户是否拥有写入权限
    public func isLocationWritable(_ location: CliInstallLocation) -> Bool {
        let fileManager = FileManager.default
        let path = location.directoryURL.path
        if fileManager.fileExists(atPath: path) {
            return fileManager.isWritableFile(atPath: path)
        }
        // 如果目录尚不存在，检测其父目录写入权限
        let parent = location.directoryURL.deletingLastPathComponent().path
        return fileManager.isWritableFile(atPath: parent)
    }

    /// 定位当前应用内嵌或本地已编译的 mtc 二进制引擎实体
    public func locateEmbeddedMtcBinary() -> String? {
        let fileManager = FileManager.default

        // 1. 当前运行 App 包内 Bundle 内部 (如打包后运行)
        let bundleInternal = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mtc").path
        if fileManager.isExecutableFile(atPath: bundleInternal) {
            return bundleInternal
        }

        // 2. 标准 /Applications/TaskCleaner.app 安装包内
        let standardApp = "/Applications/TaskCleaner.app/Contents/MacOS/mtc"
        if fileManager.isExecutableFile(atPath: standardApp) {
            return standardApp
        }

        // 3. 项目相对构建目录 (针对本地开发环境)
        let parentDir = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().path
        let localCliBuilds = [
            "\(parentDir)/macos-task-cleaner-cli/target/release/mtc",
            "\(parentDir)/macos-task-cleaner-cli/dist/arm64/mtc",
            "/Users/don/work/git/macos-task-cleaner-cli/target/release/mtc"
        ]
        for candidate in localCliBuilds {
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // 4. MTCBridge 扫描
        if let found = MTCBridge.shared.findMTCBinary() {
            // 排除自身软链接路径，避免循环引用
            if !found.hasSuffix("/.local/bin/mtc") && !found.hasSuffix("/usr/local/bin/mtc") {
                return found
            }
        }

        return nil
    }

    /// 检测当前 mtc 命令行工具的安装与软链接健康状态
    public func detectCliStatus() -> CliStatus {
        let fileManager = FileManager.default

        for location in CliInstallLocation.allCases {
            let mtcSymlink = location.mtcSymlinkURL.path
            var isDir: ObjCBool = false
            let exists = fileManager.fileExists(atPath: mtcSymlink, isDirectory: &isDir)

            let isSymlink = (try? fileManager.destinationOfSymbolicLink(atPath: mtcSymlink)) != nil

            if exists || isSymlink {
                do {
                    let dest = try fileManager.destinationOfSymbolicLink(atPath: mtcSymlink)
                    // 解析真实路径
                    let resolvedUrl = URL(fileURLWithPath: dest, relativeTo: location.directoryURL).standardized
                    if fileManager.isExecutableFile(atPath: resolvedUrl.path) {
                        let inPath = isLocationInPath(location)
                        return .installed(location: location, destinationPath: resolvedUrl.path, isInPath: inPath)
                    } else {
                        return .broken(location: location, errorDescription: "目标实体二进制不存在或不可执行: \(resolvedUrl.path)")
                    }
                } catch {
                    if fileManager.isExecutableFile(atPath: mtcSymlink) {
                        let inPath = isLocationInPath(location)
                        return .installed(location: location, destinationPath: mtcSymlink, isInPath: inPath)
                    }
                    return .broken(location: location, errorDescription: error.localizedDescription)
                }
            }
        }

        return .notInstalled
    }

    /// 创建或重设 mtc 及 taskcleaner 软链接
    @discardableResult
    public func installSymlink(to location: CliInstallLocation) throws -> (symlinkPath: String, isInPath: Bool) {
        guard let sourceBinary = locateEmbeddedMtcBinary() else {
            throw NSError(
                domain: "TaskCleanerCLI",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "未找到内置 mtc 引擎可执行文件，请确认应用安装完整。"]
            )
        }

        let fileManager = FileManager.default
        let dirURL = location.directoryURL

        if !fileManager.fileExists(atPath: dirURL.path) {
            try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        }

        let targets = [location.mtcSymlinkURL, location.taskcleanerSymlinkURL]
        for target in targets {
            let path = target.path
            if fileManager.fileExists(atPath: path) || (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil {
                try? fileManager.removeItem(at: target)
            }
            try fileManager.createSymbolicLink(at: target, withDestinationURL: URL(fileURLWithPath: sourceBinary))
        }

        let inPath = isLocationInPath(location)
        return (location.mtcSymlinkURL.path, inPath)
    }

    /// 从系统中移除已创建的软链接
    public func uninstallSymlinks() throws {
        let fileManager = FileManager.default
        for location in CliInstallLocation.allCases {
            let targets = [location.mtcSymlinkURL, location.taskcleanerSymlinkURL]
            for target in targets {
                if fileManager.fileExists(atPath: target.path) || (try? fileManager.destinationOfSymbolicLink(atPath: target.path)) != nil {
                    try fileManager.removeItem(at: target)
                }
            }
        }
    }

    /// 将目录导出配置追加写入 ~/.zshrc
    public func appendPathToZshrcIfNeeded(location: CliInstallLocation) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let zshrcPath = "\(home)/.zshrc"
        let exportLine = "\n# Task Cleaner CLI\nexport PATH=\"\(location.directoryURL.path):$PATH\"\n"

        if FileManager.default.fileExists(atPath: zshrcPath) {
            if let content = try? String(contentsOfFile: zshrcPath, encoding: .utf8),
               content.contains(location.directoryURL.path) {
                return true
            }
            if let handle = FileHandle(forWritingAtPath: zshrcPath) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                if let data = exportLine.data(using: .utf8) {
                    handle.write(data)
                    return true
                }
            }
        } else {
            try? exportLine.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
            return true
        }
        return false
    }

    /// 在指定的终端模拟器（默认 preferredTerminal）中执行命令测试
    public func testInTerminal(command: String = "mtc --help", emulator: TerminalEmulator? = nil) {
        let target = emulator ?? self.preferredTerminal

        switch target {
        case .ghostty:
            // Ghostty 原生 AppleScript 支持，启动新窗口并注入命令与回车
            let script = """
            tell application "Ghostty"
                activate
                set cfg to (new surface configuration)
                set initial input of cfg to "\(command)\\n"
                new window with configuration cfg
            end tell
            """
            var scriptError: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&scriptError)
            }
            if scriptError != nil {
                // 回退到 open 传参方式
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-na", "Ghostty.app", "--args", "-e", "zsh", "-c", "\(command); exec zsh"]
                try? process.run()
            }

        case .iterm2:
            let script = """
            tell application "iTerm"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow
                    write text "\(command)"
                end tell
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }

        case .appleTerminal:
            let script = """
            tell application "Terminal"
                activate
                do script "\(command)"
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }

        case .warp, .alacritty, .kitty:
            let appName = target.rawValue
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", appName, "--args", "-e", "zsh", "-c", "\(command); exec zsh"]
            try? process.run()
        }
    }

    /// 在访达中定位并选中软链接
    public func revealInFinder(location: CliInstallLocation) {
        let target = location.mtcSymlinkURL
        if FileManager.default.fileExists(atPath: target.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: target.path)) != nil {
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } else {
            NSWorkspace.shared.open(location.directoryURL)
        }
    }
}
