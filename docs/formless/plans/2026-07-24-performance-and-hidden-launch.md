# AutoInputSwitcher 综合优化 Implementation Plan

**Status:** Approved

**Source Spec:** `docs/formless/specs/2026-07-24-performance-and-hidden-launch.md`

## Goal

AutoInputSwitcher 启动时默认隐藏窗口、增加菜单栏图标作为交互入口、应用列表异步加载、图标懒加载、输入源列表缓存，全面提升启动体验和性能。

## Background

App 当前启动流程：`main.swift → NSApplicationMain → AppDelegate.applicationDidFinishLaunching` 中 `setActivationPolicy(.accessory)` 后立即创建 `AppRuntime`。`AppRuntime.init()` 同步执行三项重量级操作：

1. `InstalledApplicationScanner.scan()` — 遍历 `/Applications`、`/System/Applications` 等目录，对每个 `.app` 包调用 `Bundle(url:)` 解析 Info.plist 并加载 `NSWorkspace.icon(forFile:)`。扫描数百个应用耗时 1-3 秒。
2. `SystemInputSourceManager.availableInputSources()` — 调用 Carbon TIS API 创建输入源列表。
3. `JSONRuleStore.load()` — 从 `~/Library/Application Support/AutoInputSwitcher/rules.json` 同步读取。

之后 `showWindow()` 立即弹出窗口。

App 无菜单栏图标、无 Dock 图标（`LSUIElement = true`），窗口关闭后用户无法唤回，只能重新运行可执行文件。

## Architecture

- **菜单栏 (NSStatusItem)** 作为新的主交互入口，左键切换窗口显隐，右键菜单提供「显示窗口」「关于」「退出」
- **启动流程**修改为：注册菜单栏 → 创建 AppRuntime（异步启动扫描）→ 首次启动显示窗口，否则隐藏
- **InstalledApplication 数据模型**：去掉 `icon` 属性，改为在 View 层按需加载并缓存
- **SystemInputSourceManager** 内部缓存输入源列表，`invalidateCache()` 控制刷新
- `JSONRuleStore` 已经由 `AppRuntime.ruleSet` 提供内存缓存，无需改动

## Constraints

- 不改变 `LSUIElement = true`（无 Dock 图标）
- 不引入 Spotlight/NSMetadataQuery
- `rules.json` 格式不变（向后兼容）
- 自动切换逻辑、`AutoInputSwitcherCore` 库不变

## Context Map

- `Sources/AutoInputSwitcher/AppDelegate.swift` — 应用生命周期、窗口管理。改动核心：菜单栏 + 启动行为
- `Sources/AutoInputSwitcher/AppRuntime.swift` — 状态管理、ObservableObject。改动核心：异步扫描
- `Sources/AutoInputSwitcher/MainWindowView.swift` — SwiftUI 主界面。改动核心：加载态 + 懒加载图标 + 菜单栏开关
- `Sources/AutoInputSwitcher/SystemInputSourceManager.swift` — Carbon TIS 封装。改动核心：缓存
- `Sources/AutoInputSwitcher/InstalledApplication.swift` — 数据模型。改动核心：去掉 `icon` 属性
- `Sources/AutoInputSwitcher/InstalledApplicationScanner.swift` — 扫描逻辑。无需改动（Task.detached 中调用即可）
- `Sources/AutoInputSwitcher/main.swift` — 入口点。无需改动

## Tasks

### Task 1: SystemInputSourceManager 缓存 + InstalledApplication 数据模型精简

**Outcome:**

输入源列表默认缓存，仅在用户点击「刷新输入法」时重新构建。`InstalledApplication` 不再在构造时加载图标。

**Context:**

`SystemInputSourceManager` 的 `availableInputSources()` 目前每次调用都走 Carbon TIS。这在 `AppRuntime.reloadInputSources()` 中也被频繁触发。加一层内存缓存后，95% 的调用命中缓存。

