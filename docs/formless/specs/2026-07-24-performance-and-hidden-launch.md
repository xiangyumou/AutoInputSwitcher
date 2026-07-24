# AutoInputSwitcher 综合优化 Specification

**Status:** Approved

## Problem

AutoInputSwitcher 在三方面有改进空间：

1. **开机自启体验**：窗口在启动时总是弹出，开机自启场景下不必要地打断用户。
2. **启动速度**：`InstalledApplicationScanner` 在 `AppRuntime.init()` 中同步扫描所有已安装应用，主线程执行大量磁盘 I/O（遍历目录、解析数百个 `.app` 的 Info.plist、加载图标），导致窗口出现前有明显卡顿。
3. **无处唤回**：窗口关闭后，app 仍在后台运行但没有菜单栏图标、没有 Dock 图标，用户无法找回窗口，只能重新运行可执行文件。

此外，`SystemInputSourceManager` 每次调用都通过 Carbon TIS API 重新创建输入源列表，`JSONRuleStore` 每次同步读写文件，均可通过缓存改善。

## Goals

- [x] 应用启动时默认不显示窗口，仅在用户主动触发时出现
- [x] 添加菜单栏图标作为主交互入口，用户可通过设置选择是否隐藏
- [x] 应用列表后台异步加载，不阻塞主线程和窗口渲染
- [x] 应用图标懒加载，启动时不读取大量 `.app` 图标
- [x] 输入源列表缓存复用，避免重复 Carbon API 调用
- [x] 规则文件读取后内存缓存，避免重复磁盘 I/O

## Non-Goals

- 不改变 `LSUIElement = true` 的设定（保持无 Dock 图标）
- 不引入 Spotlight/NSMetadataQuery 扫描（后台异步已足够）
- 不修改现有的自动切换逻辑和规则引擎
- 不添加额外的非必要 UI 元素

## Background

App 使用 `SMAppService.mainApp` 注册/注销开机自启。当前的启动流程是：

```
main → NSApplicationMain → AppDelegate.applicationDidFinishLaunching
  → setActivationPolicy(.accessory) → AppRuntime.init()
    → InstalledApplicationScanner.scan() // 同步阻塞 1-3s
    → SystemInputSourceManager.availableInputSources()
    → JSONRuleStore.load()
    → NSWorkspace.icon(forFile:) for each app
  → showWindow() // 窗口立即弹出
```

菜单栏通过 `NSStatusItem` 实现，这是 macOS 后台标准 app 的管理入口。目前完全缺失该组件。

## Decisions

### D1: 启动窗口行为

**Choice:** 启动始终隐藏，首次安装时例外

**Rationale:** 启动时判断登录来源不靠谱且复杂。统一规则更简单可靠：

- `applicationDidFinishLaunching` 中不自动调用 `showWindow()`
- 用户通过菜单栏图标点击唤出窗口
- 已运行时从 Launchpad/Finder 再次打开 app 会触发 `applicationShouldHandleReopen`，此时显示窗口
- 首次启动（规则文件不存在）显示窗口，方便用户初始配置

### D2: 菜单栏图标

**Choice:** 默认启用菜单栏图标，可在设置中隐藏

**Rationale:** 菜单栏图标是调出窗口的主入口。隐藏后 app 行为回归现状（仅后台运行，无可见存在）。隐藏/显示无需重启即时生效。

### D3: 异步加载策略

**Choice:** 应用列表后台异步加载

**Rationale:** 用 `Task { @MainActor in }` 将 `InstalledApplicationScanner.scan()` 放到后台队列，完成后在主线程更新 UI。相比 Spotlight 索引方案更直接、更可控，改动最小。

### D4: 懒加载与缓存

**Choice:** 图标懒加载 + 输入源和规则缓存

**Rationale:**
- 图标懒加载：仅在表格需要渲染某行时才加载 `NSWorkspace.icon(forFile:)`。用 `LazyImage` 或 `AsyncImage` 模式实现。
- 输入源缓存：`SystemInputSourceManager` 内部缓存列表，`reloadInputSources()` 时刷新。
- 规则缓存：`JSONRuleStore` 加载到 `AppRuntime` 后只存一份内存引用，仅在保存时写磁盘。

## Design

### 启动流程（新）

```
main → NSApplicationMain → AppDelegate.applicationDidFinishLaunching
  → setActivationPolicy(.accessory)
  → 注册菜单栏 (NSStatusItem)
  → AppRuntime.init(async: true) // 不阻塞
    → Task { 后台队列
        InstalledApplicationScanner.scan()
        ☞ 主线程 reload UI
      }
    → SystemInputSourceManager.availableInputSources() (缓存)
    → JSONRuleStore.load() (缓存)
  → if 首次启动（规则文件为空）→ showWindow()
  → else → 不显示窗口，菜单栏已就绪
```

### 菜单栏组件

