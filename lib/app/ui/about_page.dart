import 'package:flutter/material.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const <Widget>[
          Text(
            '网址收藏 App',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 10),
          Text('作者：奥里奥多', style: TextStyle(fontSize: 16)),
          SizedBox(height: 20),
          Text(
            '技术栈',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 10),
          _TechItem(name: 'Flutter', desc: '跨平台 UI 框架（Android / Windows）'),
          _TechItem(name: 'Dart', desc: '应用核心语言'),
          _TechItem(name: 'SQLite (sqflite)', desc: '本地优先数据存储'),
          _TechItem(name: 'WebDAV', desc: '云同步与云备份协议'),
          _TechItem(name: 'HTTP + html parser', desc: '网页请求与标题解析'),
          SizedBox(height: 20),
          Text(
            '说明：该应用默认本地优先，云同步/备份在设置中启用并配置。',
            style: TextStyle(color: Colors.black54),
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
