# AIOS Windows Beta 发布指南

本文档用于 Windows Beta 的构建、打包、安装与验证。

## 版本规范
- 应用版本（`pubspec.yaml`）：`0.1.0-beta.1+1`
- 对外展示版本：`0.1.0-beta.1`

## 发布产物
- Portable：`AIOS-<version>-<arch>-portable.zip`
- MSIX：`AIOS-<version>.msix`

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
./scripts/build_windows_release.ps1
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
./scripts/package_portable.ps1 -Arch x64
```

仅打包（跳过构建）：
```powershell
./scripts/package_portable.ps1 -Arch x64 -SkipBuild
```

输出目录：
- `dist/AIOS-<version>-<arch>-portable/`
- `dist/AIOS-<version>-<arch>-portable.zip`

## MSIX 打包（Beta）
1. 安装依赖并检查 `pubspec.yaml` 中的 `msix_config`。
2. 执行：
```powershell
./scripts/build_msix.ps1
```
3. 产物位于 `build/windows/**/**/*.msix`（脚本会打印完整路径）。

等价命令：
```powershell
dart run msix:create
```

### 自签证书（Beta）
Beta 默认允许开发者本机自签安装。示例流程：
1. 生成证书（CurrentUser）：
```powershell
New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=AIOS Beta Dev" -CertStoreLocation Cert:\CurrentUser\My
```
2. 导出 `.pfx`（用于签名）与 `.cer`（用于安装信任）。
3. 在目标机器导入 `.cer` 到“受信任的根证书颁发机构”后再安装 `.msix`。

## Windows App Certification Kit（WACK）
若本机已安装 WACK，发布前建议执行一次验证并保存报告：
1. 打开 Windows App Certification Kit。
2. 选择生成的 `AIOS-<version>.msix`。
3. 保存测试报告到 `docs/wack/` 或发布归档目录。

> 若当前环境未安装 WACK，可先记录“待验证”，不阻塞 Beta 内测分发。

## 用户侧运行
### Portable
1. 解压 `AIOS-<version>-<arch>-portable.zip`
2. 双击 `code.exe`

### MSIX
1. 先导入并信任 Beta 证书
2. 双击 `.msix`
3. 从开始菜单启动 AIOS

## 回归清单
- 见 `docs/REGRESSION_CHECKLIST_BETA.md`
