# AIOS (Windows Beta)

AIOS 是一个本地优先的个人效率应用，当前处于 Windows Beta 阶段。

## 当前版本
- `0.1.0-beta.1`

## 功能范围（Beta）
- 收件箱：自然语言输入，AI 路由预览与确认落库
- 资料库：待办/笔记/链接三段视图、详情编辑、标签结果页
- 搜索：本地搜索 + AI 深度搜索（失败自动降级本地）
- 专注：countdown/countup、状态持久化、Windows 通知
- 同步/备份/通知渠道：均可在设置中配置与手动验证

## 安装（Windows）
### Portable ZIP
1. 下载 `AIOS-<version>-portable.zip`
2. 解压到任意目录（建议非系统目录）
3. 双击 `AIOS.exe` 启动

### MSIX（Beta）
1. 下载 `AIOS-<version>.msix`
2. 按 `docs/RELEASE.md` 先导入测试证书
3. 双击 `.msix` 安装并启动

## 升级
### Portable
1. 退出旧版本
2. 解压新版本到新目录（或覆盖旧目录）
3. 启动新版本

### MSIX
1. 直接安装更高版本 `.msix`
2. 系统自动执行应用升级

## 卸载
### Portable
- 删除解压目录即可

### MSIX
- Windows 设置 -> 应用 -> 已安装应用 -> AIOS -> 卸载

## 开发运行
```powershell
cd C:\Users\aolia\Desktop\code
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

## 已知问题（Beta）
- 切换不同网络环境时，AI Provider/同步连接可能需要手动重试
- MSIX Beta 使用自签证书，首次安装需额外信任证书
- 某些第三方 Provider 返回非标准 JSON 时，深度搜索会自动降级到本地搜索

## 反馈方式
1. 打开应用：`设置 -> 关于与诊断`
2. 点击“一键导出诊断包”（默认脱敏）
3. 附上诊断包与复现步骤反馈

## 发布文档
- [RELEASE.md](docs/RELEASE.md)
- [CHANGELOG.md](CHANGELOG.md)
- [RELEASE_NOTES_BETA.md](docs/RELEASE_NOTES_BETA.md)
- [REGRESSION_CHECKLIST_BETA.md](docs/REGRESSION_CHECKLIST_BETA.md)