`InstalledApplication` 的 `icon: NSImage` 在 `InstalledApplicationScanner.application(at:)` 中被设置，`NSWorkspace.icon(forFile:)` 涉及磁盘 I/O。将图标加载移到 View 层（Task 3 实现），这里先去掉该属性。

**Files:**

- Modify: `Sources/AutoInputSwitcher/SystemInputSourceManager.swift`
- Modify: `Sources/AutoInputSwitcher/InstalledApplication.swift`

**Decisions and Boundaries:**

1. **SystemInputSourceManager 缓存**：
   - 新增 `private var cachedInputSources: [InputSource]?`（初始 nil）
   - `availableInputSources()` 在有缓存时直接返回缓存值
   - 无缓存时走原逻辑并将结果赋值给 `cachedInputSources`
   - 新增 `func invalidateCache()` 将 `cachedInputSources` 置 nil
   - `AppRuntime.reloadInputSources()` 调用 `inputSourceManager.invalidateCache()` 后再调用 `availableInputSources()`
   - `availableInputSources()` 现在是 `@discardableResult`（可选），但为了缓存一致性，调用方应确保最终至少调用一次

2. **InstalledApplication 精简**：
   - 删除 `let icon: NSImage` 行
   - `Identifiable` 和 `Equatable` 自动合成保持不变（icon 之前参与了 Equatable 比较，移除后编译器自动忽略该字段）
   - 在 `InstalledApplicationScanner.application(at:)` 中删除 `icon: NSWorkspace.shared.icon(forFile: url.path)` 参数
   - `InstalledApplication` 的初始化签名变为 `init(name:bundleIdentifier:url:)`

**Interfaces:**

- Consumes: 无变化
- Produces: `SystemInputSourceManager` 新增 `invalidateCache()` 公开方法；`InstalledApplication` 去掉 `icon` 字段

**Verification:**

- `swift build` 通过（编译器保证接口一致性）
- `swift run AutoInputSwitcherCoreChecks` 通过（核心逻辑不受影响）
- 手动验证：启动 app → 窗口出现且有应用列表 → 点「刷新输入法」后输入源列表正确刷新

**Escalate if:**

- 某个 Carbon TIS 缓存后的行为与之前不一致（缓存命中时返回同一数组引用，而之前每次都新建——若调用方修改了数组内容会有问题。检查现有调用方均为只读使用，无风险）

---

### Task 2: AppDelegate 菜单栏图标 + 启动行为

**Outcome:**

- 添加 `NSStatusItem` 菜单栏图标（键盘 SF Symbol）
- 左键点击切换窗口显示/隐藏
- 右键菜单：「显示窗口」「关于 AutoInputSwitcher」「退出」
- 启动时不显示窗口，除非是首次启动（规则文件为空）
- 从 Finder/Launchpad 再次打开 app 时显示窗口（`applicationShouldHandleReopen`）
- 菜单栏图标支持显隐，设置写入 `UserDefaults` key `showMenuBarIcon`

**Context:**

AppDelegate 是启动入口。当前的 `applicationDidFinishLaunching` 中调用 `showWindow()` 导致窗口始终出现。改为：只创建菜单栏和 `AppRuntime`，根据首次启动标记决定是否弹窗。

`NSStatusItem` 使用 `NSStatusItem.systemStatusBar` 创建，button image 用 SF Symbol `"keyboard"` 或类似图标。

菜单栏显隐设置：用户通过窗口中的开关（Task 3）更改，AppDelegate 通过 `NotificationCenter` 或直接调用方法响应。

**Files:**

- Modify: `Sources/AutoInputSwitcher/AppDelegate.swift`

**Decisions and Boundaries:**

