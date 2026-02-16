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
        _versionLabel = 'v0.3.1';
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
