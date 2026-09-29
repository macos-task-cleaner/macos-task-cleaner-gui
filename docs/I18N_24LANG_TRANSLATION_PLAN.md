# macOS Task Cleaner GUI - 24 语种全量国际化 (I18n) 低算力模型执行计划书

* 文档编号: `MTC-I18N-20260929-PLAN`
* 适用执行模型: Gemini 2.5 Flash / Flash Lite / GPT-4o-mini / Claude 3.5 Haiku 等轻量级高性价比模型
* 目标代码库: [macos-task-cleaner-gui](file:///Users/don/work/git/macos-task-cleaner-gui)
* 核心操作文件: [Sources/I18n.swift](file:///Users/don/work/git/macos-task-cleaner-gui/Sources/I18n.swift)
* 辅助自动化脚本:
  - 自动注入器: [scripts/batch_inject_i18n.py](file:///Users/don/work/git/macos-task-cleaner-gui/scripts/batch_inject_i18n.py)
  - 覆盖率核验器: [scripts/verify_i18n.py](file:///Users/don/work/git/macos-task-cleaner-gui/scripts/verify_i18n.py)
  - 待译词条基准模板: [scripts/i18n_missing_keys_template.json](file:///Users/don/work/git/macos-task-cleaner-gui/scripts/i18n_missing_keys_template.json)

---

## 1. 任务背景与核心目标

### 1.1 背景说明
`TaskCleaner.app` 是面向 macOS 的前台任务清理工具，原生支持 24 种语言。在此前迭代中，应用增加了以下功能：
1. 无障碍权限 (Accessibility) 动态状态感知与实时横幅。
2. 命令行工具 (`mtc`) 自动化安装、符号链接健康探测、终端自测与 PATH 环境变量整合。
3. 进程列表多维度排序 (综合负载、内存、CPU、窗口数) 与视觉度量展示。

这些新增特性共增加了 **35 个全新的 I18n 词条**。
目前基准语言（英语 `en`、简体中文 `zhHans`、繁体中文 `zhHant`）已完成 100%（116/116 键）覆盖，其余 21 种语言均为 81/116 键（缺失这 35 个词条）。

### 1.2 为什么使用 Low-Tier (低算力) 模型执行
* **翻译任务的高冗余性**：纯字典文本翻译属于高度并行、规则明确的确定性任务，调用顶级模型（如 Gemini 3.8 High / Claude 3.5 Opus）单轮消耗数万甚至数十万 Token，性价比极低。
* **低算力模型的适配优势**：Gemini Flash 等轻量模型在多语言词条对齐、标准系统术语翻译上具备极高精度，且吞吐速度极快。
* **工程安全防护**：为避免低算力模型直接编辑 2500+ 行庞大 Swift 文件时出现括号不匹配、字符转义破损或编译报错，本项目已设计并提供了**纯 JSON 中转 + Python 自动化原子注入**机制。低算力模型仅需输出干净的 JSON 文本，由脚本注入并自动核验，零语法风险。

---

## 2. 语种全景与缺失状态审计

### 2.1 语种支持列表 (共 24 种)
* **基准全量语种 (100% 已就绪，共 3 种)**:
  - `en`: English
  - `zhHans`: 简体中文
  - `zhHant`: 繁體中文
* **待补齐语种 (缺失 35 键，当前 69.8%，共 21 种)**:
  1. `ja`: 日本語 (Japanese)
  2. `ko`: 한국어 (Korean)
  3. `fr`: Français (French)
  4. `de`: Deutsch (German)
  5. `es`: Español (Spanish)
  6. `pt`: Português (Portuguese)
  7. `it`: Italiano (Italian)
  8. `ru`: Русский (Russian)
  9. `nl`: Nederlands (Dutch)
  10. `pl`: Polski (Polish)
  11. `tr`: Türkçe (Turkish)
  12. `ar`: العربية (Arabic - 注意: RTL 右至左排版)
  13. `th`: ไทย (Thai)
  14. `vi`: Tiếng Việt (Vietnamese)
  15. `id`: Bahasa Indonesia (Indonesian)
  16. `sv`: Svenska (Swedish)
  17. `da`: Dansk (Danish)
  18. `nb`: Norsk Bokmål (Norwegian)
  19. `fi`: Suomi (Finnish)
  20. `cs`: Čeština (Czech)
  21. `uk`: Українська (Ukrainian)

总翻译量: `21 语种 * 35 词条 = 735 字符串`。

---

## 3. 分批执行策略 (3 个 Batch)

为保证低算力模型在单次上下文窗口内不发生截断，建议分 3 个批次（每批 7 种语言，约 245 个词条）递进生成：

| 批次 | 语种代码 | 涵盖语言 | 交付中间文件名 |
| :--- | :--- | :--- | :--- |
| **Batch 1** | `ja`, `ko`, `th`, `vi`, `id`, `ar`, `tr` | 亚洲语系 + 中东/突厥 (含 RTL 阿拉伯语) | `/tmp/i18n_batch_1.json` |
| **Batch 2** | `fr`, `de`, `es`, `pt`, `it`, `nl`, `pl` | 西欧核心语系 + 波兰语 | `/tmp/i18n_batch_2.json` |
| **Batch 3** | `ru`, `uk`, `cs`, `sv`, `da`, `nb`, `fi` | 东欧斯拉夫语系 + 北欧语系 | `/tmp/i18n_batch_3.json` |

---

## 4. 待补齐的 35 个词条基准对齐表

所有翻译必须严格保持占位符（如 `%@`, `%d`）与换行符 `\n` 不变。

| 序号 | I18nKey 枚举键 | 英文基准 (en) | 中文基准 (zhHans) | 占位符与上下文说明 |
| :---: | :--- | :--- | :--- | :--- |
| 1 | `accessibility_prompt_title` | Global Shortcut Accessibility Access | 全局快捷键未开启辅助功能 | 顶部警告横幅标题 |
| 2 | `accessibility_prompt_desc` | Global shortcut requires Accessibility permission to detect hotkeys across applications. | 全局快捷键需要辅助功能权限以确保在后台及各应用中稳定触发。 | 顶部警告横幅正文 |
| 3 | `btn_grant_permission` | Enable | 去开启 | 横幅右侧操作按钮 |
| 4 | `menu_accessibility_status` | Accessibility Permission | 无障碍权限 | 齿轮设置菜单状态项 |
| 5 | `menu_grant_accessibility` | Grant Accessibility Access... | 授予辅助功能权限... | 齿轮菜单未授权时跳转项 |
| 6 | `status_accessibility_granted` | Accessibility permission granted | 辅助功能权限已授予 | 底部状态栏 Toast 提示 |
| 7 | `shortcut_recorder_accessibility_warning` | Accessibility permission is required for global hotkeys to trigger outside this window. | 全局热键需授予辅助功能权限方可在其他应用中激活。 | 快捷键录制弹窗说明 |
| 8 | `cli_label_ready` | Ready | 已就绪 | 齿轮菜单 CLI 就绪徽标 |
| 9 | `cli_status_installed` | Installed | 已安装 | 命令行工具状态描述 |
| 10 | `cli_status_broken` | Broken Link | 软链接失效 | 命令行软链接指向异常 |
| 11 | `cli_status_not_installed` | Not Installed in PATH | 未安装到终端 PATH | 命令行未链接状态描述 |
| 12 | `menu_cli_tools` | Command-Line Tool (mtc) | 命令行工具 (mtc) | 齿轮二级菜单分组标题 |
| 13 | `menu_install_cli_user` | Install to ~/.local/bin (Recommended) | 安装到 ~/.local/bin (当前用户推荐) | 菜单项 |
| 14 | `menu_install_cli_system` | Install to /usr/local/bin (All Users) | 安装到 /usr/local/bin (所有用户) | 菜单项 (需 sudo) |
| 15 | `menu_test_cli_terminal` | Test in Terminal (mtc --help) | 在终端中测试运行 (mtc --help) | 菜单项 |
| 16 | `menu_test_in_terminal_format` | Test in %@ (mtc --help) | 在 %@ 中测试运行 (mtc --help) | 占位符: 终端名 (如 iTerm) |
| 17 | `menu_reveal_cli_finder` | Reveal in Finder | 在访达中显示 | 菜单项定位二进制文件 |
| 18 | `menu_uninstall_cli` | Remove 'mtc' from PATH | 从 PATH 中移除软链接 | 菜单卸载项 |
| 19 | `status_cli_uninstalled` | Removed 'mtc' CLI symlink | 已移除 mtc 命令行软链接 | 状态栏 Toast |
| 20 | `install_cli_path_missing_title` | Directory Not in PATH | 目录未包含在 PATH 中 | 引导弹窗标题 |
| 21 | `install_cli_path_missing_desc` | The 'mtc' tool has been linked to:\n%@\n\nNotice: This directory is not currently in your shell's PATH environment. Would you like to append it to ~/.zshrc? | 已将 mtc 软链接至:\n%@\n\n提示: 检测到该目录尚未包含在当前终端的 PATH 环境变量中。是否自动将其添加至 ~/.zshrc？ | 占位符: 路径；含 `\n` |
| 22 | `btn_add_to_zshrc` | Add to ~/.zshrc | 自动写入 ~/.zshrc | 按钮 |
| 23 | `status_zshrc_updated` | Appended PATH to ~/.zshrc | 已成功将 PATH 写入 ~/.zshrc | 状态栏 Toast |
| 24 | `menu_terminal_picker` | Test Terminal | 测试终端 | 子菜单标题 |
| 25 | `sort_by` | Sort | 排序方式 | 顶栏/卡片排序标题 |
| 26 | `sort_composite` | Composite Load | 综合负载 | 排序维度 |
| 27 | `sort_memory` | Memory Usage | 内存占用 | 排序维度 |
| 28 | `sort_cpu` | CPU Usage | CPU 占用 | 排序维度 |
| 29 | `sort_windows` | Window Count | 窗口数量 | 排序维度 |
| 30 | `sort_default` | Default Order | 默认顺序 | 排序维度 |
| 31 | `unit_windows` | windows | 窗口 | 复数单位词 (如 3 windows) |
| 32 | `unit_window_singular` | window | 窗口 | 单数单位词 (如 1 window) |
| 33 | `menu_show_detailed_metrics` | Show Resource Metrics | 显示详细资源数值 | 齿轮显示开关 |
| 34 | `menu_show_app_identifier` | Show App Identifier | 显示应用标识符 | 齿轮显示开关 |
| 35 | `menu_show_sort_button` | Show Sort Button in Header | 顶栏显示排序按钮 | 齿轮显示开关 |

---

## 5. 自动化工具链使用指南

### 5.1 数据结构规范 (JSON 格式)
低算力模型生成的翻译文件需遵循如下结构：
```json
{
  "ja": {
    "accessibility_prompt_title": "ショートカットのアクセシビリティ",
    "accessibility_prompt_desc": "グローバルショートカットには、他のアプリ間でホットキーを検出するためのアクセシビリティ権限が必要です。",
    "btn_grant_permission": "許可する"
  },
  "ko": {
    "accessibility_prompt_title": "단축키 손쉬운 사용 권한",
    "accessibility_prompt_desc": "글로벌 단축키가 앱 간에 동작하려면 손쉬운 사용 권한이 필요합니다.",
    "btn_grant_permission": "활성화"
  }
}
```

### 5.2 自动注入脚本执行
使用项目内置的注入工具执行安全合流：
```bash
# 语法: python3 scripts/batch_inject_i18n.py <翻译JSON文件>
python3 scripts/batch_inject_i18n.py /tmp/i18n_batch_1.json
python3 scripts/batch_inject_i18n.py /tmp/i18n_batch_2.json
python3 scripts/batch_inject_i18n.py /tmp/i18n_batch_3.json
```
* **幂等安全**：脚本会自动扫描目标语言字典，若某个键已存在则安全跳过，绝不产生重复词条。
* **安全转义**：自动处理双引号 `\"` 与换行符 `\n`，保证生成的 Swift 语法绝对合法。

### 5.3 完整度核验与构建验证
```bash
# 1. 运行完整度审计脚本 (校验 24 语种是否全量达到 116/116 键)
python3 scripts/verify_i18n.py

# 2. 快速静态编译语法检查 (验证 Swift 字典与枚举类型安全，耗时约 3 秒)
swift build
```

---

## 6. 发送给 Low 算力模型的即用 Prompt 模板

用户可直接复制以下 Prompt 依次发送给低算力模型（如 Flash / Haiku）：

### Prompt: 第一批 (Batch 1 - 亚洲与中东语系)
```markdown
请你扮演 macOS 原生软件本地化专家。请为轻量级 macOS 工具 Task Cleaner 翻译以下 35 个 UI 词条。
目标语种代码共 7 个:
1. "ja" (日本語)
2. "ko" (한국어)
3. "th" (ไทย)
4. "vi" (Tiếng Việt)
5. "id" (Bahasa Indonesia)
6. "ar" (العربية - 遵循 Apple 阿拉伯语 RTL 原生术语)
7. "tr" (Türkçe)

翻译与排版硬性约束:
1. 严禁修改或遗漏占位符: 保留 "%@" (应用名/路径/终端名) 与 "%d" (数字)。
2. 保持换行符: "\n" 必须原样保留在字符串中。
3. 遵循 macOS 原生系统术语: 如 Finder、Accessibility (アクセシビリティ / 손쉬운 사용 / 辅助功能)、Symlink (シンボリックリンク / 심볼릭 링크)、Terminal (ターミナル / 터미널)。
4. 只输出纯 JSON 格式，不要包含任何 markdown 代码块外部的闲聊文本，JSON 顶级 key 为语言代码。

待翻译的 35 个词条基准 (英文与中文对照):
- accessibility_prompt_title: "Global Shortcut Accessibility Access" / "全局快捷键未开启辅助功能"
- accessibility_prompt_desc: "Global shortcut requires Accessibility permission to detect hotkeys across applications." / "全局快捷键需要辅助功能权限以确保在后台及各应用中稳定触发。"
- btn_grant_permission: "Enable" / "去开启"
- menu_accessibility_status: "Accessibility Permission" / "无障碍权限"
- menu_grant_accessibility: "Grant Accessibility Access..." / "授予辅助功能权限..."
- status_accessibility_granted: "Accessibility permission granted" / "辅助功能权限已授予"
- shortcut_recorder_accessibility_warning: "Accessibility permission is required for global hotkeys to trigger outside this window." / "全局热键需授予辅助功能权限方可在其他应用中激活。"
- cli_label_ready: "Ready" / "已就绪"
- cli_status_installed: "Installed" / "已安装"
- cli_status_broken: "Broken Link" / "软链接失效"
- cli_status_not_installed: "Not Installed in PATH" / "未安装到终端 PATH"
- menu_cli_tools: "Command-Line Tool (mtc)" / "命令行工具 (mtc)"
- menu_install_cli_user: "Install to ~/.local/bin (Recommended)" / "安装到 ~/.local/bin (当前用户推荐)"
- menu_install_cli_system: "Install to /usr/local/bin (All Users)" / "安装到 /usr/local/bin (所有用户)"
- menu_test_cli_terminal: "Test in Terminal (mtc --help)" / "在终端中测试运行 (mtc --help)"
- menu_test_in_terminal_format: "Test in %@ (mtc --help)" / "在 %@ 中测试运行 (mtc --help)"
- menu_reveal_cli_finder: "Reveal in Finder" / "在访达中显示"
- menu_uninstall_cli: "Remove 'mtc' from PATH" / "从 PATH 中移除软链接"
- status_cli_uninstalled: "Removed 'mtc' CLI symlink" / "已移除 mtc 命令行软链接"
- install_cli_path_missing_title: "Directory Not in PATH" / "目录未包含在 PATH 中"
- install_cli_path_missing_desc: "The 'mtc' tool has been linked to:\n%@\n\nNotice: This directory is not currently in your shell's PATH environment. Would you like to append it to ~/.zshrc?" / "已将 mtc 软链接至:\n%@\n\n提示: 检测到该目录尚未包含在当前终端的 PATH 环境变量中。是否自动将其添加至 ~/.zshrc？"
- btn_add_to_zshrc: "Add to ~/.zshrc" / "自动写入 ~/.zshrc"
- status_zshrc_updated: "Appended PATH to ~/.zshrc" / "已成功将 PATH 写入 ~/.zshrc"
- menu_terminal_picker: "Test Terminal" / "测试终端"
- sort_by: "Sort" / "排序方式"
- sort_composite: "Composite Load" / "综合负载"
- sort_memory: "Memory Usage" / "内存占用"
- sort_cpu: "CPU Usage" / "CPU 占用"
- sort_windows: "Window Count" / "窗口数量"
- sort_default: "Default Order" / "默认顺序"
- unit_windows: "windows" / "窗口"
- unit_window_singular: "window" / "窗口"
- menu_show_detailed_metrics: "Show Resource Metrics" / "显示详细资源数值"
- menu_show_app_identifier: "Show App Identifier" / "显示应用标识符"
- menu_show_sort_button: "Show Sort Button in Header" / "顶栏显示排序按钮"
```

*(同理，第二批与第三批仅需替换语种代码列表即可完成完整闭环)*。

---

## 7. 执行闭环检查清单 (Checklist)

* [ ] 生成 Batch 1 翻译 (`ja, ko, th, vi, id, ar, tr`) -> 写入 `/tmp/i18n_batch_1.json` 并运行 `python3 scripts/batch_inject_i18n.py /tmp/i18n_batch_1.json`。
* [ ] 生成 Batch 2 翻译 (`fr, de, es, pt, it, nl, pl`) -> 写入 `/tmp/i18n_batch_2.json` 并运行 `python3 scripts/batch_inject_i18n.py /tmp/i18n_batch_2.json`。
* [ ] 生成 Batch 3 翻译 (`ru, uk, cs, sv, da, nb, fi`) -> 写入 `/tmp/i18n_batch_3.json` 并运行 `python3 scripts/batch_inject_i18n.py /tmp/i18n_batch_3.json`。
* [ ] 运行 `python3 scripts/verify_i18n.py`，确认全部 24 语种均输出 `[PASS] (100.0%)`。
* [ ] 运行 `swift build`，确认编译耗时 2-4 秒且无任何语法或转义报错。
* [ ] 执行 `./scripts/build_app.sh install && open /Applications/TaskCleaner.app`，进入应用切换不同语种验证界面视觉与字符宽度适应。
