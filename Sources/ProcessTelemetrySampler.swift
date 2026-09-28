import Foundation
import AppKit
import Darwin.libproc

public struct AppTelemetry: Equatable {
    public let pid: Int32
    public var memoryBytes: UInt64
    public var cpuPercent: Double
    public var windowCount: Int
    public var compositeScore: Double

    public init(pid: Int32, memoryBytes: UInt64 = 0, cpuPercent: Double = 0.0, windowCount: Int = 0, compositeScore: Double = 0.0) {
        self.pid = pid
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
        self.windowCount = windowCount
        self.compositeScore = compositeScore
    }
}

public final class ProcessTelemetrySampler {
    public static let shared = ProcessTelemetrySampler()

    private struct CpuSample {
        let timestampNanos: UInt64
        let totalCpuNanos: UInt64
    }

    private var previousCpuSamples: [Int32: CpuSample] = [:]
    private let lock = NSLock()

    private init() {}

    /// 采样前台所有活动应用的窗口数量
    public func sampleWindowCounts() -> [Int32: Int] {
        var counts: [Int32: Int] = [:]
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return counts
        }

        for win in windowList {
            guard let layer = win[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = win[kCGWindowOwnerPID as String] as? Int32 else { continue }
            counts[pid, default: 0] += 1
        }
        return counts
    }

    /// 对指定进程 PID 采样内存 (RSS) 与 CPU 占用
    public func sampleProcess(pid: Int32, windowCount: Int? = nil) -> AppTelemetry {
        var taskInfo = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let res = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size)

        let memoryBytes: UInt64 = (res == size) ? taskInfo.pti_resident_size : 0
        let currentCpuNanos = (res == size) ? (taskInfo.pti_total_user + taskInfo.pti_total_system) : 0
        let nowNanos = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)

        var cpuPercent: Double = 0.0

        lock.lock()
        if let previous = previousCpuSamples[pid], nowNanos > previous.timestampNanos, currentCpuNanos >= previous.totalCpuNanos {
            let deltaWall = Double(nowNanos - previous.timestampNanos)
            let deltaCpu = Double(currentCpuNanos - previous.totalCpuNanos)
            if deltaWall > 0 {
                // 计算百分比并限制在合理区间内
                cpuPercent = min(800.0, max(0.0, (deltaCpu / deltaWall) * 100.0))
            }
        }
        previousCpuSamples[pid] = CpuSample(timestampNanos: nowNanos, totalCpuNanos: currentCpuNanos)
        lock.unlock()

        let windows = windowCount ?? sampleWindowCounts()[pid] ?? 0

        // 综合评分计算公式:
        // 内存权重 40% (以 100MB 为基准单位)
        // CPU 权重 40% (每个 1% 算 2.0 分)
        // 窗口数量权重 20% (每个可见窗口算 5.0 分)
        let memMB = Double(memoryBytes) / (1024.0 * 1024.0)
        let composite = (memMB / 100.0) * 0.4 + (cpuPercent * 2.0) * 0.4 + (Double(windows) * 5.0) * 0.2

        return AppTelemetry(
            pid: pid,
            memoryBytes: memoryBytes,
            cpuPercent: cpuPercent,
            windowCount: windows,
            compositeScore: composite
        )
    }

    /// 批量为一组 PID 采样遥测数据
    public func sampleBatch(pids: [Int32]) -> [Int32: AppTelemetry] {
        let windows = sampleWindowCounts()
        var results: [Int32: AppTelemetry] = [:]
        for pid in pids {
            results[pid] = sampleProcess(pid: pid, windowCount: windows[pid] ?? 0)
        }
        return results
    }

    /// 清理已退出进程的 CPU 历史采样
    public func pruneExitedProcesses(activePids: Set<Int32>) {
        lock.lock()
        defer { lock.unlock() }
        previousCpuSamples = previousCpuSamples.filter { activePids.contains($0.key) }
    }

    // MARK: - 视觉度量格式化工具
    public static func formatMemory(_ bytes: UInt64?) -> String {
        guard let bytes = bytes, bytes > 0 else { return "-- MB" }
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb >= 1024.0 {
            return String(format: "%.1f GB", mb / 1024.0)
        }
        return String(format: "%.0f MB", mb)
    }

    public static func formatCpu(_ percent: Double?) -> String {
        guard let p = percent else { return "--%" }
        if p < 0.1 {
            return "< 0.1%"
        }
        return String(format: "%.1f%%", p)
    }

    public static func formatWindows(_ count: Int?, unit: String = "窗口") -> String {
        let c = count ?? 0
        return "\(c) \(unit)"
    }
}
