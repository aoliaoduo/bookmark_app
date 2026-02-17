import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'changelog_page.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _versionLabel = '-';

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
        _versionLabel = 'v0.5.16';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            '粮仓 App',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            '当前版本：$_versionLabel',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
          Text('作者：奥里奥多', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: const Text('更新日志'),
              subtitle: const Text('查看各版本功能更新记录'),
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => const ChangelogPage(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '技术栈',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 10),
                  const _TechItem(
                    name: 'Flutter',
                    desc: '跨平台 UI 框架（Android / Windows）',
                  ),
                  const _TechItem(name: 'Dart', desc: '应用核心语言'),
                  const _TechItem(
                    name: 'SQLite (sqflite)',
                    desc: '本地优先数据存储',
                  ),
                  const _TechItem(name: 'WebDAV', desc: '云同步与云备份协议'),
                  const _TechItem(
                    name: 'HTTP + html parser',
                    desc: '网页请求与标题解析',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '说明：该应用默认本地优先，云同步/备份在设置中启用并配置。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TechItem extends StatelessWidget {
  const _TechItem({required this.name, required this.desc});

  final String name;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: <InlineSpan>[
                  TextSpan(
                    text: name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: '：$desc'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
