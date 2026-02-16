import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key});

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  String _versionLabel = '-';

  static const List<_ChangelogEntry> _entries = <_ChangelogEntry>[
    _ChangelogEntry(
      version: 'v0.4.9',
      date: '2026-02-17',
      notes: <String>[
        '修复手机端“瘦身清理”执行 WAL checkpoint 报错导致流程中断',
        '数据库维护改为按能力执行：PRAGMA 统一走 rawQuery，非 WAL 场景自动跳过 checkpoint',
        '即使个别维护指令失败也会降级继续，避免用户一键瘦身直接失败',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.8',
      date: '2026-02-17',
      notes: <String>[
        '回收站改为本地状态：删除/恢复不再参与云同步',
        '同步拉取 JSON 改为按字节+编码解码，修复手机端中文字段（标题/备注等）乱码',
        '网页标题抓取新增 charset 识别（含 GBK/GB2312），提升中文站点标题识别准确性',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.7',
      date: '2026-02-17',
      notes: <String>[
        '修复 WebDAV Base URL 含 /dav 时拉取路径重复拼接导致“同步无报错但拉不到数据”',
        '同步拉取新增路径规范化，自动去除服务端 href 的 basePath 前缀',
        '补充回归测试，覆盖 /dav 前缀场景并防止出现 /dav/dav 重复路径',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.6',
      date: '2026-02-17',
      notes: <String>[
        '输入框提示简化为“输入网址”，移除示例 URL 文案',
        '新增“清空全部数据”功能，可一键重置收藏与同步配置',
        '每条收藏支持一键复制链接地址',
        '合并部分按钮到菜单，减少顶部与条目操作区的拥挤，风格更统一',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.5',
      date: '2026-02-17',
      notes: <String>[
        '修复 Android release 包缺少网络权限导致的云同步/备份域名解析失败',
        '主清单补充 INTERNET 权限，手机端同步与备份可正常访问 WebDAV',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.4',
      date: '2026-02-16',
      notes: <String>[
        '修复手机端顶部操作栏按钮过多导致右侧被遮挡的问题',
        '窄屏自动切换为“核心按钮 + 更多菜单”，所有功能都可点到',
        '批量模式顶部操作同样支持窄屏菜单收纳',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.3',
      date: '2026-02-16',
      notes: <String>[
        '修复 Windows 中文文字深浅不一致问题，统一中文字体渲染',
        '统一“外观模式”与主按钮文字样式，避免局部样式混用造成观感差异',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.2',
      date: '2026-02-16',
      notes: <String>[
        '修复云同步在 WebDAV 返回 409 时直接中断的问题（改为按空目录处理）',
        '云同步拉取兼容历史 ussers 目录路径，避免旧目录结构导致报错',
        'WebDAV Base URL 自动剥离 /BookmarksApp 子路径，减少配置误填影响',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.1',
      date: '2026-02-16',
      notes: <String>[
        '修复外观模式选项样式不统一，改为统一单选样式展示',
        '修复 Windows 目录切换导致的数据/配置丢失，新增旧目录自动迁移',
        '修复 Windows 标题栏中文名显示乱码',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.0',
      date: '2026-02-16',
      notes: <String>[
        '应用品牌升级为“粮仓”，首页标题与桌面窗口名同步调整',
        '新增深色模式（跟随系统/浅色/深色）并支持在设置页切换',
        '链接标题抓取失败时，列表中会显示错误提示并提供处理入口',
        '优化圆角阴影样式，卡片阴影与圆角边界保持一致',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.3.5',
      date: '2026-02-17',
      notes: <String>[
        '首页标题从“网址收藏”调整为“链接收藏”',
        '新增输入区按钮高度对齐，收藏按钮与输入框视觉统一',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.3.4',
      date: '2026-02-17',
      notes: <String>[
        '修复搜索栏双层边框样式问题，统一为单层输入框视觉',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.3.3',
      date: '2026-02-17',
      notes: <String>[
        'CI 调整为仅在 PR 场景自动取消进行中的旧任务',
        'main 分支推送任务不再被新推送自动中断，减少误判失败',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.3.2',
      date: '2026-02-17',
      notes: <String>[
        '修复搜索框展开时的位置冲突问题，改为固定位置展示',
        '搜索框视觉样式进一步弱化，避免抢占主流程注意力',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.3.1',
      date: '2026-02-17',
      notes: <String>[
        '搜索区域改为默认收起，视觉权重下调，避免干扰主操作',
        '回收站不再单独占用 Tab，改为主页内模式切换',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.3.0',
      date: '2026-02-17',
      notes: <String>[
        '同步游标改为基于 WebDAV 服务端时间，修复多设备时钟差导致的漏同步风险',
        'WebDAV 路径段统一做 URL 编码，提升特殊字符场景稳定性',
        'WebDAV 密码迁移到安全存储（含旧版明文配置自动迁移）',
        '快照备份文件名升级为时间戳格式，避免同日多次备份互相覆盖',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.2.2',
      date: '2026-02-17',
      notes: <String>[
        'Windows 端记住上次窗口尺寸，重启后自动恢复',
        '应用版本格式统一为纯语义版本（移除 +build 展示）',
        '统一主页/设置/关于/更新日志的视觉风格',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.2.1',
      date: '2026-02-16',
      notes: <String>[
        '修复导出时取消需要点两次的问题（现在点一次取消即可）',
        '优化导出路径选择交互一致性',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.2.0',
      date: '2026-02-16',
      notes: <String>[
        '新增回收站、清空回收站、批量操作、实时进度条',
        '新增去重（重复/相似）与一键标题更新',
        '新增导出、搜索、瘦身（仅清理无用数据）',
        '新增关于页与应用内更新日志页',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.1.0',
      date: '2026-02-16',
      notes: <String>[
        '首版上线：本地优先收藏、WebDAV 云备份/同步',
        '支持自动抓取网页标题与按周期更新',
        '支持 Android / Windows 构建与运行',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionLabel = 'v${info.version}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _versionLabel = 'v0.4.9';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更新日志')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: ListTile(
              leading: const Icon(Icons.new_releases_outlined),
              title: const Text('当前应用版本'),
              subtitle: Text(_versionLabel),
            ),
          ),
          const SizedBox(height: 12),
          for (final _ChangelogEntry entry in _entries)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${entry.version} (${entry.date})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final String note in entry.notes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $note'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChangelogEntry {
  const _ChangelogEntry({
    required this.version,
    required this.date,
    required this.notes,
  });

  final String version;
  final String date;
  final List<String> notes;
}
