# AI-First Local Productivity App (M1)

基于 `PRD_v1.1_AI_friendly.md` 的 M1 本地可运行版本（Windows 优先）。

## M1 已实现
- 本地 SQLite 真源（`sqflite_common_ffi`）
  - 已建表：`kv / inbox_drafts / tags / entity_tags / todos / notes / note_versions / bookmarks / focus_state / search_fts`
  - 启动自检 FTS5（写入临时记录 -> `MATCH` 查询 -> 日志 `FTS5 OK` -> 清理）
- 导航与页面结构
  - Drawer 三入口：`收件箱 / 资料库 / 专注`
  - 资料库顶部切换：`待办 / 笔记 / 链接`（无额外一级 Tab）
- 资料库真实分页列表
  - `pageSize=50`，触底加载下一页
  - Todo 排序：`priority DESC, created_at DESC`
  - Note 排序：`updated_at DESC`
  - 链接排序：`updated_at DESC`
- Debug（仅 `kDebugMode` 显示）
  - 一键生成 1000 测试数据（700/200/100）
  - 一键清空测试数据（不清理 `kv`，保留 `device_id/lamport`）
- 轻量动画
  - 资料库切换淡入
  - 列表新增项 Fade + Size
  - 分页底部 loading row（`加载中...`）
- 测试
  - DB schema/FTS
  - Repository 分页
  - 触底分页 widget test
  - App shell Drawer 基础测试

## M1 未实现（按 PRD 分期）
- AI Router 与统一输入执行链路
- AI Provider（`base_url/api_key/models`）与批测
- WebDAV 增量同步 / 云备份与恢复
- 本地稳通知完整实现（含 Android AlarmManager）
- 飞书/SMTP 外发通知
- 搜索 deep 模式（多轮计划+重排）

## 运行方式（Windows）
```powershell
cd C:\Users\aolia\Desktop\code
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

## M1 手测路径
1. 启动应用，确认日志出现数据库初始化与 `FTS5 OK`。
2. 打开 Drawer，确认只有 3 个一级入口：收件箱 / 资料库 / 专注。
3. 进入资料库，顶部切换 `待办/笔记/链接`，观察中文空态文案。
4. 打开资料库右上角调试菜单（Debug 下可见）：
   - 点击“生成测试数据(1000)”
   - 滚动列表到底部，确认触底分页与“加载中...”行显示/消失正常。
5. 点击“清空测试数据”，确认列表回到空态。

## 性能验收建议（M1）
- 在 Windows Debug 模式下先执行“生成测试数据(1000)”。
- 在 Todo 列表连续快速滚动并反复触底分页。
- 观察是否有明显卡顿、掉帧或加载状态异常。

## 已知限制（M1）
- `hasMore = items.length == pageSize` 为简化策略：若最后一页恰好等于 `pageSize`，会多触发一次空加载；UI 可正确收敛。
