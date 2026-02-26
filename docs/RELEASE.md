# AIOS Windows Beta 发布指南

本文档用于 Windows Beta 的构建、打包、安装与验证。

## 版本规范
- 应用版本（`pubspec.yaml`）：`0.1.0-beta.1+1`
- 对外展示版本：`0.1.0-beta.1`

## 发布产物
- Portable：`AIOS-<version>-<arch>-portable.zip`
- MSIX：`AIOS-<version>.msix`（M5 Commit 4 完成配置）

## 构建前检查
```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

## Windows Release 构建
```powershell
pwsh ./scripts/build_windows_release.ps1
```

默认等价于：
```powershell
flutter build windows --release
```

构建输出目录（按架构）：
- `build/windows/x64/runner/Release/`
- `build/windows/arm64/runner/Release/`

## Portable ZIP 打包
自动构建并打包：
```powershell
pwsh ./scripts/package_portable.ps1 -Arch x64
```

仅打包（跳过构建）：
```powershell
pwsh ./scripts/package_portable.ps1 -Arch x64 -SkipBuild
```

输出目录：
- `dist/AIOS-<version>-<arch>-portable/`
- `dist/AIOS-<version>-<arch>-portable.zip`

## 用户侧运行（Portable）
1. 解压 `AIOS-<version>-<arch>-portable.zip`
2. 双击 `code.exe`（后续可改为品牌化 exe 名称）

## MSIX（Beta）
- 将在后续提交完成 `msix_config` 与打包命令固化
- 计划采用自签证书用于本机/测试环境安装

## 回归清单
- 见 `docs/REGRESSION_CHECKLIST_BETA.md`（后续提交补充）