1. **NSStatusItem 创建**（在 `applicationDidFinishLaunching` 中）：
   ```swift
   private var statusItem: NSStatusItem?
   
   private func setupMenuBar() {
       let item = NSStatusItem.systemStatusBar.statusItem(
           withLength: NSStatusItem.variableLength
       )
       item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "AutoInputSwitcher")
       item.button?.action = #selector(toggleWindow)
       item.button?.target = self
       
       let menu = NSMenu()
       menu.addItem(NSMenuItem(title: "显示窗口", action: #selector(showWindowFromMenu), keyEquivalent: ""))
       menu.addItem(NSMenuItem.separator())
       menu.addItem(NSMenuItem(title: "关于 AutoInputSwitcher", action: #selector(showAboutPanel), keyEquivalent: ""))
       menu.addItem(NSMenuItem(title: "退出", action: #selector(terminateApp), keyEquivalent: "q"))
       item.menu = menu
       
       statusItem = item
       statusItem.isVisible = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
   }
   ```

2. **启动行为**：
   - `applicationDidFinishLaunching` 中移除 `showWindow()` 的自动调用
   - 改为先调用 `setupMenuBar()`，然后：
     ```swift
     let isFirstLaunch = !FileManager.default.fileExists(
         atPath: JSONRuleStore.applicationSupportStore().url.path
     )
     if isFirstLaunch {
         showWindow()
     }
     ```
   - `applicationShouldHandleReopen` 中调用 `showWindow()`（保持不变）

3. **菜单栏显隐**：
   - 新增 `func updateMenuBarIconVisibility(_ show: Bool)` 设置 `statusItem?.isVisible = show` 并写 `UserDefaults`
   - 从 `NotificationCenter` 订阅或由 AppRuntime 桥接。简单方案：AppRuntime 持有一个闭包或弱引用调用 AppDelegate 的方法。更简单：AppDelegate 直接观察 UserDefaults 的 `showMenuBarIcon` key 变化（KVO 或 `NSUserDefaultsDidChangeNotification`）
   
   推荐方案：AppDelegate 监听 `UserDefaults.didChangeNotification`，检查 `showMenuBarIcon` key 是否有变化后更新。避免耦合。

4. **方法签名**：
   - `@objc private func toggleWindow()` — 若 window 可见且有 isVisible 属性 → `window?.close()`，否则 `showWindow()`
   - `@objc private func showWindowFromMenu()` — 直接 `showWindow()`
   - `@objc private func showAboutPanel()` — `NSApp.orderFrontStandardAboutPanel(nil)`
   - `@objc private func terminateApp()` — `NSApp.terminate(nil)`

5. **UserDefaults key**：常量 `"showMenuBarIcon"`，默认值 `true`（在 `UserDefaults.register` 或在 setup 中设置初始值）

**Interfaces:**

- Consumes: `AppRuntime` 的构造方式不变；`MainWindowView` 无变化（除了新增 toggle 回调，见 Task 3）
- Produces: `AppDelegate` 暴露 `updateMenuBarIconVisibility(_:)`（供 Task 3 调用）；UserDefaults key `showMenuBarIcon`

**Verification:**

- `swift build` 通过
- 手动验证场景：
  1. 删除 `~/Library/Application Support/AutoInputSwitcher/rules.json` 首次启动 → 窗口弹出
  2. 再次启动 → 窗口隐藏，菜单栏有图标
  3. 左键点击图标 → 窗口显示/切换
  4. 右键菜单 →「关于」面板弹出、「退出」正常退出
  5. 从 Finder 再次打开 app → 窗口显示
  6. 设置菜单栏隐藏 → statusItem 消失；重新从 Finder 打开 → 窗口中显示开关，打开后图标恢复

**Escalate if:**

- SF Symbol `"keyboard"` 在 macOS 14 上不可用。回退方案：用 `"menubar.dock"` 或 `"switch.2"`，或自定义 NSImage 绘制

---

### Task 3: AppRuntime 异步扫描 + MainWindowView 加载态与懒加载图标 + 菜单栏开关

**Outcome:**

- `AppRuntime` 启动时异步扫描应用列表，不阻塞主线程
- `MainWindowView` 在扫描完成前显示加载占位
- 应用图标在表格行渲染时按需加载并缓存在 View 层
- 菜单栏图标显隐开关添加到窗口 topBar
- 窗口关闭 app 不退出（`applicationShouldTerminateAfterLastWindowClosed` 保持 `false`）

