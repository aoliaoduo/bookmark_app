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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '网址收藏',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
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
