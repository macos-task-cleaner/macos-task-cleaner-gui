import Foundation
import AppKit
import ApplicationServices

@MainActor
public final class AccessibilityManager: ObservableObject {
    public static let shared = AccessibilityManager()

    private let dismissedKey = "TaskCleaner_AccessibilityPromptDismissed"

    @Published public var isTrusted: Bool = false
    @Published public var isPromptDismissed: Bool = false

    private init() {
        self.isTrusted = AXIsProcessTrusted()
        self.isPromptDismissed = UserDefaults.standard.bool(forKey: dismissedKey)

        // 监听应用回到前台/激活通知，当用户从系统设置返回时自动更新授权状态
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }
    }

    /// 是否应当在主面板中展示辅助功能授权引导卡片
    public var shouldShowPrompt: Bool {
        return !isTrusted && !isPromptDismissed && GlobalShortcutManager.shared.isEnabled
    }

    /// 刷新当前进程的辅助功能权限信任状态
    @discardableResult
    public func checkTrust(prompt: Bool = false) -> Bool {
        let trusted: Bool
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }

        if self.isTrusted != trusted {
            self.isTrusted = trusted
            if trusted {
                // 已获得权限，自动清除忽略标记
                self.isPromptDismissed = false
                UserDefaults.standard.set(false, forKey: dismissedKey)
            }
        }
        return trusted
    }

    /// 静默刷新状态
    public func refreshStatus() {
        _ = checkTrust(prompt: false)
    }

    /// 触发系统授权流程并一步跳转至 macOS 系统设置
    public func requestAuthorization() {
        // 1. 调用系统底层 API 注册应用至辅助功能列表并触发系统弹窗（若系统支持）
        _ = checkTrust(prompt: true)

        // 2. 深度链接直接拉起 macOS 13+「系统设置 > 隐私与安全性 > 辅助功能」
        openAccessibilitySettings()
    }

    /// 一步拉起 macOS 系统设置的辅助功能授权页面
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 用户在主卡片中点击稍后/关闭
    public func dismissPrompt() {
        self.isPromptDismissed = true
        UserDefaults.standard.set(true, forKey: dismissedKey)
    }

    /// 当用户主动配置或开启快捷键时，重置忽略状态以便重新提示
    public func resetDismissal() {
        self.isPromptDismissed = false
        UserDefaults.standard.set(false, forKey: dismissedKey)
        refreshStatus()
    }
}
