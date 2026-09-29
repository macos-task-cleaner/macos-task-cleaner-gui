# macOS Task Cleaner GUI - Agent Guidelines & Engineering Constraints

This document defines the architectural conventions, engineering rules, and hard constraints for AI coding agents operating on the `macos-task-cleaner-gui` codebase.

---

## 1. Global Operating Policies

1. **Strict No-Emoji Policy**:
   * Never output Unicode emojis in code, comments, Git commit messages, logs, UI strings, documentation, or responses.
   * Use plain text prefixes for emphasis or status (e.g., `[INFO]`, `[WARN]`, `[SUCCESS]`, `*`, `-`).

2. **Workspace Delivery Principle**:
   * All deliverables, source code modifications, scripts, and documentation must physically persist within the local workspace directory.
   * Never leave deliverables exclusively in hidden cache directories.

3. **Clickable File Links**:
   * All file paths and symbol references in explanations must use the `file://` scheme (e.g. `file:///Users/don/work/git/macos-task-cleaner-gui/Sources/TaskCleanerMenuView.swift`).

---

## 2. Architecture Overview

`TaskCleaner.app` is a lightweight macOS menu bar utility built using Swift 5.9+ and SwiftUI, integrated with AppKit.

* `Sources/TaskCleanerApp.swift`: App lifecycle and `MenuBarExtra` declaration with `.menuBarExtraStyle(.window)`.
* `Sources/TaskCleanerMenuView.swift`: Main SwiftUI popover panel, dynamic list sections, action cards, and footer toolbar.
* `Sources/TaskCleanerViewModel.swift`: State machine, live workspace observers, and async process termination dispatch.
* `Sources/MTCBridge.swift`: Communication bridge invoking the `mtc` Rust core engine and parsing JSON summaries.
* `Sources/LiquidGlassComponents.swift`: Native macOS visual effect wrappers (`VisualEffectBackground`, `SystemCard`, `SystemBadge`, `WindowAutoResizer`).
* `Sources/LaunchAtLoginManager.swift`: Modern macOS 13+ `SMAppService` launch-at-login integration and first-run coordinator.
* `Sources/CliIntegrationManager.swift`: Automated CLI installation, symlink health detection, terminal test execution, and shell PATH integration.
* `Sources/ProcessTelemetrySampler.swift`: Real-time AppKit/CoreGraphics process telemetry sampler for memory, CPU usage, and on-screen window counts.
* `Sources/I18n.swift`: 24-language internationalization dictionary and runtime locale resolution.
* `scripts/build_app.sh`: Automated compilation, resource generation, and DMG disk image packaging.

---

## 3. SwiftUI & AppKit Hard Constraints (Lessons Learned)

### A. Window Auto-Resizing & Anchoring (`MenuBarExtraWindow`)
* **Problem**: macOS `MenuBarExtraWindow` does not automatically reduce its frame height when child SwiftUI views disappear or collapse. Left unhandled, content shrinks while the window remains tall, creating empty space or causing views to shift.
* **Rule**:
  * The top-level container in `TaskCleanerMenuView` must be `ZStack(alignment: .top)` to ensure views are anchored to the top under the status item, never centered vertically.
  * Always attach `WindowAutoResizer(targetWidth: 310)` to the root view.
  * When content `fittingSize.height` changes, `WindowAutoResizer` must calculate `heightDiff = currentFrame.height - fitting.height` and update `window.setFrame(...)` by shifting `origin.y += heightDiff` so that the window's `maxY` (anchored to the menu bar) remains constant.

### B. Material Transitions & CABackdropLayer Ghosting
* **Problem**: Components wrapped in `SystemCard` use `.background(RoundedRectangle(...).fill(.thinMaterial))` and `.overlay(RoundedRectangle(...).strokeBorder(...))`. In macOS AppKit, `Material` is backed by `NSVisualEffectView` and CoreAnimation `CABackdropLayer`, which **does not support opacity animation**.
* **Rule**:
  * Never apply `.transition(.opacity)` or `.transition(.move(edge: .top))` to views containing `.thinMaterial` or `SystemCard`.
  * If animated dismissal is needed, either dismiss views atomically (`shouldShow = false`) or animate inner content opacity while keeping background removal clean.
  * Dismissals must not trigger transitions that translate views into the header or outer frame bounds.

### C. State Mutation Decoupling in UI Actions
* **Problem**: Concurrently modifying an observed state (e.g. `shouldShowPrompt = false`) and an un-animated property on another `@ObservedObject` (e.g. `viewModel.statusMessage = ...`) within the same runloop turn can abort in-flight transitions, freezing temporary view states.
* **Rule**:
  * Decouple secondary UI messages or async status updates using `DispatchQueue.main.asyncAfter` or task scheduling.

