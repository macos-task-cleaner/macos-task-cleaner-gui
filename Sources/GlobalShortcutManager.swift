import Foundation
import AppKit
import Carbon
import Combine

public enum ShortcutPreset: String, CaseIterable, Identifiable {
    case optShiftK = "optShiftK"
    case optCmdK = "optCmdK"
    case ctrlOptK = "ctrlOptK"
    case cmdShiftX = "cmdShiftX"

    public var id: String { rawValue }

    public var displayString: String {
        switch self {
        case .optShiftK: return "⌥⇧K"
        case .optCmdK: return "⌥⌘K"
        case .ctrlOptK: return "⌃⌥K"
        case .cmdShiftX: return "⌘⇧X"
        }
    }

    public var keyCode: UInt32 {
        switch self {
        case .optShiftK, .optCmdK, .ctrlOptK:
            return UInt32(kVK_ANSI_K) // 40
        case .cmdShiftX:
            return UInt32(kVK_ANSI_X) // 7
        }
    }

    public var carbonModifiers: UInt32 {
        switch self {
        case .optShiftK:
            return UInt32(optionKey | shiftKey)
        case .optCmdK:
            return UInt32(optionKey | cmdKey)
        case .ctrlOptK:
            return UInt32(controlKey | optionKey)
        case .cmdShiftX:
            return UInt32(cmdKey | shiftKey)
        }
    }
}

@MainActor
public class GlobalShortcutManager: ObservableObject {
    public static let shared = GlobalShortcutManager()

    private let userDefaultsKeyEnabled = "tc_shortcut_enabled"
    private let userDefaultsKeyPreset = "tc_shortcut_preset"
    private let userDefaultsKeyKeyCode = "tc_shortcut_keycode"
    private let userDefaultsKeyModifiers = "tc_shortcut_modifiers"
    private let userDefaultsKeyDisplay = "tc_shortcut_display"

    @Published public var isEnabled: Bool = true
    @Published public var displayString: String = "⌥⇧K"
    @Published public var currentPreset: ShortcutPreset? = .optShiftK

    private var hotKeyRef: EventHotKeyRef?
    private static var isEventHandlerInstalled = false

    private init() {
        loadSettings()
        setupCarbonEventHandler()
        registerCurrentShortcut()
    }

    private func loadSettings() {
        if UserDefaults.standard.object(forKey: userDefaultsKeyEnabled) == nil {
            // 首次启动，默认启用 ⌥⇧K
            UserDefaults.standard.set(true, forKey: userDefaultsKeyEnabled)
            UserDefaults.standard.set(ShortcutPreset.optShiftK.rawValue, forKey: userDefaultsKeyPreset)
            UserDefaults.standard.set(ShortcutPreset.optShiftK.keyCode, forKey: userDefaultsKeyKeyCode)
            UserDefaults.standard.set(ShortcutPreset.optShiftK.carbonModifiers, forKey: userDefaultsKeyModifiers)
            UserDefaults.standard.set(ShortcutPreset.optShiftK.displayString, forKey: userDefaultsKeyDisplay)
        }

        self.isEnabled = UserDefaults.standard.bool(forKey: userDefaultsKeyEnabled)
        self.displayString = UserDefaults.standard.string(forKey: userDefaultsKeyDisplay) ?? "⌥⇧K"

        if let presetRaw = UserDefaults.standard.string(forKey: userDefaultsKeyPreset),
           let preset = ShortcutPreset(rawValue: presetRaw) {
            self.currentPreset = preset
        } else {
            self.currentPreset = nil
        }
    }

    private func setupCarbonEventHandler() {
        guard !Self.isEventHandlerInstalled else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (handler, event, userData) -> OSStatus in
                Task { @MainActor in
                    GlobalShortcutManager.shared.handleHotKeyTriggered()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )

        if status == noErr {
            Self.isEventHandlerInstalled = true
        }
    }

    public func handleHotKeyTriggered() {
        guard isEnabled else { return }
        // 播放轻量系统触感声音
        NSSound(named: "Pop")?.play()
        TaskCleanerViewModel.shared?.triggerGlobalShortcutClean()
    }

    private func unregisterCurrentShortcut() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    public func registerCurrentShortcut() {
        unregisterCurrentShortcut()
        guard isEnabled else { return }

        let keyCode = UInt32(UserDefaults.standard.integer(forKey: userDefaultsKeyKeyCode))
        let modifiers = UInt32(UserDefaults.standard.integer(forKey: userDefaultsKeyModifiers))

        guard keyCode > 0 || modifiers > 0 else { return }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5443), id: 1) // "TC"
        var newRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        if status == noErr {
            self.hotKeyRef = newRef
        }
    }

    public func setPreset(_ preset: ShortcutPreset) {
        self.isEnabled = true
        self.currentPreset = preset
        self.displayString = preset.displayString

        UserDefaults.standard.set(true, forKey: userDefaultsKeyEnabled)
        UserDefaults.standard.set(preset.rawValue, forKey: userDefaultsKeyPreset)
        UserDefaults.standard.set(preset.keyCode, forKey: userDefaultsKeyKeyCode)
        UserDefaults.standard.set(preset.carbonModifiers, forKey: userDefaultsKeyModifiers)
        UserDefaults.standard.set(preset.displayString, forKey: userDefaultsKeyDisplay)

        registerCurrentShortcut()
        AccessibilityManager.shared.resetDismissal()
        TaskCleanerViewModel.shared?.statusMessage = I18n.shared.format(.status_shortcut_bound, preset.displayString)
    }

    public func setCustomShortcut(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.isEnabled = true
        self.currentPreset = nil
        self.displayString = display

        UserDefaults.standard.set(true, forKey: userDefaultsKeyEnabled)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyPreset)
        UserDefaults.standard.set(keyCode, forKey: userDefaultsKeyKeyCode)
        UserDefaults.standard.set(modifiers, forKey: userDefaultsKeyModifiers)
        UserDefaults.standard.set(display, forKey: userDefaultsKeyDisplay)

        registerCurrentShortcut()
        AccessibilityManager.shared.resetDismissal()
        TaskCleanerViewModel.shared?.statusMessage = I18n.shared.format(.status_shortcut_bound, display)
    }

    public func disableShortcut() {
        self.isEnabled = false
        UserDefaults.standard.set(false, forKey: userDefaultsKeyEnabled)
        unregisterCurrentShortcut()
        TaskCleanerViewModel.shared?.statusMessage = I18n.shared.t(.status_shortcut_disabled)
    }

    public var currentKeyCode: UInt32 {
        UInt32(UserDefaults.standard.integer(forKey: userDefaultsKeyKeyCode))
    }

    public var currentCarbonModifiers: UInt32 {
        UInt32(UserDefaults.standard.integer(forKey: userDefaultsKeyModifiers))
    }

    public func resetToDefault() {
        setPreset(.optShiftK)
    }

    public func openCustomShortcutRecorder() {
        ShortcutRecorderWindowController.shared.showWindow()
    }
}
