import Foundation
import AppKit
import ApplicationServices

@MainActor
public final class AccessibilityManager: ObservableObject {
    public static let shared = AccessibilityManager()

    private let dismissedKey = "TaskCleaner_AccessibilityPromptDismissed"

    @Published public var isTrusted: Bool = false
    @Published public var isPromptDismissed: Bool = false

    private var pollTimer: Timer?
    private var burstTimer: Timer?
    private var burstRemainingCount: Int = 0

    private init() {
        self.isPromptDismissed = UserDefaults.standard.bool(forKey: dismissedKey)
        // 初次加载主动检测状态
        self.isTrusted = Self.queryIsTrusted(prompt: false)

        setupNotificationObservers()
        startAmbientPolling()
    }

    private func setupNotificationObservers() {
        // 1. 监听系统级分布式通知 (用户在系统设置中开关辅助功能时实时广播)
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }

        // 2. 监听窗口成为 Key 状态 (MenuBarExtraWindow 被点击呼出时触发)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
                self?.startBurstPolling(duration: 4.0, interval: 0.3)
            }
        }

        // 3. 监听应用激活/回到前台通知
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
                self?.startBurstPolling(duration: 4.0, interval: 0.3)
            }
        }
    }

    /// 查询系统底层真实的信任状态 (通过 AXIsProcessTrustedWithOptions 绕过静态缓存，配合 AXIsProcessTrusted 双重验证)
    public static func queryIsTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options) || AXIsProcessTrusted()
    }

    /// 是否应当在主面板中展示辅助功能授权引导横条
    public var shouldShowPrompt: Bool {
        return !isTrusted && !isPromptDismissed && GlobalShortcutManager.shared.isEnabled
    }

    /// 刷新当前进程的辅助功能权限信任状态
    @discardableResult
    public func checkTrust(prompt: Bool = false) -> Bool {
        let trusted = Self.queryIsTrusted(prompt: prompt)

        if self.isTrusted != trusted {
            self.isTrusted = trusted
            if trusted {
                self.isPromptDismissed = false
                UserDefaults.standard.set(false, forKey: dismissedKey)
                GlobalShortcutManager.shared.registerCurrentShortcut()
                TaskCleanerViewModel.shared?.statusMessage = I18n.shared.t(.status_accessibility_granted)
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    TaskCleanerViewModel.shared?.statusMessage = nil
                }
            }
        }
        return trusted
    }

    /// 静默刷新状态
    public func refreshStatus() {
        _ = checkTrust(prompt: false)
    }

    /// 启动常态心跳检测 (采用 .common RunLoop 模式确保菜单展开时不被挂起)
    public func startAmbientPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pollTimer = timer
    }

    /// 停止常态心跳检测
    public func stopAmbientPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// 启动突发高频轮询 (例如用户点击授权或激活窗口后，0.3s 间隔高频探查)
    public func startBurstPolling(duration: TimeInterval = 15.0, interval: TimeInterval = 0.3) {
        burstTimer?.invalidate()
        burstRemainingCount = max(1, Int(duration / interval))

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    t.invalidate()
                    return
                }
                self.burstRemainingCount -= 1
                let trusted = self.checkTrust(prompt: false)
                // 若已成功获权或倒计时耗尽，停止高频轮询
                if trusted || self.burstRemainingCount <= 0 {
                    self.burstTimer?.invalidate()
                    self.burstTimer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.burstTimer = timer
    }

    /// 停止突发高频轮询
    public func stopBurstPolling() {
        burstTimer?.invalidate()
        burstTimer = nil
    }

    /// 兼容老接口
    public func startPolling() {
        startAmbientPolling()
        startBurstPolling()
    }

    public func stopPolling() {
        stopBurstPolling()
    }

    /// 触发系统授权流程并一步跳转至 macOS 系统设置
    public func requestAuthorization() {
        // 1. 触发系统底层 API 注册应用至辅助功能列表并触发系统弹窗
        _ = checkTrust(prompt: true)

        // 2. 深度链接直接拉起 macOS 13+「系统设置 > 隐私与安全性 > 辅助功能」
        openAccessibilitySettings()

        // 3. 启动高频心跳 (持续 30 秒，0.3 秒间隔)，用户在设置面板切换开关后瞬间自动感知并收起提示
        startBurstPolling(duration: 30.0, interval: 0.3)
    }

    /// 一步拉起 macOS 系统设置的辅助功能授权页面
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 用户点击右上角忽略/关闭
    public func dismissPrompt() {
        self.isPromptDismissed = true
        UserDefaults.standard.set(true, forKey: dismissedKey)
    }

    /// 当用户主动配置或开启快捷键时，重置忽略状态以便重新提示
    public func resetDismissal() {
        self.isPromptDismissed = false
        UserDefaults.standard.set(false, forKey: dismissedKey)
        refreshStatus()
        startBurstPolling(duration: 5.0, interval: 0.3)
    }
}
