import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app/export/export_service.dart';
import 'app/local/bookmark_repository.dart';
import 'app/local/local_database.dart';
import 'app/maintenance/maintenance_service.dart';
import 'app/settings/settings_store.dart';
import 'app/ui/home_page.dart';
import 'core/metadata/metadata_fetch_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BookmarkApp());
}

class BookmarkApp extends StatefulWidget {
  const BookmarkApp({super.key});

  @override
  State<BookmarkApp> createState() => _BookmarkAppState();
}

class _BookmarkAppState extends State<BookmarkApp> {
  AppController? _controller;
  Object? _bootstrapError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final SettingsStore settingsStore = SettingsStore();
      final settings = await settingsStore.load();
      final db = await LocalDatabase.instance.database;

      final BookmarkRepository repository = BookmarkRepository(
        db: db,
        metadataService: MetadataFetchService(),
        deviceId: settings.deviceId,
      );

      final AppController controller = AppController(
        repository: repository,
        settingsStore: settingsStore,
        exportService: ExportService(),
        maintenanceService: MaintenanceService(db: db),
      );
      await controller.initialize();

      if (!mounted) return;
      setState(() {
        _controller = controller;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootstrapError = e;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0E8A86),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '网址收藏',
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7F8),
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: colorScheme.surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: colorScheme.primary,
              width: 1.4,
            ),
          ),
        ),
        tabBarTheme: TabBarThemeData(
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_bootstrapError != null) {
      return Scaffold(body: Center(child: Text('初始化失败: $_bootstrapError')));
    }

    final AppController? controller = _controller;
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return HomePage(controller: controller);
  }
}
