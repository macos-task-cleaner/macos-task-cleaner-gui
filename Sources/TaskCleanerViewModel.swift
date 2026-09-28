import Foundation
import SwiftUI
import AppKit
import Combine

public enum CleanerTab: Int, CaseIterable, Identifiable {
    case targets = 0
    case protected = 1
    case all = 2

    public var id: Int { rawValue }
}

@MainActor
public class TaskCleanerViewModel: ObservableObject {
    @Published public var summary: DryRunSummary?
    @Published public var isWorking: Bool = false
    @Published public var statusMessage: String?
    @Published public var selectedTab: CleanerTab = .targets
    @Published public var initialTargetCapacity: Int = 3
    @Published public var cliStatus: CliStatus = .notInstalled
    @Published public var preferredTerminal: TerminalEmulator = CliIntegrationManager.shared.preferredTerminal

    private let sortModeKey = "TaskCleaner_ProcessSortMode"
    @Published public var sortMode: ProcessSortMode {
        didSet {
            UserDefaults.standard.set(sortMode.rawValue, forKey: sortModeKey)
        }
    }

    private let showDetailedMetricsKey = "TaskCleaner_ShowDetailedMetrics"
    @Published public var showDetailedMetrics: Bool {
        didSet {
            UserDefaults.standard.set(showDetailedMetrics, forKey: showDetailedMetricsKey)
        }
    }

    private let showSortButtonKey = "TaskCleaner_ShowSortButton"
    @Published public var showSortButton: Bool {
        didSet {
            UserDefaults.standard.set(showSortButton, forKey: showSortButtonKey)
        }
    }

    public var isCliInstalled: Bool {
        if case .installed = cliStatus { return true }
        return false
    }

    public static weak var shared: TaskCleanerViewModel?

    public var isMenuTracking: Bool = false
    private var menuObservers: [NSObjectProtocol] = []
    private var hasCapturedSessionCapacity: Bool = false
    private var timerCancellable: AnyCancellable?
    private var workspaceObservers: [NSObjectProtocol] = []

