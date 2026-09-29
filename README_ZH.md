<p align="center">
  <img src="docs/images/app-icon-128.png" width="128" height="128" alt="Task Cleaner 应用图标" />
</p>

<h1 align="center">Task Cleaner</h1>

<p align="center">
  <strong>面向 macOS 的轻量、工程级状态栏任务清场与白名单管理客户端</strong>
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README_ZH.md">简体中文</a>
</p>

<p align="center">
  <a href="https://apple.com/macos"><img src="https://img.shields.io/badge/平台-macOS%2013%2B-000000?logo=apple&logoColor=white" alt="平台: macOS 13+" /></a>
  <img src="https://img.shields.io/badge/架构-Apple%20Silicon%20%7C%20AMD64-blue" alt="架构: Apple Silicon | AMD64" />
  <a href="https://swift.org/"><img src="https://img.shields.io/badge/编程语言-Swift%205.9%2B-F05138?logo=swift&logoColor=white" alt="Swift: 5.9+" /></a>
  <img src="https://img.shields.io/badge/界面库-SwiftUI%20%7C%20AppKit-007AFF?logo=swift&logoColor=white" alt="UI: SwiftUI | AppKit" />
  <a href="https://www.rust-lang.org/"><img src="https://img.shields.io/badge/核心引擎-Rust-dea584?logo=rust&logoColor=white" alt="核心引擎: Rust" /></a>
  <img src="https://img.shields.io/badge/国际化-24%20种语言%20(100%25)-teal" alt="国际化: 24 种语言 (100%)" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/开源协议-GNU%20AGPLv3-blue" alt="开源协议: GNU AGPLv3" /></a>
  <a href="COMMERCIAL.md"><img src="https://img.shields.io/badge/商业许可-可授权-orange" alt="商业许可: 可授权" /></a>
</p>

面向 macOS 状态栏的原生前台任务清场与白名单管理应用。基于 Swift 与 SwiftUI 原生开发，底层深度集成高性能 `macos-task-cleaner-core` Rust 引擎。

---

## 界面效果展示

<p align="center">
  <img src="docs/images/gui-main-zh.png" width="380" alt="macOS Task Cleaner 菜单栏常驻浮层" />
</p>

---

## 核心特性

* **原生菜单栏常驻 (Menu Bar Extra)**：优雅驻留在 macOS 顶部菜单栏，采用纯净白色药丸镂空图标，实时展示未受保护的前台活跃进程计数。
* **多进程树与虚拟机内核级深度遥测**：
  * 深度穿透复杂多进程架构（Chrome 渲染及辅助进程、Electron 后台守护、Xcode 编译分发节点）与虚拟化 Hypervisor 开销（Parallels Desktop `prl_vm_app`、Docker），打通跨 UID 0 / root 权限隔离壁垒。
  * 结合 PPID 祖先树溯源与应用 Bundle 目录归属判定，精准聚合全量物理内存 (RSS) 与 CPU 真实消耗（例如准确捕获并汇总 Parallels 虚拟机的完整 6GB 运行内存，彻底解决传统监控仅识别 ~200MB 前台界面的失真问题）。
* **多维度性能指标与动态实时排序**：
  * 支持按综合负载评分、物理内存占用 (RAM)、CPU 使用率、屏幕可见窗口数四种维度实时动态排序。
  * 支持在设置菜单中自由开关内存与 CPU 实时度量、窗口数统计徽标及应用包标识符 (Bundle Identifier) 的展示。
* **三段式清晰状态栏统计**：
  * **待清理前台任务**：实时统计当前命中清理范围、即将被退出的前台应用数量。
  * **保留常驻 / 已保护**：展示处于 L1 至 L4 各保护层级中的应用总数。
  * **查看全部活动应用**：展开查看当前系统所有活跃前台图形应用。
