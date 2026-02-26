# AIOS Windows Beta 发布说明

本文档用于指导 Windows Beta 的构建、打包、安装与验证。

## 版本规范
- 应用版本（pubspec）：`0.1.0-beta.1+1`
- 对外展示版本：`0.1.0-beta.1`

## 发布产物
- Portable：`AIOS-<version>-portable.zip`
- MSIX：`AIOS-<version>.msix`

## 构建前检查
```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

## Portable（将在后续提交补脚本）
```powershell
flutter build windows --release
```

输出目录（示例）：
- `build/windows/x64/runner/Release/`

## MSIX（将在后续提交补配置与脚本）
- 计划使用本机自签证书（beta）
- 计划 identity：
  - `identity_name = AIOS.Beta`
  - `publisher = CN=AIOS Beta Dev`

## 安装验证（用户侧）
### Portable
1. 解压 zip
2. 双击 `AIOS.exe`

### MSIX
1. 导入并信任 beta 证书
2. 双击 `.msix`
3. 安装后从开始菜单启动 AIOS

## 回归检查
- 详见：`docs/REGRESSION_CHECKLIST_BETA.md`（后续提交新增）