**Context:**

`AppRuntime.init()` 目前同步调用 `applicationScanner.scan()`。改为：将 `installedApplications` 初始化为空数组，然后在 `Task.detached` 中异步执行扫描，完成后 `await MainActor.run` 更新。

`MainWindowView` 中表格使用 `Image(nsImage:)` 展示图标，需要改为按需 `NSWorkspace.icon(forFile:)` 调用并在 view 层缓存。

菜单栏开关需要桥接回 `AppDelegate`。方案：`AppRuntime` 持有 `setMenuBarIconVisibility: (Bool) -> Void` 闭包，`AppDelegate` 在创建 `AppRuntime` 后注入该闭包。

**Files:**

- Modify: `Sources/AutoInputSwitcher/AppRuntime.swift`
- Modify: `Sources/AutoInputSwitcher/MainWindowView.swift`

**Decisions and Boundaries:**

1. **AppRuntime 异步扫描**：
   - 在 `init()` 中，`applicationScanner.scan()` 调用置为 `self.installedApplications = applicationScanner.scan()` → 改为 `self.installedApplications = []`，然后调用 `startAsyncApplicationScan()`
   - `startAsyncApplicationScan()` 方法：
     ```swift
     private func startAsyncApplicationScan() {
         Task {
             let applications = await Task.detached(priority: .userInitiated) {
                 self.applicationScanner.scan()
             }.value
             await MainActor.run {
                 self.installedApplications = applications
             }
         }
     }
     ```
   - `applicationScanner` 是 `let` 属性，在闭包中直接捕获。由于 `self` 在 `init` 中完全初始化后才调用此方法，不会导致 `init` 中逃逸闭包问题
   - `reloadApplications()` 方法改为同样走异步路径：
     ```swift
     func reloadApplications() {
         startAsyncApplicationScan()
     }
     ```

2. **MainWindowView 加载占位**：
   - 在 `applicationsContent` 中，当 `runtime.installedApplications.isEmpty` 且 `runtime.searchText.isEmpty` 且扫描可能还在进行时，显示 `ProgressView("正在扫描应用...")` 而不是 `ContentUnavailableView`
   - 区分「正在加载」和「确实没有结果」：加一个 `@Published var isScanning: Bool` 到 `AppRuntime`，开始扫描时设 `true`，完成后设 `false`
   - `applicationsContent`:
     ```
     if runtime.isScanning {
         ProgressView("正在扫描已安装应用...")
     } else if runtime.filteredInstalledApplications.isEmpty {
         ContentUnavailableView(...)
     } else {
         applicationsList
     }
     ```

3. **图标懒加载**：
   - `MainWindowView` 中新增 `@State private var loadedIcons: [String: NSImage] = [:]`
   - 替换表格 row 中的 `Image(nsImage: application.icon)` 为：
     ```swift
     if let icon = loadedIcons[application.bundleIdentifier] {
         Image(nsImage: icon)
     } else {
         Image(systemName: "app.fill")
             .foregroundStyle(.tertiary)
             .onAppear { loadIcon(for: application) }
     }
     ```
   - `loadIcon(for:)` 方法（在主线程调用，NSWorkspace.icon 是线程安全的，但 UI 更新在主线程）：
     ```swift
     private func loadIcon(for application: InstalledApplication) {
         guard loadedIcons[application.bundleIdentifier] == nil else { return }
         let icon = NSWorkspace.shared.icon(forFile: application.url.path)
         icon.size = NSSize(width: 24, height: 24)
         loadedIcons[application.bundleIdentifier] = icon
     }
     ```
   - 注意：`loadedIcons` 是 `@State`，SwiftUI 会自动触发视图更新
   - 当 `runtime.reloadApplications()` 刷新应用列表时，旧的图标缓存可能失效（如果应用被移除/重装）。但这是边缘情况，简单处理：reload 时清空 `loadedIcons`？不清空也没关系，旧图标仍然有效（bundleIdentifier 不变）。保持不变即可。

