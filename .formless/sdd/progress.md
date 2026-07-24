# Progress: AutoInputSwitcher 综合优化

**Plan:** `docs/formless/plans/2026-07-24-performance-and-hidden-launch.md`
**Branch:** `feature/performance-and-hidden-launch`
**Starting commit:** `6ca0571`

## Tasks

- [x] Task 1: SystemInputSourceManager 缓存 + InstalledApplication 数据模型精简
  - Commits: `3a1581b`
- [x] Task 2: AppDelegate 菜单栏图标 + 启动行为
  - Commits: `d7f287b`
- [x] Task 3: AppRuntime 异步扫描 + MainWindowView 加载态与懒加载图标 + 菜单栏开关
  - Commits: `c794fb9`, `ec3df6e` (fix: input source cache invalidation on reload)
