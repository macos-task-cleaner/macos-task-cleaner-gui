import Foundation
import AppKit
import UniformTypeIdentifiers

public struct DryRunSummary: Codable, Equatable {
    public let scanned_total: Int
    public let protected_count: Int
    public let target_count: Int
    public let scan_duration_ms: Double
    public let config_source: String
    public let protected_apps: [ProtectedAppEntry]
    public let targets: [TargetAppEntry]

    public static func == (lhs: DryRunSummary, rhs: DryRunSummary) -> Bool {
        return lhs.scanned_total == rhs.scanned_total
            && lhs.protected_count == rhs.protected_count
            && lhs.target_count == rhs.target_count
            && lhs.protected_apps == rhs.protected_apps
            && lhs.targets == rhs.targets
    }
}

public enum ProcessSortMode: String, CaseIterable, Identifiable, Codable {
    case composite = "composite"     // 综合负载
    case memory = "memory"           // 内存占用
    case cpu = "cpu"                 // 处理器占用
    case windows = "windows"         // 窗口数量
    case defaultName = "default"     // 默认/应用名称

    public var id: String { rawValue }
}

/// 统一进程排序与展示条目协议，消除 TargetAppEntry 与 ProtectedAppEntry 的重复逻辑
public protocol ProcessSortableEntry: Identifiable, Equatable {
    var pid: Int { get }
    var name: String { get }
    var bundle_id: String { get }
    var memory_bytes: UInt64? { get set }
    var cpu_percent: Double? { get set }
    var window_count: Int? { get set }
    var composite_score: Double? { get set }
    var appIcon: NSImage { get }
}

extension ProcessSortableEntry {
    @MainActor
    public func localizedName(in i18n: I18n) -> String {
        AppDisplayNameResolver.shared.resolve(
            bundleId: bundle_id,
            fallback: name,
            language: i18n.currentLanguage
        )
    }

    public var effectiveIdentifier: String {
        !bundle_id.isEmpty ? bundle_id : name
    }

    public var tooltipText: String {
        bundle_id.isEmpty ? "PID: \(pid)" : "\(bundle_id) (PID: \(pid))"
    }
}

/// 线程安全的应用图标内存缓存，避免列表高频重绘与滚动时重复触发磁盘 I/O
public final class AppIconCache {
    public static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()
    private let fallbackIcon: NSImage

    private init() {
        cache.countLimit = 128
        fallbackIcon = NSWorkspace.shared.icon(for: .application)
    }

    public func icon(forPid pid: Int, bundleId: String) -> NSImage {
        let key = (!bundleId.isEmpty ? bundleId : "pid_\(pid)") as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        if let runningApp = NSRunningApplication(processIdentifier: pid_t(pid)),
           let icon = runningApp.icon {
            cache.setObject(icon, forKey: key)
            return icon
        }

        if !bundleId.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            cache.setObject(icon, forKey: key)
            return icon
        }

        return fallbackIcon
    }
}

public struct TargetAppEntry: Codable, Identifiable, Equatable, ProcessSortableEntry {
    public var id: Int { pid }
    public let pid: Int
    public let name: String
    public let bundle_id: String
    public let is_alive: Bool
    public var memory_bytes: UInt64?
    public var cpu_percent: Double?
    public var window_count: Int?
    public var composite_score: Double?

    public init(
        pid: Int,
        name: String,
        bundle_id: String,
        is_alive: Bool,
        memory_bytes: UInt64? = nil,
        cpu_percent: Double? = nil,
        window_count: Int? = nil,
        composite_score: Double? = nil
    ) {
        self.pid = pid
        self.name = name
        self.bundle_id = bundle_id
        self.is_alive = is_alive
        self.memory_bytes = memory_bytes
        self.cpu_percent = cpu_percent
        self.window_count = window_count
        self.composite_score = composite_score
    }

    public static func == (lhs: TargetAppEntry, rhs: TargetAppEntry) -> Bool {
        return lhs.pid == rhs.pid
            && lhs.name == rhs.name
            && lhs.bundle_id == rhs.bundle_id
            && lhs.is_alive == rhs.is_alive
            && lhs.memory_bytes == rhs.memory_bytes
            && lhs.cpu_percent == rhs.cpu_percent
            && lhs.window_count == rhs.window_count
    }

    public var appIcon: NSImage {
        AppIconCache.shared.icon(forPid: pid, bundleId: bundle_id)
    }
}

public struct ProtectedAppEntry: Codable, Identifiable, Equatable, ProcessSortableEntry {
    public var id: Int { pid }
    public let pid: Int
    public let name: String
    public let bundle_id: String
    public let tier: String
    public let tier_id: String?
    public let rule: String
    public var memory_bytes: UInt64?
    public var cpu_percent: Double?
    public var window_count: Int?
    public var composite_score: Double?

    public init(
        pid: Int,
        name: String,
        bundle_id: String,
        tier: String,
        tier_id: String?,
        rule: String,
        memory_bytes: UInt64? = nil,
        cpu_percent: Double? = nil,
        window_count: Int? = nil,
        composite_score: Double? = nil
    ) {
        self.pid = pid
        self.name = name
        self.bundle_id = bundle_id
        self.tier = tier
        self.tier_id = tier_id
        self.rule = rule
        self.memory_bytes = memory_bytes
        self.cpu_percent = cpu_percent
        self.window_count = window_count
        self.composite_score = composite_score
    }

    public static func == (lhs: ProtectedAppEntry, rhs: ProtectedAppEntry) -> Bool {
        return lhs.pid == rhs.pid
            && lhs.name == rhs.name
            && lhs.bundle_id == rhs.bundle_id
            && lhs.tier == rhs.tier
            && lhs.tier_id == rhs.tier_id
            && lhs.rule == rhs.rule
            && lhs.memory_bytes == rhs.memory_bytes
            && lhs.cpu_percent == rhs.cpu_percent
            && lhs.window_count == rhs.window_count
    }

    public var appIcon: NSImage {
        AppIconCache.shared.icon(forPid: pid, bundleId: bundle_id)
    }
}
