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

    private init() {
        self.isPromptDismissed = UserDefaults.standard.bool(forKey: dismissedKey)
        // 初次加载主动检测状态
        self.isTrusted = Self.queryIsTrusted(prompt: false)

        // 监听窗口成为 Key 状态 (MenuBarExtraWindow 被点击呼出时触发)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }

        // 监听应用回到前台/激活通知
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }

        // 若当前未授权，开启心跳轮询以便用户在系统设置授权时即时自动感知
        if !self.isTrusted {
            startPolling()
        }
    }

    /// 查询系统底层真实的信任状态 (通过 AXIsProcessTrustedWithOptions 绕过静态缓存)
    public static func queryIsTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
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
                stopPolling()
                TaskCleanerViewModel.shared?.statusMessage = I18n.shared.t(.status_accessibility_granted)
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    TaskCleanerViewModel.shared?.statusMessage = nil
                }
            } else {
                startPolling()
            }
        }
        return trusted
    }

    /// 静默刷新状态
    public func refreshStatus() {
        _ = checkTrust(prompt: false)
    }

    /// 启动主动检测心跳
    public func startPolling() {
        guard pollTimer == nil, !isTrusted else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.checkTrust(prompt: false) {
                    self.stopPolling()
                }
            }
        }
    }

    /// 停止心跳检测
    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// 触发系统授权流程并一步跳转至 macOS 系统设置
    public func requestAuthorization() {
        // 1. 触发系统底层 API 注册应用至辅助功能列表并触发系统弹窗
        _ = checkTrust(prompt: true)

        // 2. 深度链接直接拉起 macOS 13+「系统设置 > 隐私与安全性 > 辅助功能」
        openAccessibilitySettings()

        // 3. 启动高频心跳，用户在设置面板切换开关后瞬间自动感知并收起提示
        startPolling()
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
        if !isTrusted {
            startPolling()
        }
    }
}