### D. AppKit PopUpButton & Menu Sizing
* **Problem**: SwiftUI `Menu` with `.menuStyle(.borderlessButton)` creates an AppKit `NSPopUpButton`. By default, AppKit calculates the button's intrinsic width to fit the longest menu item title (e.g., 107pt for language names). An icon-only label will be padded out to 107pt, pushing adjacent buttons far away.
* **Rule**:
  * When defining an icon-only `Menu` (such as the globe language switcher), always specify `.frame(width: 16, height: 16)` directly on the `Menu` itself, not just on the label's inner `Image`.
  * Keep the globe icon immediately adjacent to the "Quit" button with tight spacing (`HStack(spacing: 6)`).

### E. Right-to-Left (RTL) Layout Adaptations
* **Problem**: In-app language switching to RTL locales (such as Arabic `.ar`) does not automatically alter SwiftUI or AppKit layout direction if left unhandled.
* **Rule**:
  * Inject `.environment(\.layoutDirection, i18n.layoutDirection)` at the root view in `TaskCleanerMenuView`.
  * Pass `isRTL` to `WindowAutoResizer` to synchronize `contentView.userInterfaceLayoutDirection = isRTL ? .rightToLeft : .leftToRight` on the AppKit `NSWindow`.
  * Avoid hardcoded absolute horizontal offsets; use directional logic (e.g. `offset(x: i18n.isRTL ? -3 : 3)`) and directional alignments (`.leading` / `.trailing`).

### F. AppKit Termination & Protected App Management
* **Problem**: macOS `launchd` monitors `Finder`. If killed via raw POSIX signals, `launchd` treats it as a crash and immediately respawns it.
* **Rule**:
  * All foreground applications displayed in `NativeProtectedRow` (including Finder) can be removed from protection by the user via the "Remove" button, moving them to the targets list.
  * When Finder is terminated (either via individual trash icon or batch clean), the underlying `mtc` engine utilizes native AppKit `NSRunningApplication.terminate()` so that Finder exits cleanly without `launchd` respawning it.

### G. Native macOS Context Menus & Action Symmetry
* **Rule**:
  * All application rows (both `NativeTargetRow` and `NativeProtectedRow`) must maintain identical 44pt trailing control footprints (primary action icon + three-dot `Menu`).
  * Both row types must attach full native `.contextMenu` containing `Reveal in Finder` (`folder`), clipboard tools (`doc.on.doc`, `number`), and tier/lifecycle actions.
  * Secondary menus (such as the action section split chevron and footer gear menu) must use SF Symbols with `Label(...)` for authentic macOS vibrancy aesthetics.

### H. Accessibility Permission & TCC Synchronization
* **Problem**:
  1. Polling via default RunLoop mode (`Timer.scheduledTimer`) gets frozen during AppKit menu tracking (`NSEventTrackingRunLoopMode`), preventing live UI updates while the menu is open.
  2. Ad-hoc signed binaries (`codesign -s -`) bind permissions strictly to their ephemeral CDHash. Recompiling invalidates prior TCC grants in System Settings.
  3. Menus with warning symbols (`exclamationmark.triangle`) look like errors; they must use the standard system accessibility symbol (`accessibility`) and display `✓` upon authorization.
  4. Top prompt banners can disrupt window geometry if `appListView` does not dynamically subtract banner height from its 230pt baseline.
* **Rule**:
  * Always register `DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.accessibility.api"))` to receive instant system-wide authorization broadcasts.
  * Always schedule monitoring timers on `RunLoop.main` in `.common` mode so tracking menus never starve detection.
  * Use the standard system `accessibility` symbol for accessibility settings items and inline banners.
  * `appListView` must dynamically calculate `listHeight = 230.0 - (launchPrompt ? 65 : 0) - (accessibilityPrompt ? 34 : 0)` to guarantee the 460pt total window height remains rigid and bottom toolbars are never pushed out.
  * `scripts/build_app.sh install` must always execute `swift build -c release` to ensure new code changes are physically compiled into the app bundle.

### I. Deep Multi-Process & Virtual Machine Memory Aggregation
* **Problem**:
  1. Naive single-PID measurement via `proc_pidinfo(pid, PROC_PIDTASKINFO)` only queries the main frontmost GUI process (e.g. Parallels `prl_client_app` at ~200MB, Chrome browser process at ~280MB).
  2. Complex applications distribute heavy workloads into helper daemons, renderers, and hypervisor VMs (e.g. Parallels `prl_vm_app` taking 4GB-6GB).
  3. Hypervisor/virtualization processes often run under UID 0 (`root`). Direct unprivileged calls to `proc_pidinfo` fail with `EPERM` (errno 1), causing VM memory to be completely missed.