* **精细化单任务控制与原生上下文菜单**：
  * **单应用独立结束**：列表项右侧提供小垃圾桶图标，支持精准单独退出特定进程。
  * **一键加白与取消**：列表项右侧提供加锁/盾牌图标，点击可一键添加至用户白名单或移除保护。
  * **原生右键上下文菜单**：在任意应用项上右键呼出完整系统菜单，支持在访达中显示、拷贝 PID、拷贝 Bundle ID 及快速分级调整白名单。
* **内置伴生命令行 (`mtc`) 终端管理**：
  * 原生 Rust `mtc` 二进制核心已直接预置打包于应用内，支持在图形界面设置中一键软链接安装至 `~/.local/bin` 或 `/usr/local/bin`。
  * 自动检测终端 Shell 环境并智能写入 PATH 环境变量配置 (`~/.zshrc`)。
  * 内置终端功能连通性实时测试与软链接健康度诊断。
* **全局快捷键与无感知辅助功能 TCC 监听**：
  * 支持可自定义的全局快捷键（默认 `Option + Space`），在任意全屏空间与桌面一键即时呼出清理控制台。
  * 接入 `DistributedNotificationCenter` 监听系统无障碍授权广播 (`com.apple.accessibility.api`)，彻底消除菜单跟踪期间的 RunLoop 轮询卡顿。
* **一键全部清理**：点击底部的“全部清理”按钮，瞬时优雅平稳退出全部未加白的前台应用。
* **原生 AppKit 访达 (Finder) 退出协议**：通过调用 `NSRunningApplication.terminate()` 退出访达，使系统守护进程 `launchd` 识别为自愿退出，彻底解决传统 POSIX `kill` 导致的“闪退又瞬间弹回”复活死循环。
* **无损分级降级清场**：触发 `SIGTERM -> 宽限期轮询 -> SIGKILL` 三段式安全退出协议，绕过应用层阻塞式保存确认弹窗。
* **对标系统级实用工具质感**：严格遵循 Apple HIG 规范，采用深色监视器屏幕基底、暗调微网格与微浮雕操作按钮。
* **100% 完整覆盖 24 种国际语言与 RTL 支持**：全部 24 种语言均已达成 100% 词条全量覆盖（116/116 键），遵循 Apple 官方本地化术语体系，完美支持阿拉伯语等从右向左 (RTL) 界面的原生镜像翻转布局。
* **开机自启动引导与常驻守护**：基于 macOS 13+ 原生 `SMAppService` 框架构建，零后台守护常驻开销，支持在设置菜单随时一键开关。

---

## 下载与快速安装

### 方式一：推荐 DMG 拖拽式安装镜像