```
AppDelegate
  ├── statusItem: NSStatusItem  (keyboard icon, SF Symbol)
  ├── statusItem.button.action → toggleWindow()
  └── statusItem.menu → [显示窗口, 设置, 关于, 退出]
```

- `statusItem` 使用 `NSStatusItem.systemStatusBar` 创建，长度 `NSStatusItem.variableLength`
- 点击 action 切换窗口显示/隐藏
- 右键菜单固定包含「显示窗口」和「退出」项
- 设置中切换隐藏时：隐藏 → `statusItem.isVisible = false`，显示 → `true`

### 异步加载

```swift
// AppRuntime
func loadApplications() async {
    let applications = await Task.detached(priority: .userInitiated) {
        InstalledApplicationScanner().scan()
    }.value
    await MainActor.run {
        self.installedApplications = applications
    }
}
```

- 窗口 ContentView 在应用列表为空时显示加载中状态（ProgressView）
- 收到加载完成信号后自动切换为表格

### 图标懒加载

- `InstalledApplication` 去掉 `icon: NSImage` 属性（或改为 lazy computed）
- 表格中通过 `AsyncImage` 或自定义 `loadIcon(for:)` 方法按需加载
- 或使用 NSTableView/NSCollectionView 的 cell 重用 + 延迟 icon 设置

简单方案：在 View 层缓存已加载的 icon：

```swift
@State private var loadedIcons: [String: NSImage] = [:]

func icon(for app: InstalledApplication) -> NSImage? {
    if let icon = loadedIcons[app.bundleIdentifier] { return icon }
    let icon = NSWorkspace.shared.icon(forFile: app.url.path)
    loadedIcons[app.bundleIdentifier] = icon
    return icon
}
```

### 输入源缓存

```swift
final class SystemInputSourceManager {
    private var cachedInputSources: [InputSource]?

    func availableInputSources() -> [InputSource] {
        if let cached = cachedInputSources { return cached }
        // ... 原逻辑 ...
        cachedInputSources = result
        return result
    }

    func invalidateCache() {
        cachedInputSources = nil
    }
}
```

`reloadInputSources()` 内部调用 `invalidateCache()`，下次查询时重新构建。

### 规则缓存

`AppRuntime` 的 `ruleSet: RuleSet` 属性已经是内存中的唯一来源，无需额外缓存。`saveRules()` 写入文件，`load()` 在 init 时从文件读取到内存。确保文件读取走 `async` 避免阻塞。

## Interfaces and Data Flow

### 新增设置项

UserDefaults:
- `showMenuBarIcon` (Bool, 默认 true): 是否显示菜单栏图标
- `hasCompletedInitialSetup` (Bool, 默认 false): 首次启动标记

### AppDelegate 新增/修改

| 方法 | 变化 |
|---|---|
| `applicationDidFinishLaunching` | 移除 `showWindow()` 的自动调用；添加菜单栏创建 |
| `showWindow()` | 不变（从 nil 创建 window，de-miniaturize，order front） |
| `toggleWindow()` | 新增：若窗口可见 → `window?.close()`，否则 → `showWindow()` |
| `updateMenuBarIconVisibility()` | 新增：响应设置变化，显隐 statusItem |

## Errors and Edge Cases

- **首次启动无规则文件**：弹窗引导配置，否则用户以为 app 没安装成功
- **菜单栏隐藏后无入口**：告知用户可通过重新从 Finder 打开 app（`applicationShouldHandleReopen`）唤出窗口，再开启菜单栏
- **异步加载失败**：扫描失败不影响窗口，显示空列表+错误提示；用户可手动点「刷新」
- **图标加载失败**：用 NSWorkspace 默认应用图标作为 fallback
- **后台加载中用户退出**：Task 的优先级不会阻止 app 正常退出

## Compatibility and Rollout

- 向后兼容：旧的 rules.json 格式不变
- 行为变化：已有用户升级后，下次启动时窗口不再自动弹出（通过菜单栏可访问），不影响已配置的规则
- 若用户升级后发现窗口不见了，通知文案提示「点击菜单栏图标或重新从应用文件夹打开」

## Acceptance Criteria

- [ ] 应用在首次启动时显示窗口（用户可配置规则）
- [ ] 非首次启动时窗口默认不弹出
- [ ] 菜单栏图标默认可见，左键切换窗口显隐，右键菜单有退出选项
- [ ] 设置中可隐藏/显示菜单栏图标，即时生效
- [ ] 点击菜单栏图标或从 Finder 重新打开时窗口正常显示
- [ ] 应用列表在后台加载，主线程不卡顿，加载完成前显示占位提示
- [ ] 应用图标在表格滚动到对应行时才加载
- [ ] 输入源列表重复调用不触发 Carbon TIS，仅在点「刷新输入法」时更新
- [ ] 规则文件仅在保存时写磁盘，读取后内存缓存

## Open Questions

- None
