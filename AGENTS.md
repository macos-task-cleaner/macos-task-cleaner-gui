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

---

## 4. Build & Verification Tiering (CRITICAL EFFICIENCY RULE)

1. **Daily Development & UI Micro-adjustments (Level 1 - STRICT)**:
   * For syntax check, type safety, and view logic verification, **ONLY execute `swift build`**.
   * On Apple Silicon, `swift build` compiles incrementally in 2-4 seconds.
   * **STRICTLY PROHIBITED**: Never run `./scripts/build_app.sh` during iterative UI styling, bug fixing, or feature development. `build_app.sh` invokes `create-dmg` which triggers macOS Finder AppleScript automation (`osascript`), causing 3-5 minute unhandled UI hangs in headless/background execution.

2. **Milestone / Release Packaging (Level 3 - EXPLICIT ONLY)**:
   * Only run `./scripts/build_app.sh arm64` when the user explicitly requests full DMG release packaging or a production distribution binary.
   * If running `build_app.sh` in the background, never poll `manage_task status`; wait for reactive completion notification.

3. **Application Installation Throttling**:
   * Do NOT automatically terminate (`pkill -f TaskCleanerGUI`) and overwrite `/Applications/TaskCleaner.app` on minor UI/logic iterations.
   * Only deploy to `/Applications` when the user explicitly instructs to run/test the installed app in the system menu bar.

---

## 5. Internationalization (I18n) Decoupling & Manual Trigger (STRICT)

* **Decoupling Principle**: Full multi-lingual dictionary synchronization (`Sources/I18n.swift`) is strictly decoupled from daily feature development and UI prototyping.
* **Prohibited**:
  - Never proactively modify `Sources/I18n.swift` (adding new `I18nKey` enums or multi-lingual dictionary entries) during routine UI adjustments, bug fixes, or incremental feature delivery.
  - Never block a fast UI fix on four-language dictionary synchronization.
* **Daily Development / Fast Iteration Rule**:
  - Use inline string literals (e.g. `Text("...")`, `Button("...")`, `Label("...")`) or raw string fallbacks directly in SwiftUI views for new UI elements, labels, or toggles.
* **Manual Trigger Requirement (User-Driven)**:
  - Agent must ONLY update `Sources/I18n.swift` when the user **explicitly commands** it (e.g., "同步多语言", "更新 i18n", "翻译新加的文案", "做国际化").
  - When explicitly triggered by the user:
    - Prepare all language updates (key enum, `.en`, `.zhHans`, `.zhHant`) in memory and apply them in a **single atomic edit** (or via `python3 scripts/update_i18n.py`);
    - Strictly prohibited from performing fragmented 4-way slice editing.

---

## 6. Documentation & Version Control Throttling

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
