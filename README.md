# 网址收藏 App（本地优先 + WebDAV 云同步/备份）

这个仓库现在是一个可运行的 Flutter 客户端源码，目标对应你的 3 条需求：

1. 本地优先：所有收藏先写本地 SQLite（离线可用）
2. 云备份 + 云同步：通过 WebDAV 推送操作日志与快照
3. 只输网址：自动抓标题，并按设置周期自动刷新标题

## 已实现功能

- 本地数据库
  - `bookmarks`：收藏记录（含软删除）
  - `sync_outbox`：待同步操作队列
  - `sync_state`：同步游标
- 网址收藏
  - 输入 URL 后自动标准化
  - 新增后异步抓取页面标题
- 标题更新
  - 可手动“更新标题”
  - 可按设置周期批量刷新过期标题（默认 7 天）
  - 支持“一键更新全部标题”（并发抓取，适配大量网址）
  - 批量更新时显示实时进度条与完成计数
- 搜索
  - 支持按标题/网址实时搜索（收藏与回收站）
- 去重
  - 支持“去除重复”（按标准化 URL）
  - 支持“去除相似”（忽略常见跟踪参数，并基于 host/path + 相似度判定）
  - 去重结果进入回收站，避免误删
- 批量操作
  - 支持批量删除到回收站
  - 支持批量恢复/批量永久删除
  - 支持批量更新标题
  - 支持批量导出（JSON/CSV）
- 导出
  - 支持导出全部数据（JSON/CSV）
  - 支持用户自行选择导出目录或导出文件路径
- 瘦身清理
  - 清理已推送且过期的同步日志
  - 清理回收站过期数据（默认 30 天）
  - 清理数据库无效数据（空 URL 等脏数据）
  - 执行数据库优化与回收空间（VACUUM/optimize）
- 回收站
  - 删除后进入回收站
  - 支持恢复单条收藏
  - 支持一键清空回收站（永久删除）
- 关于页
  - 展示技术栈与作者信息（作者：奥里奥多）
  - 展示当前版本号
- 更新日志页
  - 应用内可查看版本更新记录（版本 + 日期 + 功能变化）
- 云能力（WebDAV）
  - 操作日志增量同步（push + pull）
  - 全量快照备份上传
- 平台
  - Flutter 跨平台方案，优先支持 Android 和 Windows

## 项目结构

- `lib/main.dart`：应用入口
- `lib/app/local/`：本地数据库与仓库
- `lib/app/ui/`：首页与设置页
- `lib/core/metadata/`：网页标题抓取
- `lib/core/sync/`：同步引擎 + WebDAV Provider
- `lib/core/backup/`：WebDAV 快照备份
- `docs/SYNC_WEBDAV.md`：WebDAV 同步协议说明
- `assets/icons/app_icon.svg`：手绘矢量图标源文件

## 本机运行（首次）

1. 安装 Flutter（建议 stable）
2. 在仓库根目录执行：

```bash
flutter pub get
flutter run -d windows
```

Android 调试：

```bash
flutter run -d android
```

## 打包

Android APK：

```bash
flutter build apk --release
```

输出：`build/app/outputs/flutter-apk/app-release.apk`

Windows EXE：

```bash
flutter build windows --release
```

输出：`build/windows/x64/runner/Release/`

## 版本与发布流程

- 应用内版本号来自 `pubspec.yaml` 的 `version`
- 应用内可在“更多功能 -> 更新日志”或“关于 -> 更新日志”查看变更记录
- GitHub Actions 已配置：
  - `CI`：推送到 `main` 或 PR 时自动执行 `analyze/test`，并构建 Android/Windows
  - `Release`：推送 `v*` 标签时自动构建 APK 与 Windows 压缩包并发布到 GitHub Release

## WebDAV 设置建议

设置页中填写：

- 启用 WebDAV
- Base URL（例如 Nextcloud DAV 根路径）
- 应用内用户 ID（用于云目录隔离）
- WebDAV 用户名 / 密码

同步目录约定：

```text
/BookmarksApp/users/{userId}/devices/{deviceId}/ops/*.json
/BookmarksApp/users/{userId}/snapshots/bookmarks_YYYY-MM-DD.json
```

## 注意事项

- 这是 MVP：冲突策略是 LWW + 删除优先。
- 某些网站标题抓取可能受反爬或 JS 渲染影响，后续可加“服务端抓取器”作为兜底。
- 生产版建议把 WebDAV 密码改为系统安全存储（Android Keystore / Windows Credential Manager）。
