import SwiftUI
import AppKit
import Carbon

public class KeyCodeHelper {
    public static func keyString(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return ""
        }
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }

    public static func modifierFlags(from carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if (carbonModifiers & UInt32(controlKey)) != 0 { flags.insert(.control) }
        if (carbonModifiers & UInt32(optionKey)) != 0 { flags.insert(.option) }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { flags.insert(.shift) }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { flags.insert(.command) }
        return flags
    }

    public static func modifierDisplay(from flags: NSEvent.ModifierFlags) -> String {
        var res = ""
        if flags.contains(.control) { res += "⌃" }
        if flags.contains(.option) { res += "⌥" }
        if flags.contains(.shift) { res += "⇧" }
        if flags.contains(.command) { res += "⌘" }
        return res
    }
}

@MainActor
public class ShortcutRecorderViewModel: ObservableObject {
    @Published public var recordedKeyCode: UInt16?
    @Published public var recordedModifiers: NSEvent.ModifierFlags = []
    @Published public var activeModifiers: NSEvent.ModifierFlags = []

    private var eventMonitor: Any?

    public init() {
        loadCurrentShortcut()
    }

    public func loadCurrentShortcut() {
        let mgr = GlobalShortcutManager.shared
        if mgr.isEnabled {
            let key = mgr.currentKeyCode
            let mods = mgr.currentCarbonModifiers
            if key > 0 || mods > 0 {
                self.recordedKeyCode = UInt16(key)
                self.recordedModifiers = KeyCodeHelper.modifierFlags(from: mods)
            }
        }
    }

    public var hasValidRecordedShortcut: Bool {
        guard let _ = recordedKeyCode else { return false }
        return KeyCodeHelper.carbonModifiers(from: recordedModifiers) != 0
    }

    public func resetToDefault() {
        self.recordedKeyCode = UInt16(ShortcutPreset.optShiftK.keyCode)
        self.recordedModifiers = KeyCodeHelper.modifierFlags(from: ShortcutPreset.optShiftK.carbonModifiers)
        self.activeModifiers = []
    }

    public func clear() {
        self.recordedKeyCode = nil
        self.recordedModifiers = []
        self.activeModifiers = []
    }

    public func startMonitoring(onClose: @escaping () -> Void, onSave: @escaping () -> Void) {
        stopMonitoring()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }

            if event.type == .flagsChanged {
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                self.activeModifiers = flags
                return nil
            } else if event.type == .keyDown {
                // 1. Escape: 取消并退出
                if event.keyCode == 53 {
                    self.stopMonitoring()
                    onClose()
                    return nil
                }

                // 2. Return / Enter: 若已捕获合法快捷键则直接保存退出
                if event.keyCode == 36 {
                    if self.hasValidRecordedShortcut {
                        onSave()
                        return nil
                    }
                }

                // 3. Delete / ForwardDelete: 清空当前捕获组合
                if event.keyCode == 51 || event.keyCode == 117 {
                    self.clear()
                    return nil
                }

                // 4. 普通按键组合录制
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                let keyStr = KeyCodeHelper.keyString(for: event.keyCode)
                if !keyStr.isEmpty && !flags.isEmpty {
                    self.recordedKeyCode = event.keyCode
                    self.recordedModifiers = flags
                    self.activeModifiers = []
                }
                return nil
            }
            return event
        }
    }

    public func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

public struct ShortcutRecorderView: View {
    @ObservedObject private var i18n = I18n.shared
    @StateObject private var vm = ShortcutRecorderViewModel()
    @ObservedObject private var accessibilityManager = AccessibilityManager.shared

    var onClose: () -> Void