4. **菜单栏开关**：
   - 在 `MainWindowView.topBar` 的 `Toggle("开机自启")` 旁边增加：
     ```swift
     Toggle("菜单栏", isOn: Binding(
         get: { UserDefaults.standard.bool(forKey: "showMenuBarIcon") },
         set: { 
             UserDefaults.standard.set($0, forKey: "showMenuBarIcon")
             runtime.updateMenuBarIconVisibility?($0)
         }
     ))
     .toggleStyle(.switch)
     ```
   - `AppRuntime` 新增 `var updateMenuBarIconVisibility: ((Bool) -> Void)?`
   - `AppDelegate` 在创建 `AppRuntime` 后注入：
     ```swift
     runtime.updateMenuBarIconVisibility = { [weak self] show in
         self?.updateMenuBarIconVisibility(show)
     }
     ```
   - 给这个 Toggle 加 `accessibilityLabel("显示菜单栏图标")`

5. **AppRuntime 中 UserDefaults 初始值**：
   在 `AppRuntime.init()` 或 `AppDelegate` 中用以下方式确保 `showMenuBarIcon` 默认 true：
   ```swift
   UserDefaults.standard.register(defaults: ["showMenuBarIcon": true])
   ```
   在 `AppDelegate.applicationDidFinishLaunching` 中设置此默认值。

6. **首次启动判断**：
   `AppDelegate` 中判断首次启动的逻辑（Task 2 已覆盖），AppRuntime 无需额外修改。但 `AppRuntime.init()` 仍需能正常构造，`ruleSet` 为空时就是空数组，不影响。

**Interfaces:**

- `AppRuntime` 新增 `@Published var isScanning: Bool`，新增 `var updateMenuBarIconVisibility: ((Bool) -> Void)?`（可选闭包）
- AppDelegate 注入闭包到 AppRuntime
- MainWindowView 使用 `loadedIcons: [String: NSImage]` 状态管理图标缓存

**Verification:**

- `swift build` 通过
- 手动验证：
  1. 启动 → 窗口（首次）或隐藏（后续），菜单栏图标存在
  2. 窗口出现后，应用列表区域先显示「正在扫描已安装应用...」加载动画，0.5-2 秒后列表出现
  3. 表格滚动时新行的图标正常出现
  4. 切换「菜单栏」开关 → 菜单栏图标即时显隐
  5. 多次切换不崩溃

**Escalate if:**

- async/await Task 在 init 中捕获 `self` 导致编译错误。若编译器要求显式 `self` 或生命周期约束导致问题，考虑用 `applicationScanner` 的局部副本而非属性引用。但 `InstalledApplicationScanner` 是值类型且方法不涉及 `self` 变异，应无问题。
- SwiftUI 中 `loadedIcons` 更新不触发重绘：验证 `onAppear` 中设置后 table row 是否响应。若 `Table` 不配合 `@State` 更新，考虑改用 `@ObservedObject` 或封装 icon 字典到 ObservableObject 中。只要 SwiftUI 检测到 `@State` 变化，`Table` 应能重新渲染对应行。

---

### Verification汇总

自动化验证（运行全部核心检查）：
```bash
swift run AutoInputSwitcherCoreChecks
```

编译验证：
```bash
swift build
```

手动集成测试清单（在 `README.md` 中无需记录，供开发者自测）：
1. 首次启动 → 窗口显示，菜单栏图标可见
2. 关闭窗口 → 菜单栏图标不消失
3. 重新启动 app → 窗口默认不弹出
4. 左键菜单栏图标 → 窗口显示/隐藏交替
5. 右键菜单 →「关于」和「退出」正常工作
6. 窗口表 topBar → 开关菜单栏图标显隐
7. 隐藏菜单栏图标 → 关闭窗口 → 从 Finder 打开 app → 窗口出现 → 打开菜单栏开关 → 图标恢复
8. 窗口加载时显示「正在扫描...」进度条，非空结果正常显示
9. 应用列表行图标按需加载，不卡顿