前往 [GitHub Releases](https://github.com/macos-task-cleaner/macos-task-cleaner-gui/releases/latest) 直接下载适用于您 Mac 架构的安装镜像：

| 硬件架构 | 适用设备 | 安装包直链下载 |
| :--- | :--- | :--- |
| **Apple Silicon** (`arm64`) | Apple M1 / M2 / M3 / M4 芯片 Mac | [TaskCleaner-macOS-arm64.dmg](https://github.com/macos-task-cleaner/macos-task-cleaner-gui/releases/latest/download/TaskCleaner-macOS-arm64.dmg) |
| **AMD64 / Intel** (`x86_64`) | Intel 处理器 / AMD64 架构 Mac | [TaskCleaner-macOS-x86_64.dmg](https://github.com/macos-task-cleaner/macos-task-cleaner-gui/releases/latest/download/TaskCleaner-macOS-x86_64.dmg) |
| **Universal** (`universal`) | 兼容全部 Apple Silicon 及 Intel Mac | [TaskCleaner-macOS-universal.dmg](https://github.com/macos-task-cleaner/macos-task-cleaner-gui/releases/latest/download/TaskCleaner-macOS-universal.dmg) |

双击打开下载的 `.dmg` 文件后，直接将 `Task Cleaner.app` 拖入 `Applications` 文件夹即可完成安装。

### 方式二：源码本地编译

要求 macOS 13.0+ 及 Swift 5.9+ / Xcode 环境：

```bash
git clone https://github.com/macos-task-cleaner/macos-task-cleaner-gui.git
cd macos-task-cleaner-gui

# 使用内置脚本一键编译并组装（支持参数: arm64 | x86_64 | universal | all | native）
./scripts/build_app.sh

# 移动至应用程序目录并启动
cp -R build/TaskCleaner.app /Applications/
open /Applications/TaskCleaner.app
```

---

## 项目代码结构

* `Sources/TaskCleanerApp.swift`：应用程序入口与 `MenuBarExtra` 声明、托盘原生矢量绘制
* `Sources/TaskCleanerMenuView.swift`：SwiftUI 交互浮层面板、动态高度协调器、应用行视图与操作菜单
* `Sources/TaskCleanerViewModel.swift`：状态机管理、异步扫描与清场调度
* `Sources/MTCBridge.swift`：与底层 `mtc` 引擎及 TOML 配置的通信桥接层
* `Sources/ProcessTelemetrySampler.swift`：基于 AppKit 与 CoreGraphics 的实时深度多进程内存、CPU 与窗口遥测采样器
* `Sources/CliIntegrationManager.swift`：内置伴生 CLI 软链接自动化部署、PATH 环境变量注入与终端测试协调器
* `Sources/LiquidGlassComponents.swift`：原生视觉材质封装与 `MenuBarExtraWindow` 动态尺寸协调器
* `Sources/LaunchAtLoginManager.swift`：原生 `SMAppService` 开机自启动集成与首次引导协调器
* `Sources/I18n.swift`：24 种语言 100% 完整词条国际化注册表与运行时多语言切换器
* `Sources/Models.swift`：数据模型定义与应用图标动态提取
* `scripts/build_app.sh`：自动编译、增量 Rust 核心检查、`TaskCleaner.app` 组装及 DMG 可视化拖拽安装盘生成脚本
* `scripts/generate_app_icon.swift`：应用官方 AppIcon 矢量生成器
* `scripts/generate_dmg_background.swift`：2x Retina 分辨率 DMG 拖拽安装背景图生成器

---

## 命令行客户端伴随工具

原生的 Rust 命令行客户端 **`mtc`** 已经直接集成内置在 `Task Cleaner.app` 内部。您可以在数秒内将其配置到终端：

1. 从菜单栏打开 `Task Cleaner`。
2. 点击右下角齿轮设置图标，选择 **安装命令行工具 (`mtc`)**。
3. 应用将自动在 `~/.local/bin` 或 `/usr/local/bin` 中创建软链接，并自动完成 Shell PATH (`~/.zshrc`) 配置。

如需独立使用或参与 CLI 源码开发：
* **CLI 仓库**：[macos-task-cleaner-cli](https://github.com/macos-task-cleaner/macos-task-cleaner-cli)
* **核心引擎**：[macos-task-cleaner-core](https://github.com/macos-task-cleaner/macos-task-cleaner-core)

图形客户端与命令行工具共用同一份白名单配置文件（`~/.config/mtc/config.toml`），无论在菜单栏图形界面还是终端添加的白名单规则均自动保持双向同步。

---

## 许可协议与商业授权

本项目采用双重授权模式（Dual-Licensing Model）：

1. **开源许可证**：遵循 **GNU Affero General Public License v3.0 (AGPLv3)** 协议。个人学习、学术研究与非商业开源项目可免费使用与修改；凡修改或基于本项目构建衍生作品（包括通过网络提供交互服务的 SaaS / 云端调用形态），均须向公众无偿开源全部衍生代码。详见 [LICENSE](LICENSE)。
2. **商业许可协议 (Commercial License)**：面向企业客户、闭源专有产品集成、白标重命名销售或无法遵守 AGPLv3 传染性条款的商业场景，必须事先取得商业授权许可证。详见 [COMMERCIAL.md](COMMERCIAL.md)。
3. **商标与品牌保护**：项目名称、标识图形与应用图标均受版权及商标保护。任何二次分发或分叉 (Fork) 版本必须彻底去除官方品牌元素。详见 [TRADEMARK.md](TRADEMARK.md)。

Copyright (c) 2026 DonJone. 保留所有权利。
