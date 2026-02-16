import 'package:flutter/material.dart';

import '../settings/app_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _daysController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _userIdController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  late bool _webDavEnabled;
  late bool _autoRefreshOnLaunch;

  @override
  void initState() {
    super.initState();
    final AppSettings s = widget.settings;
    _daysController = TextEditingController(
      text: s.titleRefreshDays.toString(),
    );
    _baseUrlController = TextEditingController(text: s.webDavBaseUrl);
    _userIdController = TextEditingController(text: s.webDavUserId);
    _usernameController = TextEditingController(text: s.webDavUsername);
    _passwordController = TextEditingController(text: s.webDavPassword);
    _webDavEnabled = s.webDavEnabled;
    _autoRefreshOnLaunch = s.autoRefreshOnLaunch;
  }

  @override
  void dispose() {
    _daysController.dispose();
    _baseUrlController.dispose();
    _userIdController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          SwitchListTile(
            value: _autoRefreshOnLaunch,
            onChanged: (bool value) {
              setState(() {
                _autoRefreshOnLaunch = value;
              });
            },
            title: const Text('启动时自动刷新过期标题'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _daysController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '标题自动更新周期（天）',
            ),
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            value: _webDavEnabled,
            onChanged: (bool value) {
              setState(() {
                _webDavEnabled = value;
              });
            },
            title: const Text('启用 WebDAV 云同步/备份'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'WebDAV Base URL',
              hintText: 'https://dav.example.com/remote.php/dav/files/yourname',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _userIdController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '应用内用户 ID（用于云端目录）',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'WebDAV 用户名',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'WebDAV 密码',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('保存设置')),
        ],
      ),
    );
  }

  void _save() {
    final int days = int.tryParse(_daysController.text.trim()) ?? 7;
    final AppSettings next = widget.settings.copyWith(
      titleRefreshDays: days < 1 ? 1 : days,
      autoRefreshOnLaunch: _autoRefreshOnLaunch,
      webDavEnabled: _webDavEnabled,
      webDavBaseUrl: _baseUrlController.text.trim(),
      webDavUserId: _userIdController.text.trim(),
      webDavUsername: _usernameController.text.trim(),
      webDavPassword: _passwordController.text,
    );
    Navigator.of(context).pop(next);
  }
}