    public var body: some View {
        VStack(spacing: 18) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 24))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(i18n.t(.shortcut_recorder_title))
                        .font(.headline)
                    Text(i18n.t(.shortcut_recorder_desc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Key Display Area
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                vm.hasValidRecordedShortcut ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: vm.hasValidRecordedShortcut ? 2 : 1
                            )
                    )

                if let keyCode = vm.recordedKeyCode, !vm.recordedModifiers.isEmpty {
                    HStack(spacing: 8) {
                        if vm.recordedModifiers.contains(.control) {
                            keyBadge("⌃ Control")
                        }
                        if vm.recordedModifiers.contains(.option) {
                            keyBadge("⌥ Option")
                        }
                        if vm.recordedModifiers.contains(.shift) {
                            keyBadge("⇧ Shift")
                        }
                        if vm.recordedModifiers.contains(.command) {
                            keyBadge("⌘ Command")
                        }
                        let keyStr = KeyCodeHelper.keyString(for: keyCode)
                        if !keyStr.isEmpty {
                            keyBadge(keyStr, isPrimary: true)
                        }

                        Spacer()

                        Button(action: {
                            vm.clear()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(i18n.t(.btn_reset_shortcut))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                } else if !vm.activeModifiers.isEmpty {
                    HStack(spacing: 8) {
                        if vm.activeModifiers.contains(.control) {
                            keyBadge("⌃")
                        }
                        if vm.activeModifiers.contains(.option) {
                            keyBadge("⌥")
                        }
                        if vm.activeModifiers.contains(.shift) {
                            keyBadge("⇧")
                        }
                        if vm.activeModifiers.contains(.command) {
                            keyBadge("⌘")
                        }
                        Text("...")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text(i18n.t(.shortcut_recorder_prompt))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
            }
            .frame(height: 64)

            // Hint Text
            Text(i18n.t(.shortcut_recorder_hint))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Accessibility Warning Row (若未授予辅助功能权限，展示提醒与授权入口)
            if !accessibilityManager.isTrusted {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .systemOrange))

                    Text(i18n.t(.shortcut_recorder_accessibility_warning))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer()

                    Button(action: {
                        accessibilityManager.requestAuthorization()
                    }) {
                        Text(i18n.t(.btn_grant_permission))
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 4)
            }

            // Action Buttons
            HStack(spacing: 10) {
                Button(action: {
                    vm.resetToDefault()
                }) {
                    Text(i18n.t(.btn_restore_default))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Spacer()

                Button(action: {
                    vm.clear()
                }) {
                    Text(i18n.t(.btn_reset_shortcut))
                }

                Button(action: {
                    vm.stopMonitoring()
                    onClose()
                }) {
                    Text(i18n.t(.btn_cancel))
                }
                .keyboardShortcut(.cancelAction)

                Button(action: {
                    saveShortcut()
                }) {
                    Text(i18n.t(.btn_save_shortcut))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!vm.hasValidRecordedShortcut)
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear {
            vm.startMonitoring(
                onClose: onClose,
                onSave: { saveShortcut() }
            )
        }
        .onDisappear {
            vm.stopMonitoring()
        }
    }

    @ViewBuilder
    private func keyBadge(_ text: String, isPrimary: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isPrimary ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isPrimary ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }

    private func saveShortcut() {
        guard let keyCode = vm.recordedKeyCode else { return }
        let mods = KeyCodeHelper.carbonModifiers(from: vm.recordedModifiers)
        guard mods != 0 else { return }

        let displayMod = KeyCodeHelper.modifierDisplay(from: vm.recordedModifiers)
        let keyChar = KeyCodeHelper.keyString(for: keyCode)
        let fullDisplay = "\(displayMod)\(keyChar)"

        GlobalShortcutManager.shared.setCustomShortcut(
            keyCode: UInt32(keyCode),
            modifiers: mods,
            display: fullDisplay
        )

        vm.stopMonitoring()
        onClose()
    }
}

public class ShortcutRecorderWindowController: NSWindowController {
    public static let shared = ShortcutRecorderWindowController()

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 255),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showWindow() {
        guard let panel = self.window as? NSPanel else { return }

        // 每次唤起时重新装载全新的 HostingView，确保读取最新绑定的快捷键状态与重设环境
        let contentView = ShortcutRecorderView { [weak self] in
            self?.close()
        }
        panel.contentView = NSHostingView(rootView: contentView)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
