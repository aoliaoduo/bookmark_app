import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app/export/export_service.dart';
import 'app/local/bookmark_repository.dart';
import 'app/local/local_database.dart';
import 'app/local/windows_data_migration.dart';
import 'app/maintenance/maintenance_service.dart';
import 'app/settings/app_settings.dart';
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
  AppThemePreference _themePreference = AppThemePreference.system;

  void _onControllerChanged() {
    final AppController? controller = _controller;
    if (controller == null) return;
    final AppThemePreference next = controller.settings.themePreference;
    if (next == _themePreference) return;
    if (!mounted) return;
    setState(() {
      _themePreference = next;
    });
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await WindowsDataMigration.migrateLegacyBookmarkAppData();
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
      controller.addListener(_onControllerChanged);

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _themePreference = controller.settings.themePreference;
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
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '粮仓',
      themeMode: _themePreference.themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: _buildHome(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0E8A86),
      brightness: brightness,
    );
    final bool isDark = brightness == Brightness.dark;
    final String? appFontFamily = _fontFamilyForPlatform();
    final TextTheme baseTextTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
    ).textTheme;
    final TextTheme textTheme = appFontFamily == null
        ? baseTextTheme
        : baseTextTheme.apply(fontFamily: appFontFamily);

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: appFontFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF12191A) : const Color(0xFFF4F7F8),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 3,
        shadowColor: colorScheme.shadow.withValues(alpha: isDark ? 0.45 : 0.14),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 0.6 : 1,
            ),
          ),
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
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll<TextStyle?>(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  String? _fontFamilyForPlatform() {
    if (kIsWeb) {
      return null;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return 'Microsoft YaHei';
    }
    return null;
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