* **Rule**:
  * Both Core (`macos-task-cleaner/src/app.rs`) and GUI (`ProcessTelemetrySampler.swift`) must perform deep multi-process aggregation.
  * Take a system process table snapshot via `/bin/ps -ax -o pid,ppid,rss,%cpu` (which executes in ~15ms and penetrates UID 0 / EPERM barriers thanks to macOS `/bin/ps` setuid root privileges).
  * Associate all system processes with their foreground application using two primary criteria:
    a) **Bundle Directory Ownership**: Binary path (`proc_pidpath`) starts with `<App.bundleURL.path>/` (e.g. `/Applications/Parallels Desktop.app/...`).
    b) **Process Hierarchy Lineage**: Ancestor chain in PPID tree resolves to the application's root PID.
  * Always sum aggregated memory (RSS) and CPU across all associated sub-processes.
  * `scripts/build_app.sh` must automatically check and compile the latest `mtc` Rust engine whenever core or CLI source files are newer than the target binary.

---

## 4. Build & Verification Tiering (CRITICAL EFFICIENCY RULE)

1. **Daily Development & UI Micro-adjustments (Level 1 - STRICT)**:
   * For syntax check, type safety, and view logic verification, **ONLY execute `swift build`**.
   * On Apple Silicon, `swift build` compiles incrementally in 2-4 seconds.
   * **STRICTLY PROHIBITED**: Never run `./scripts/build_app.sh` during iterative UI styling, bug fixing, or feature development. `build_app.sh` invokes `create-dmg` which triggers macOS Finder AppleScript automation (`osascript`), causing 3-5 minute unhandled UI hangs in headless/background execution.

2. **Milestone / Release Packaging (Level 3 - EXPLICIT ONLY)**:
   * Only run `./scripts/build_app.sh arm64` when the user explicitly requests full DMG release packaging or a production distribution binary.
   * If running `build_app.sh` in the background, never poll `manage_task status`; wait for reactive completion notification.

3. **Post-Bugfix Build & Launch Protocol (MANDATORY)**:
   * After completing any bug fix or functional modification, the agent **MUST** automatically execute the following commands to install and launch the updated application for user testing:
     ```bash
     # 1. 编译并安装到 /Applications (耗时约 5-8 秒，仅组装应用 Bundle 与本地签名，自动跳过 DMG 打包)
     ./scripts/build_app.sh install

     # 2. 重新启动已安装的应用供用户测试
     open /Applications/TaskCleaner.app
     ```
   * Never run full DMG packaging (`./scripts/build_app.sh arm64` / `all`) for bug testing; strictly use `./scripts/build_app.sh install`.

---

## 5. Internationalization (I18n) Manual Trigger Policy (STRICT IRONCLAD RULE)

* **User Manual Trigger Only (绝对禁止自动翻译)**:
  - **I18n 的翻译和多语言字典同步只有用户显式手动触发才能执行**。
  - 严禁未经用户明确下达翻译指令（如“同步多语言”、“更新 i18n”、“做国际化”、“翻译文案”）就在修复 bug 或调整 UI 时擅自修改 `Sources/I18n.swift`、添加多语种字典条目或进行多语言机翻。
* **Daily Development / Fast Iteration Rule**:
  - 日常修复与界面微调中，优先使用直观文案或现有既有字段；界面临时文案直接使用内联字符串字面量（`Text("...")`、`Label("...")`）。
* **When Explicitly Commanded by User**:
  - 当且仅当用户显式下达国际化命令时，方可批量准备所有语言（`.en`, `.zhHans`, `.zhHant` 等），并在单次原子批处理中修改（或通过 `python3 scripts/update_i18n.py`），严禁碎裂化 4-way 切片式编辑。

---

## 6. Documentation & Version Control Throttling

* **Post-Bugfix Documentation Synchronization (Continuous Learning)**:
  - After completing each bug fix or resolving a system/UI constraint, the agent **MUST** concisely record the core lesson, root cause pitfall, or architectural rule in `AGENTS.md` (e.g. under Lessons Learned, Build Protocols, or Architecture) to preserve knowledge across future development turns.
* **Inheritance & Architecture Docs**: 
  - Do NOT rewrite or re-export `PROJECT_INHERITANCE_GUIDE.md` or large summary documents for minor UI tweaks or single-property additions.
  - Only update backlog items upon full completion of a major milestone (e.g. Backlog #2, Backlog #3).
* **Git Hygiene**:
  - Avoid redundant polling commands (e.g. running `git status -s` multiple times consecutively without edits).
  - Perform clean, single-point commits only when a feature is functionally complete and verified.

---

## 7. Licensing & Commercial Policy

* **Dual-Licensing Model**:
  * Open-source under **GNU AGPLv3**. Any fork or network service utilizing this code must remain AGPLv3.
  * Proprietary, closed-source bundling, white-labeling, or SaaS deployment requires a separate commercial license.
* **Documentation & Attribution**:
  * Preserve `LICENSE`, `COMMERCIAL.md`, and `TRADEMARK.md` at repository root.
  * Preserve the "About Task Cleaner" dialog (`showAboutDialog()`) presenting version `0.1.0`, copyright notice `Copyright (c) 2026 DonJone. All rights reserved.`, and repository links.
