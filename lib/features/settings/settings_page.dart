import 'package:flutter/material.dart';

import '../../core/i18n/app_strings.dart';
import 'about_diagnostics_page.dart';
import 'ai_provider_page.dart';
import 'maintenance_page.dart';
import 'notification_channels_page.dart';
import 'sync_page.dart';
import 'theme_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settingsPageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(context, AppStrings.settingsGroupAi),
          _entry(
            context,
            icon: Icons.tune_outlined,
            title: AppStrings.aiProviderTitle,
            pageBuilder: (_) => const AiProviderPage(),
          ),
          _sectionTitle(context, AppStrings.settingsGroupSync),
          _entry(
            context,
            icon: Icons.sync_outlined,
            title: AppStrings.syncPageTitle,
            pageBuilder: (_) => const SyncPage(),
          ),
          _sectionTitle(context, AppStrings.settingsGroupBackup),
          _entry(
            context,
            icon: Icons.backup_outlined,
            title: AppStrings.backupSectionTitle,
            pageBuilder: (_) => const SyncPage(),
          ),
          _sectionTitle(context, AppStrings.settingsGroupNotify),
          _entry(
            context,
            icon: Icons.notifications_active_outlined,
            title: AppStrings.notifyOpenSettings,
            pageBuilder: (_) => const NotificationChannelsPage(),
          ),
          _sectionTitle(context, AppStrings.settingsGroupAppearance),
          _entry(
            context,
            icon: Icons.palette_outlined,
            title: AppStrings.openThemeSettings,
            pageBuilder: (_) => const ThemePage(),
          ),
          _sectionTitle(context, AppStrings.settingsGroupMaintenance),
          _entry(
            context,
            icon: Icons.build_outlined,
            title: AppStrings.openMaintenanceTools,
            pageBuilder: (_) => const MaintenancePage(),
          ),
          _sectionTitle(context, AppStrings.settingsGroupAbout),
          _entry(
            context,
            icon: Icons.health_and_safety_outlined,
            title: AppStrings.settingsAboutDiagnostics,
            pageBuilder: (_) => const AboutDiagnosticsPage(),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(AppStrings.settingsAboutText),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _entry(
    BuildContext context, {
    required IconData icon,
    required String title,
    required WidgetBuilder pageBuilder,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: pageBuilder));
      },
    );
  }
}