    public init() {
        let storedSort = UserDefaults.standard.string(forKey: sortModeKey) ?? ProcessSortMode.composite.rawValue
        self.sortMode = ProcessSortMode(rawValue: storedSort) ?? .composite

        if UserDefaults.standard.object(forKey: showDetailedMetricsKey) == nil {
            self.showDetailedMetrics = true
        } else {
            self.showDetailedMetrics = UserDefaults.standard.bool(forKey: showDetailedMetricsKey)
        }

        if UserDefaults.standard.object(forKey: showSortButtonKey) == nil {
            self.showSortButton = true
        } else {
            self.showSortButton = UserDefaults.standard.bool(forKey: showSortButtonKey)
        }

        Self.shared = self
        _ = GlobalShortcutManager.shared

        let dc = NotificationCenter.default
        let beginObs = dc.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isMenuTracking = true
            }
        }
        let endObs = dc.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isMenuTracking = false
            }
        }
        menuObservers = [beginObs, endObs]

        refreshCliStatus()
        refresh(silent: true)
    }

    deinit {
        timerCancellable?.cancel()
        for obs in menuObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        let nc = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            nc.removeObserver(obs)
        }
    }

    private func updateInitialCapacityIfNeeded(from summary: DryRunSummary?) {
        guard !hasCapturedSessionCapacity else { return }
        if let count = summary?.target_count {
            self.initialTargetCapacity = min(6, max(3, count))
            self.hasCapturedSessionCapacity = true
        }
    }

    public func refresh(silent: Bool = false) {
        guard !isMenuTracking else { return }
        Task {
            if !silent {
                isWorking = true
            }

            let result = await Task.detached {
                MTCBridge.shared.fetchSummary()
            }.value

            guard !self.isMenuTracking else {
                if !silent { self.isWorking = false }
                return
            }

            guard let result = result else {
                if !silent { self.isWorking = false }
                return
            }

            let allPids = (result.targets.map { Int32($0.pid) } + result.protected_apps.map { Int32($0.pid) })
            let telemetryMap = await Task.detached {
                ProcessTelemetrySampler.shared.sampleBatch(pids: allPids)
            }.value

            ProcessTelemetrySampler.shared.pruneExitedProcesses(activePids: Set(allPids))

            let enrichedTargets = result.targets.map { target -> TargetAppEntry in
                var t = target
                if let telem = telemetryMap[Int32(target.pid)] {
                    t.memory_bytes = telem.memoryBytes
                    t.cpu_percent = telem.cpuPercent
                    t.window_count = telem.windowCount
                    t.composite_score = telem.compositeScore
                }
                return t
            }
            let enrichedProtected = result.protected_apps.map { app -> ProtectedAppEntry in
                var p = app
                if let telem = telemetryMap[Int32(app.pid)] {
                    p.memory_bytes = telem.memoryBytes
                    p.cpu_percent = telem.cpuPercent
                    p.window_count = telem.windowCount
                    p.composite_score = telem.compositeScore
                }
                return p
            }

            let enrichedSummary = DryRunSummary(
                scanned_total: result.scanned_total,
                protected_count: result.protected_count,
                target_count: result.target_count,
                scan_duration_ms: result.scan_duration_ms,
                config_source: result.config_source,
                protected_apps: enrichedProtected,
                targets: enrichedTargets
            )

            if self.summary != enrichedSummary {
                self.summary = enrichedSummary
                self.updateInitialCapacityIfNeeded(from: enrichedSummary)
            }

            self.refreshCliStatus()

            if !silent {
                self.isWorking = false
            }
        }
    }

    // MARK: - 实时前台进程监听系统 (Live Monitoring)
    public func startLiveMonitoring() {
        // 每次托盘面板重新打开时，重置会话锁，捕获第一次打开时的待结束进程数量
        hasCapturedSessionCapacity = false
        updateInitialCapacityIfNeeded(from: summary)

        // 1. 弹出瞬间立即执行一次静默刷新
        refresh(silent: true)

        // 2. 开启心跳 (每 2 秒自动同步，在 default 模式下运行，菜单追踪时自动静默挂起)
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 2.0, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, !self.isWorking, !self.isMenuTracking else { return }
                self.refresh(silent: true)
            }

        // 3. 订阅 macOS 原生应用生命周期事件 (即时感知应用启动、退出与激活)
        stopWorkspaceObservers()
        let nc = NSWorkspace.shared.notificationCenter

        let launchObs = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isMenuTracking else { return }
                self.refresh(silent: true)
            }
        }

        let termObs = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isMenuTracking else { return }
                self.refresh(silent: true)
            }
        }

        let actObs = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isMenuTracking else { return }
                self.refresh(silent: true)
            }
        }

        workspaceObservers = [launchObs, termObs, actObs]
    }

    public func stopLiveMonitoring() {
        hasCapturedSessionCapacity = false
        timerCancellable?.cancel()
        timerCancellable = nil
        stopWorkspaceObservers()
    }

    private func stopWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            nc.removeObserver(obs)
        }
        workspaceObservers.removeAll()
    }

    // MARK: - 多维指标排序系统 (5 种排序模式)
    public var sortedTargets: [TargetAppEntry] {
        guard let list = summary?.targets else { return [] }
        return sortTargets(list, mode: sortMode)
    }

    public var sortedProtected: [ProtectedAppEntry] {
        guard let list = summary?.protected_apps else { return [] }
        return sortProtected(list, mode: sortMode)
    }

    private func sortTargets(_ list: [TargetAppEntry], mode: ProcessSortMode) -> [TargetAppEntry] {
        switch mode {
        case .composite:
            return list.sorted {
                let s0 = $0.composite_score ?? 0.0
                let s1 = $1.composite_score ?? 0.0
                if abs(s0 - s1) > 0.001 { return s0 > s1 }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .memory:
            return list.sorted {
                let m0 = $0.memory_bytes ?? 0
                let m1 = $1.memory_bytes ?? 0
                if m0 != m1 { return m0 > m1 }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .cpu:
            return list.sorted {
                let c0 = $0.cpu_percent ?? 0.0
                let c1 = $1.cpu_percent ?? 0.0
                if abs(c0 - c1) > 0.05 { return c0 > c1 }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .windows:
            return list.sorted {
                let w0 = $0.window_count ?? 0
                let w1 = $1.window_count ?? 0
                if w0 != w1 { return w0 > w1 }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .defaultName:
            return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private func sortProtected(_ list: [ProtectedAppEntry], mode: ProcessSortMode) -> [ProtectedAppEntry] {
        switch mode {
        case .composite:
            return list.sorted {
                let s0 = $0.composite_score ?? 0.0
                let s1 = $1.composite_score ?? 0.0
                if abs(s0 - s1) > 0.001 { return s0 > s1 }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .memory:
            return list.sorted {
                let m0 = $0.memory_bytes ?? 0
                let m1 = $1.memory_bytes ?? 0
                if m0 != m1 { return m0 > m1 }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .cpu:
            return list.sorted {
                let c0 = $0.cpu_percent ?? 0.0
                let c1 = $1.cpu_percent ?? 0.0
                if abs(c0 - c1) > 0.05 { return c0 > c1 }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .windows:
            return list.sorted {
                let w0 = $0.window_count ?? 0
                let w1 = $1.window_count ?? 0
                if w0 != w1 { return w0 > w1 }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .defaultName:
            return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    // MARK: - 核心执行操作
    public func cleanAll(force: Bool = false, purge: Bool = false) {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = I18n.shared.t(.status_terminating_all)

        Task {
            let success = await Task.detached {
                MTCBridge.shared.executeClean(force: force, purge: purge)
            }.value

            if success {
                self.statusMessage = I18n.shared.t(.status_all_terminated)
            } else {
                self.statusMessage = I18n.shared.t(.status_some_unresponsive)
            }

            self.isWorking = false
            self.refresh(silent: true)

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.statusMessage = nil
        }
    }

    public func triggerGlobalShortcutClean() {
        guard !isWorking else { return }
        cleanAll(force: false, purge: false)
    }

    public func terminateTarget(_ app: TargetAppEntry) {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = I18n.shared.format(.status_terminating_app, app.localizedName(in: I18n.shared))

        Task {
            let success = await Task.detached {
                MTCBridge.shared.terminateProcess(pid: app.pid)
            }.value

            if success {
                self.statusMessage = I18n.shared.format(.status_app_terminated, app.localizedName(in: I18n.shared))
            } else {
                self.statusMessage = I18n.shared.format(.status_app_terminate_failed, app.localizedName(in: I18n.shared))
            }

            self.isWorking = false
            self.refresh(silent: true)

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.statusMessage = nil
        }
    }

    public func whitelistApp(_ app: TargetAppEntry) {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = I18n.shared.format(.status_added_whitelist, app.localizedName(in: I18n.shared))

        Task {
            let identifier = !app.bundle_id.isEmpty ? app.bundle_id : app.name
            _ = await Task.detached {
                MTCBridge.shared.addToWhitelist(identifier: identifier)
            }.value

            self.isWorking = false
            self.refresh(silent: true)

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.statusMessage = nil
        }
    }

    public func unprotectApp(_ app: ProtectedAppEntry) {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = I18n.shared.format(.status_removed_whitelist, app.localizedName(in: I18n.shared))

        Task {
            let identifier = !app.bundle_id.isEmpty ? app.bundle_id : app.name
            _ = await Task.detached {
                MTCBridge.shared.removeFromWhitelist(identifier: identifier)
            }.value

            self.isWorking = false
            self.refresh(silent: true)

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.statusMessage = nil
        }
    }

    public func openConfigFile() {
        MTCBridge.shared.openConfigFile()
    }

    public func openConfigDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".config/taskcleaner")
        if FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.open(dir)
        } else {
            let legacy = home.appendingPathComponent(".config/mtc")
            NSWorkspace.shared.open(legacy)
        }
    }

    // MARK: - CLI 集成管理
    public func refreshCliStatus() {
        self.cliStatus = CliIntegrationManager.shared.detectCliStatus()
        self.preferredTerminal = CliIntegrationManager.shared.preferredTerminal
    }

    public func installCli(to location: CliInstallLocation = .userLocalBin) {
        do {
            let (symlinkPath, isInPath) = try CliIntegrationManager.shared.installSymlink(to: location)
            refreshCliStatus()
            self.statusMessage = I18n.shared.t(.status_cli_installed)

            let alert = NSAlert()
            if !isInPath {
                alert.messageText = I18n.shared.t(.install_cli_path_missing_title)
                alert.informativeText = I18n.shared.format(.install_cli_path_missing_desc, symlinkPath)
                alert.alertStyle = .warning
                alert.addButton(withTitle: I18n.shared.t(.btn_add_to_zshrc))
                alert.addButton(withTitle: I18n.shared.t(.btn_ready))

                NSApp.activate(ignoringOtherApps: true)
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    if CliIntegrationManager.shared.appendPathToZshrcIfNeeded(location: location) {
                        self.statusMessage = I18n.shared.t(.status_zshrc_updated)
                        refreshCliStatus()
                    }
                }
            } else {
                alert.messageText = I18n.shared.t(.install_cli_success_title)
                alert.informativeText = I18n.shared.format(.install_cli_success_desc, symlinkPath)
                alert.alertStyle = .informational
                alert.addButton(withTitle: I18n.shared.t(.btn_ready))

                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }

            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.statusMessage = nil
            }
        } catch {
            self.statusMessage = "\(I18n.shared.t(.status_cli_install_failed)): \(error.localizedDescription)"
            refreshCliStatus()
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.statusMessage = nil
            }
        }
    }

    public func installCliCommand() {
        installCli(to: .userLocalBin)
    }

    public func uninstallCli() {
        do {
            try CliIntegrationManager.shared.uninstallSymlinks()
            refreshCliStatus()
            self.statusMessage = I18n.shared.t(.status_cli_uninstalled)
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.statusMessage = nil
            }
        } catch {
            self.statusMessage = error.localizedDescription
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.statusMessage = nil
            }
        }
    }

    public var installedTerminals: [TerminalEmulator] {
        CliIntegrationManager.shared.installedTerminals
    }

    public func setPreferredTerminal(_ emulator: TerminalEmulator) {
        CliIntegrationManager.shared.setPreferredTerminal(emulator)
        self.preferredTerminal = emulator
    }

    public func testCliInTerminal(emulator: TerminalEmulator? = nil) {
        CliIntegrationManager.shared.testInTerminal(emulator: emulator)
    }

    public func revealCliInFinder() {
        if case .installed(let loc, _, _) = cliStatus {
            CliIntegrationManager.shared.revealInFinder(location: loc)
        } else if case .broken(let loc, _) = cliStatus {
            CliIntegrationManager.shared.revealInFinder(location: loc)
        } else {
            CliIntegrationManager.shared.revealInFinder(location: .userLocalBin)
        }
    }

    public func revealInFinder(pid: Int) {
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)),
           let url = app.bundleURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    public func copyToClipboard(text: String, label: String? = nil) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if let label = label {
            self.statusMessage = label
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.statusMessage = nil
            }
        }
    }

    public func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "Task Cleaner 1.0.0"
        alert.informativeText = """
        Copyright (c) 2026 DonJone. All rights reserved.

        Dual-Licensed: GNU AGPLv3 / Commercial License

        Free and open source for personal and community use under GNU AGPLv3.
        Commercial bundling, proprietary closed-source integration, SaaS operation, or white-labeling requires a commercial license.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Commercial Policy")
        alert.addButton(withTitle: "GitHub")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/macos-task-cleaner/macos-task-cleaner-gui/blob/main/COMMERCIAL.md") {
                NSWorkspace.shared.open(url)
            }
        } else if response == .alertThirdButtonReturn {
            if let url = URL(string: "https://github.com/macos-task-cleaner/macos-task-cleaner-gui") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
