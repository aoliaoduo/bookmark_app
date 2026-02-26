# AIOS 0.1.0-beta.1 Release Notes

发布日期：2026-02-26

## Beta 范围
- 本地优先的收件箱、资料库（待办/笔记/链接）、专注计时、搜索、设置。
- AI Provider 配置、Router 预览确认落库、失败草稿回退。
- WebDAV 同步、云备份/恢复、飞书/SMTP 通知队列。
- 主题系统、维护工具、中文化提示、Windows 快捷键与轻量动效。

## 本次发布准备新增
- Windows Portable 打包脚本：`scripts/package_portable.ps1`
- Windows MSIX 打包脚本：`scripts/build_msix.ps1`
- `pubspec.yaml` 增加 `msix_config`（Beta 配置）
- 设置页新增“关于与诊断”导出（默认脱敏，可选敏感导出）
- 发布文档与回归清单补齐：
  - `docs/RELEASE.md`
  - `docs/REGRESSION_CHECKLIST_BETA.md`

## 已知限制（Beta）
- MSIX 当前采用 Beta 自签证书安装流程。
- WACK 检测需在安装了对应工具链的机器执行。
- 外部服务（AI/WebDAV/飞书/SMTP）受网络与账号配置影响较大，失败会给出可复制错误。

## 升级与反馈
- 安装/升级请参考：`docs/RELEASE.md`
- 问题反馈建议附带诊断包：设置 -> 关于与诊断 -> 导出诊断包
