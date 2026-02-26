# Changelog

All notable changes to this project are documented in this file.

## [0.1.0-beta.1] - 2026-02-26

### Added
- Drawer 信息架构定型：主入口（收件箱/资料库/专注）、工具（搜索/标签）、系统（设置/维护）
- 资料库三段切换（待办/笔记/链接）与分页加载（pageSize=50）
- 详情页统一推入式路由：`/todo/:id`、`/note/:id`、`/link/:id`
- 待办详情最小编辑（标题/优先级/标签/提醒）与 done/open 状态切换
- 笔记详情版本管理、原文入口、可取消重新整理
- 链接详情编辑、单条刷新标题、批量刷新进度与取消
- 本地 FTS5 索引维护与恢复重建
- 搜索页本地/AI 深度搜索，支持失败降级
- 专注计时（countdown + countup）与 `focus_state` 持久化恢复
- WebDAV 同步、云备份恢复、外发通知队列（飞书/SMTP）
- 主题系统与维护工具页面

### Changed
- UI 文案将“收藏”统一为“链接”（UI 可见层）
- 输入框创建入口收敛到收件箱，资料库改为“+ 新建”跳转
- 状态条支持 AI/同步/备份/通知状态展示与错误复制

### Fixed
- deep 搜索失败时自动降级本地，避免无结果卡死
- 详情页保存后列表刷新一致性
- 标签结果页与搜索页详情入口统一

### Tests
- 新增/完善：DB schema、FTS、repository 分页、详情保存取消、搜索降级、focus 状态恢复、同步/通知队列相关测试

---

## 历史里程碑摘要

### M1
- SQLite schema + FTS5 + Drawer 三入口 + 资料库分页 + Debug seed

### M2
- AI Provider 配置/models/连通性测试 + Router JSON schema + ActionExecutor 落库

### M3
- Todo/Note/Link 业务闭环 + FTS upsert + 本地/AI 搜索 + 标题刷新

### M4
- 专注计时状态机 + 持久化恢复 + Windows 通知稳定性

### M5
- WebDAV 同步 + 云备份恢复 + 飞书/SMTP 外发通知队列

### M6
- 主题系统 + 维护工具 + 中文体验统一 + 性能回归

### UI v2.1
- 侧边栏 IA、输入路径收敛、标签页/详情页体验统一
