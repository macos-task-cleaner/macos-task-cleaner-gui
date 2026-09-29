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

    private struct SystemProcessEntry {
        let ppid: Int32
        let rssBytes: UInt64
        let cpuPercent: Double
    }

    /// 执行系统级全量进程快照 (/bin/ps -ax -o pid,ppid,rss,%cpu)
    /// 突破沙箱与 root/不同 UID 权限限制，毫秒级获取全系统真实物理驻留内存与 CPU 负载
    private func fetchSystemProcessSnapshot() -> (processes: [Int32: SystemProcessEntry], paths: [Int32: String])? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-ax", "-o", "pid,ppid,rss,%cpu"]
        proc.standardOutput = pipe
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()

            guard proc.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else {
                return nil
            }

            var processes: [Int32: SystemProcessEntry] = [:]
            var paths: [Int32: String] = [:]
            var pathBuf = [CChar](repeating: 0, count: 4096)

            for line in text.components(separatedBy: "\n").dropFirst() {
                let parts = line.split(separator: " ").map { String($0) }
                if parts.count >= 4,
                   let pid = Int32(parts[0]),
                   let ppid = Int32(parts[1]),
                   let rssKb = UInt64(parts[2]),
                   let cpu = Double(parts[3]) {
                    processes[pid] = SystemProcessEntry(ppid: ppid, rssBytes: rssKb * 1024, cpuPercent: cpu)

                    let ret = proc_pidpath(pid, &pathBuf, 4096)
                    if ret > 0 {
                        paths[pid] = String(cString: pathBuf)
                    }
                }
            }

            return (processes, paths)
        } catch {
            return nil
        }
    }

    /// 批量为一组前台应用 PID 采样深度聚合遥测数据 (内存、CPU、窗口与综合评分)
    public func sampleBatch(pids: [Int32]) -> [Int32: AppTelemetry] {
        let windows = sampleWindowCounts()
        var results: [Int32: AppTelemetry] = [:]

        // 尝试使用系统级深度快照聚合进程树与沙盒虚拟机内存
        if let (sysProcs, paths) = fetchSystemProcessSnapshot() {
            struct AppMeta {
                let pid: Int32
                let bundlePath: String?
            }

            var appMetas: [AppMeta] = []
            for pid in pids {
                var bp: String? = NSRunningApplication(processIdentifier: pid)?.bundleURL?.path
                if bp == nil, let p = paths[pid], let idx = p.range(of: ".app") {
                    bp = String(p[..<idx.upperBound])
                }
                appMetas.append(AppMeta(pid: pid, bundlePath: bp))
            }

            let fgPids = Set(pids)
            let bundleApps = appMetas
                .filter { $0.bundlePath != nil }
                .sorted { ($0.bundlePath?.count ?? 0) > ($1.bundlePath?.count ?? 0) }

            var memMap: [Int32: UInt64] = Dictionary(uniqueKeysWithValues: pids.map { ($0, 0) })
            var cpuMap: [Int32: Double] = Dictionary(uniqueKeysWithValues: pids.map { ($0, 0.0) })

            func findAncestorApp(for pid: Int32) -> Int32? {
                var curr = pid
                var visited = Set<Int32>()
                visited.insert(curr)
                for _ in 0..<32 {
                    guard let parent = sysProcs[curr]?.ppid, parent > 1, !visited.contains(parent) else { break }
                    if fgPids.contains(parent) {
                        return parent
                    }
                    visited.insert(parent)
                    curr = parent
                }
                return nil
            }

            for (procPid, entry) in sysProcs {
                // 1. 直属应用主进程
                if fgPids.contains(procPid) {
                    memMap[procPid, default: 0] += entry.rssBytes
                    cpuMap[procPid, default: 0.0] += entry.cpuPercent
                    continue
                }

                // 2. 检查是否在某 App 的 Bundle 目录内 (例如 Parallels VM.app/prl_vm_app 或 Chrome Helper)
                var matchedApp: Int32? = nil
                if let path = paths[procPid] {
                    for app in bundleApps {
                        if let bp = app.bundlePath, path.hasPrefix(bp + "/") {
                            matchedApp = app.pid
                            break
                        }
                    }
                }

                if let appPid = matchedApp {
                    memMap[appPid, default: 0] += entry.rssBytes
                    cpuMap[appPid, default: 0.0] += entry.cpuPercent
                    continue
                }

                // 3. 检查进程树 PPID 拓扑
                if let ancPid = findAncestorApp(for: procPid) {
                    memMap[ancPid, default: 0] += entry.rssBytes
                    cpuMap[ancPid, default: 0.0] += entry.cpuPercent
                    continue
                }
            }

            for pid in pids {
                let mem = memMap[pid] ?? 0
                let cpu = min(800.0, max(0.0, cpuMap[pid] ?? 0.0))
                let win = windows[pid] ?? 0

                let memMB = Double(mem) / (1024.0 * 1024.0)
                let composite = (memMB / 100.0) * 0.4 + (cpu * 2.0) * 0.4 + (Double(win) * 5.0) * 0.2

                results[pid] = AppTelemetry(
                    pid: pid,
                    memoryBytes: mem,
                    cpuPercent: cpu,
                    windowCount: win,
                    compositeScore: composite
                )
            }
            return results
        }

        // 降级使用单进程 proc_pidinfo 探测
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
