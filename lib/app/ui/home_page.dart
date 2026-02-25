import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../core/domain/bookmark.dart';
import '../../core/metadata/title_fetch_note.dart';
import '../../platform/platform_services.dart';
import '../app_controller.dart';
import '../export/export_service.dart';
import '../maintenance/maintenance_service.dart';
import '../settings/app_settings.dart';
import '../sync_coordinator.dart';
import 'about_page.dart';
import 'changelog_page.dart';
import 'settings_page.dart';

enum _HomeMenuAction {
  emptyTrash,
  backupNow,
  exportAllJson,
  exportAllCsv,
  exportAllMd,
  dedupExact,
  dedupSimilar,
  dedupAll,
  slimDown,
  changelog,
  clearAllData,
}

enum _SelectionMenuAction {
  exportSelectedJson,
  exportSelectedCsv,
  exportSelectedMd,
}

enum _CompactHomeAction {
  refreshAllTitles,
  refreshStaleTitles,
  emptyTrash,
  backupNow,
  exportAllJson,
  exportAllCsv,
  exportAllMd,
  dedupExact,
  dedupSimilar,
  dedupAll,
  slimDown,
  changelog,
  clearAllData,
  about,
  settings,
}

enum _CompactSelectionAction {
  toggleSelectAll,
  restoreSelected,
  deleteSelectedForever,
  refreshSelectedTitles,
  deleteSelected,
  exportSelectedJson,
  exportSelectedCsv,
  exportSelectedMd,
}

enum _SortOption { updatedDesc, createdDesc, titleAsc, urlAsc }

enum _TopSyncState { syncing, success, error, idle, notReady }

@visibleForTesting
Uri? parseExternalHttpUri(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final Uri? uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return null;
  }

  final String scheme = uri.scheme.toLowerCase();
  final bool isHttp = scheme == 'http' || scheme == 'https';
  if (!isHttp || !uri.hasAuthority || uri.host.trim().isEmpty) {
    return null;
  }
  return uri;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  bool _showTrash = false;
  bool _selectionMode = false;
  _SortOption _sortOption = _SortOption.updatedDesc;
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _sortOption = _sortOptionFromPreference(
      widget.controller.settings.homeSortPreference,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerStartupAutoSync();
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final AppController controller = widget.controller;
        final List<Bookmark> allBookmarks = controller.bookmarks;
        final List<Bookmark> allTrash = controller.trashBookmarks;

        final List<Bookmark> bookmarks = _applySort(
          _applySearch(allBookmarks),
          fromTrash: false,
        );
        final List<Bookmark> trash = _applySort(
          _applySearch(allTrash),
          fromTrash: true,
        );
        final List<Bookmark> currentItems = _showTrash ? trash : bookmarks;
        final bool compactActions = _useCompactActionsLayout(context);

        _pruneSelection(allBookmarks, allTrash);

        return Scaffold(
          appBar: AppBar(
            title: _buildTopBarTitle(
              controller,
              compactActions: compactActions,
            ),
            actions: _selectionMode
                ? _buildSelectionActions(
                    controller,
                    currentItems,
                    compactActions: compactActions,
                  )
                : _buildNormalActions(
                    controller,
                    trash,
                    currentItems,
                    compactActions: compactActions,
                  ),
          ),
          body: Stack(
            children: <Widget>[
              Positioned.fill(child: _buildAtmosphereBackground()),
              Column(
                children: <Widget>[
                  if (!_showTrash)
                    _buildInputArea(controller)
                  else
                    _buildTrashHint(),
                  _buildSearchArea(),
                  _buildSyncStatusBar(controller),
                  if (controller.batchRefreshing)
                    _buildBatchProgress(controller)
                  else if (controller.loading)
                    const LinearProgressIndicator(),
                  if (controller.error != null)
                    MaterialBanner(
                      content: Text(controller.error!),
                      actions: <Widget>[
                        TextButton(
                          onPressed: controller.clearError,
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  _buildMetaBar(
                    controller: controller,
                    allBookmarks: allBookmarks,
                    allTrash: allTrash,
                  ),
                  Expanded(
                    child: _showTrash
                        ? _buildTrashList(trash)
                        : _buildBookmarkList(bookmarks),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildNormalActions(
    AppController controller,
    List<Bookmark> trash,
    List<Bookmark> currentItems, {
    required bool compactActions,
  }) {
    if (compactActions) {
      return <Widget>[
        IconButton(
          tooltip: '批量操作',
          onPressed: () => _enterSelectionMode(currentItems),
          icon: const Icon(Icons.checklist),
        ),
        _buildSyncActionButton(controller),
        PopupMenuButton<_CompactHomeAction>(
          tooltip: '更多操作',
          onSelected: (_CompactHomeAction action) {
            _onCompactHomeAction(action, controller);
          },
          itemBuilder: (BuildContext context) =>
              <PopupMenuEntry<_CompactHomeAction>>[
            if (!_showTrash)
              PopupMenuItem<_CompactHomeAction>(
                value: _CompactHomeAction.refreshAllTitles,
                enabled: !controller.loading,
                child: const Text('一键更新全部标题'),
              ),
            if (!_showTrash)
              PopupMenuItem<_CompactHomeAction>(
                value: _CompactHomeAction.refreshStaleTitles,
                enabled: !controller.loading,
                child: const Text('刷新过期标题'),
              ),
            PopupMenuItem<_CompactHomeAction>(
              value: _CompactHomeAction.emptyTrash,
              enabled: !controller.loading && trash.isNotEmpty,
              child: const Text('清空回收站'),
            ),
            PopupMenuItem<_CompactHomeAction>(
              value: _CompactHomeAction.backupNow,
              enabled: !controller.loading &&
                  !controller.syncing &&
                  !controller.backingUp,
              child: const Text('云备份'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<_CompactHomeAction>(
              value: _CompactHomeAction.exportAllJson,
              child: Text('导出全部(JSON)'),
            ),
            const PopupMenuItem<_CompactHomeAction>(
              value: _CompactHomeAction.exportAllCsv,
              child: Text('导出全部(CSV)'),
            ),
            const PopupMenuItem<_CompactHomeAction>(
              value: _CompactHomeAction.exportAllMd,
              child: Text('导出全部(MD)'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<_CompactHomeAction>(
              value: _CompactHomeAction.dedupExact,
              child: Text('去重（重复）'),
            ),
            const PopupMenuItem<_CompactHomeAction>(
              value: _CompactHomeAction.dedupSimilar,
              child: Text('去重（相似）'),
            ),
            const PopupMenuItem<_CompactHomeAction>(
              value: _CompactHomeAction.dedupAll,
              child: Text('去重（重复+相似）'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<_CompactHomeAction>(
              value: _CompactHomeAction.slimDown,
              child: Text('瘦身清理'),
            ),
            const PopupMenuItem<_CompactHomeAction>(
              value: _CompactHomeAction.changelog,
              child: Text('更新日志'),
            ),
            PopupMenuItem<_CompactHomeAction>(
              value: _CompactHomeAction.clearAllData,
              enabled: !controller.loading,
              child: const Text('清空全部数据'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<_CompactHomeAction>(
              value: _CompactHomeAction.about,
              child: Text('关于'),
            ),
            PopupMenuItem<_CompactHomeAction>(
              value: _CompactHomeAction.settings,
              enabled: !controller.loading,
              child: const Text('设置'),
            ),
          ],
        ),
      ];
    }

    final List<Widget> actions = <Widget>[
      IconButton(
        tooltip: '批量操作',
        onPressed: () => _enterSelectionMode(currentItems),
        icon: const Icon(Icons.checklist),
      ),
      _buildSyncActionButton(controller),
    ];

    if (!_showTrash) {
      actions.addAll(<Widget>[
        IconButton(
          tooltip: '一键更新全部标题',
          onPressed: controller.loading ? null : _refreshAllTitles,
          icon: const Icon(Icons.flash_on),
        ),
        IconButton(
          tooltip: '刷新过期标题',
          onPressed: controller.loading ? null : _refreshStaleTitles,
          icon: const Icon(Icons.auto_awesome),
        ),
      ]);
    }

    actions.addAll(<Widget>[
      PopupMenuButton<_HomeMenuAction>(
        tooltip: '更多功能',
        onSelected: (_HomeMenuAction action) =>
            _onHomeMenuAction(action, controller: controller, trash: trash),
        itemBuilder: (BuildContext context) =>
            <PopupMenuEntry<_HomeMenuAction>>[
          PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.emptyTrash,
            enabled: !controller.loading && trash.isNotEmpty,
            child: const Text('清空回收站'),
          ),
          PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.backupNow,
            enabled: !controller.loading &&
                !controller.syncing &&
                !controller.backingUp,
            child: const Text('云备份'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.exportAllJson,
            child: Text('导出全部(JSON)'),
          ),
          const PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.exportAllCsv,
            child: Text('导出全部(CSV)'),
          ),
          const PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.exportAllMd,
            child: Text('导出全部(MD)'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.dedupExact,
            child: Text('去重（重复）'),
          ),
          const PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.dedupSimilar,
            child: Text('去重（相似）'),
          ),
          const PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.dedupAll,
            child: Text('去重（重复+相似）'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.slimDown,
            child: Text('瘦身清理'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.changelog,
            child: Text('更新日志'),
          ),
          PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.clearAllData,
            enabled: !controller.loading,
            child: const Text('清空全部数据'),
          ),
        ],
      ),
      IconButton(
        tooltip: '关于',
        onPressed: _openAbout,
        icon: const Icon(Icons.info_outline),
      ),
      IconButton(
        tooltip: '设置',
        onPressed: controller.loading ? null : () => _openSettings(controller),
        icon: const Icon(Icons.settings),
      ),
    ]);

    return actions;
  }

  List<Widget> _buildSelectionActions(
    AppController controller,
    List<Bookmark> currentTabItems, {
    required bool compactActions,
  }) {
    final bool hasSelection = _selectedIds.isNotEmpty;
    final bool allSelected = currentTabItems.isNotEmpty &&
        currentTabItems.every(
          (Bookmark item) => _selectedIds.contains(item.id),
        );

    if (compactActions) {
      return <Widget>[
        IconButton(
          tooltip: '退出批量',
          onPressed: _clearSelection,
          icon: const Icon(Icons.close),
        ),
        PopupMenuButton<_CompactSelectionAction>(
          tooltip: '批量菜单',
          onSelected: (_CompactSelectionAction action) {
            _onCompactSelectionAction(action, currentTabItems: currentTabItems);
          },
          itemBuilder: (BuildContext context) =>
              <PopupMenuEntry<_CompactSelectionAction>>[
            PopupMenuItem<_CompactSelectionAction>(
              value: _CompactSelectionAction.toggleSelectAll,
              enabled: currentTabItems.isNotEmpty,
              child: Text(allSelected ? '取消全选' : '全选当前列表'),
            ),
            const PopupMenuDivider(),
            if (_showTrash)
              PopupMenuItem<_CompactSelectionAction>(
                value: _CompactSelectionAction.restoreSelected,
                enabled: hasSelection && !controller.loading,
                child: const Text('批量恢复'),
              ),
            if (_showTrash)
              PopupMenuItem<_CompactSelectionAction>(
                value: _CompactSelectionAction.deleteSelectedForever,
                enabled: hasSelection && !controller.loading,
                child: const Text('批量永久删除'),
              ),
            if (!_showTrash)
              PopupMenuItem<_CompactSelectionAction>(
                value: _CompactSelectionAction.refreshSelectedTitles,
                enabled: hasSelection && !controller.loading,
                child: const Text('批量更新标题'),
              ),
            if (!_showTrash)
              PopupMenuItem<_CompactSelectionAction>(
                value: _CompactSelectionAction.deleteSelected,
                enabled: hasSelection && !controller.loading,
                child: const Text('批量删除到回收站'),
              ),
            PopupMenuItem<_CompactSelectionAction>(
              value: _CompactSelectionAction.exportSelectedJson,
              enabled: hasSelection && !controller.loading,
              child: const Text('导出已选(JSON)'),
            ),
            PopupMenuItem<_CompactSelectionAction>(
              value: _CompactSelectionAction.exportSelectedCsv,
              enabled: hasSelection && !controller.loading,
              child: const Text('导出已选(CSV)'),
            ),
            PopupMenuItem<_CompactSelectionAction>(
              value: _CompactSelectionAction.exportSelectedMd,
              enabled: hasSelection && !controller.loading,
              child: const Text('导出已选(MD)'),
            ),
          ],
        ),
      ];
    }

    final List<Widget> actions = <Widget>[
      IconButton(
        tooltip: '退出批量',
        onPressed: _clearSelection,
        icon: const Icon(Icons.close),
      ),
      IconButton(
        tooltip: allSelected ? '取消全选' : '全选当前列表',
        onPressed: currentTabItems.isEmpty
            ? null
            : () => _toggleSelectAll(currentTabItems),
        icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
      ),
    ];

    if (_showTrash) {
      actions.add(
        IconButton(
          tooltip: '批量恢复',
          onPressed:
              !hasSelection || controller.loading ? null : _restoreSelected,
          icon: const Icon(Icons.restore_from_trash),
        ),
      );
      actions.add(
        IconButton(
          tooltip: '批量永久删除',
          onPressed: !hasSelection || controller.loading
              ? null
              : _deleteSelectedForever,
          icon: const Icon(Icons.delete_forever),
        ),
      );
    } else {
      actions.add(
        IconButton(
          tooltip: '批量更新标题',
          onPressed: !hasSelection || controller.loading
              ? null
              : _refreshSelectedTitles,
          icon: const Icon(Icons.refresh),
        ),
      );
      actions.add(
        IconButton(
          tooltip: '批量删除到回收站',
          onPressed:
              !hasSelection || controller.loading ? null : _deleteSelected,
          icon: const Icon(Icons.delete_outline),
        ),
      );
    }

    actions.add(
      PopupMenuButton<_SelectionMenuAction>(
        tooltip: '导出已选',
        enabled: hasSelection && !controller.loading,
        onSelected: (_SelectionMenuAction action) async {
          switch (action) {
            case _SelectionMenuAction.exportSelectedJson:
              await _exportSelected(ExportFormat.json);
              break;
            case _SelectionMenuAction.exportSelectedCsv:
              await _exportSelected(ExportFormat.csv);
              break;
            case _SelectionMenuAction.exportSelectedMd:
              await _exportSelected(ExportFormat.md);
              break;
          }
        },
        itemBuilder: (BuildContext context) =>
            <PopupMenuEntry<_SelectionMenuAction>>[
          const PopupMenuItem<_SelectionMenuAction>(
            value: _SelectionMenuAction.exportSelectedJson,
            child: Text('导出已选(JSON)'),
          ),
          const PopupMenuItem<_SelectionMenuAction>(
            value: _SelectionMenuAction.exportSelectedCsv,
            child: Text('导出已选(CSV)'),
          ),
          const PopupMenuItem<_SelectionMenuAction>(
            value: _SelectionMenuAction.exportSelectedMd,
            child: Text('导出已选(MD)'),
          ),
        ],
      ),
    );

    return actions;
  }

  Widget _buildAtmosphereBackground() {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -170,
            right: -120,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    theme.colorScheme.primary.withValues(
                      alpha: isDark ? 0.22 : 0.16,
                    ),
                    theme.colorScheme.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -180,
            left: -130,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    theme.colorScheme.secondary.withValues(
                      alpha: isDark ? 0.16 : 0.11,
                    ),
                    theme.colorScheme.secondary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassPanel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(10),
  }) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final BorderRadius borderRadius = BorderRadius.circular(16);
    final Color panelBase = isDark
        ? theme.colorScheme.surface.withValues(alpha: 0.7)
        : Colors.white.withValues(alpha: 0.84);
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.alphaBlend(
              Colors.white.withValues(alpha: isDark ? 0.08 : 0.26),
              panelBase,
            ),
            Color.alphaBlend(
              Colors.black.withValues(alpha: isDark ? 0.14 : 0.06),
              panelBase,
            ),
          ],
        ),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(
            alpha: isDark ? 0.5 : 0.85,
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.white.withValues(alpha: isDark ? 0.04 : 0.28),
            blurRadius: 10,
            offset: const Offset(-2, -2),
          ),
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(
              alpha: isDark ? 0.24 : 0.1,
            ),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: const <double>[0, 0.55, 1],
                      colors: <Color>[
                        Colors.white.withValues(alpha: isDark ? 0.14 : 0.26),
                        Colors.transparent,
                        Colors.black.withValues(alpha: isDark ? 0.16 : 0.06),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _GlassTexturePainter(
                    color: (isDark ? Colors.white : Colors.black).withValues(
                      alpha: isDark ? 0.035 : 0.02,
                    ),
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaBar({
    required AppController controller,
    required List<Bookmark> allBookmarks,
    required List<Bookmark> allTrash,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool narrow = constraints.maxWidth < 620;
          final Widget sortButton = PopupMenuButton<_SortOption>(
            tooltip: '排序',
            onSelected: _onSortOptionSelected,
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<_SortOption>>[
              CheckedPopupMenuItem<_SortOption>(
                value: _SortOption.updatedDesc,
                checked: _sortOption == _SortOption.updatedDesc,
                child: const Text('按最近更新'),
              ),
              CheckedPopupMenuItem<_SortOption>(
                value: _SortOption.createdDesc,
                checked: _sortOption == _SortOption.createdDesc,
                child: const Text('按最近添加'),
              ),
              CheckedPopupMenuItem<_SortOption>(
                value: _SortOption.titleAsc,
                checked: _sortOption == _SortOption.titleAsc,
                child: const Text('按标题 A-Z'),
              ),
              CheckedPopupMenuItem<_SortOption>(
                value: _SortOption.urlAsc,
                checked: _sortOption == _SortOption.urlAsc,
                child: const Text('按网址 A-Z'),
              ),
            ],
            child: _buildMetaChip(
              icon: Icons.sort_rounded,
              label: _sortOptionLabel(_sortOption),
            ),
          );
          final Widget countChip = _buildMetaChip(
            icon: Icons.bookmarks_outlined,
            label: '收藏 ${allBookmarks.length} / 回收站 ${allTrash.length}',
          );
          final Widget modeText = Row(
            children: <Widget>[
              Icon(
                _showTrash ? Icons.delete_outline : Icons.schedule_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _showTrash
                      ? '回收站模式：可恢复或永久删除'
                      : '自动更新周期：每 ${controller.settings.titleRefreshDays} 天',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          );

          if (narrow) {
            return _buildGlassPanel(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  modeText,
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      sortButton,
                      const SizedBox(width: 8),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: countChip,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }

          return _buildGlassPanel(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              children: <Widget>[
                Expanded(child: modeText),
                const SizedBox(width: 8),
                sortButton,
                const SizedBox(width: 8),
                countChip,
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetaChip({required IconData icon, required String label}) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.72,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.85),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(AppController controller) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color fieldBase = isDark
        ? theme.colorScheme.surface.withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.9);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color.alphaBlend(
                      Colors.white.withValues(alpha: isDark ? 0.08 : 0.2),
                      fieldBase,
                    ),
                    Color.alphaBlend(
                      Colors.black.withValues(alpha: isDark ? 0.08 : 0.04),
                      fieldBase,
                    ),
                  ],
                ),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: isDark ? 0.5 : 0.72,
                  ),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: theme.colorScheme.shadow.withValues(
                      alpha: isDark ? 0.2 : 0.1,
                    ),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.link_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      enabled: !controller.loading,
                      textAlignVertical: TextAlignVertical.center,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.1),
                      decoration: InputDecoration(
                        hintText: '输入网址',
                        hintStyle: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.92,
                          ),
                        ),
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                      ),
                      onSubmitted: (_) => _addUrl(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _GlassTactileButton(
            tooltip: '收藏',
            onPressed: controller.loading ? null : _addUrl,
            singleLayer: true,
            radius: 16,
            size: const Size(102, 46),
            tintColor: theme.colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.add_link,
                  size: 18,
                  color: theme.colorScheme.onPrimary,
                ),
                const SizedBox(width: 6),
                Text(
                  '收藏',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchArea() {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: _buildGlassPanel(
        padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.search_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '搜索标题或网址',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  filled: false,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: _GlassTactileButton(
                  tooltip: '清空搜索',
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  radius: 10,
                  size: const Size.square(34),
                  padding: EdgeInsets.zero,
                  tintColor: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.clear,
                    size: 17,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrashHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: _buildGlassPanel(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.delete_sweep_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '当前查看回收站，可恢复或永久删除条目',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchProgress(AppController controller) {
    final int total = controller.batchTotal;
    final int processed = controller.batchProcessed;
    final int updated = controller.batchUpdated;
    final String label =
        total <= 0 ? '正在准备批量更新...' : '正在更新标题：$processed / $total（成功 $updated）';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: _buildGlassPanel(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          children: <Widget>[
            LinearProgressIndicator(value: controller.batchProgress),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookmarkList(List<Bookmark> bookmarks) {
    if (bookmarks.isEmpty) {
      return const Center(child: Text('还没有匹配的收藏'));
    }

    final AppController controller = widget.controller;
    return ListView.builder(
      itemCount: bookmarks.length,
      itemBuilder: (BuildContext context, int index) {
        final Bookmark item = bookmarks[index];
        final String? issue = parseTitleFetchFailureNote(item.note);
        final String titleText = item.title?.trim().isNotEmpty == true
            ? item.title!
            : (issue == null ? '(未获取标题)' : '(标题抓取失败)');
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          elevation: 0,
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            leading: _selectionMode
                ? Checkbox(
                    value: _selectedIds.contains(item.id),
                    onChanged: (_) => _toggleSelected(item.id),
                  )
                : null,
            title: Text(
              titleText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 2),
                Text(
                  item.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '添加: ${_formatDateTime(item.createdAt)}  更新: ${_formatDateTime(item.updatedAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.92),
                      ),
                ),
                if (issue != null) ...<Widget>[
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _showTitleIssueActions(item, issue),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Theme.of(
                          context,
                        ).colorScheme.errorContainer.withValues(alpha: 0.72),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '标题获取失败：$issue',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                          Text(
                            '处理',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            isThreeLine: false,
            onTap: () {
              if (_selectionMode) {
                _toggleSelected(item.id);
              } else {
                _openUrl(item.url);
              }
            },
            onLongPress: () => _startSelection(item.id),
            trailing: _selectionMode
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _buildInlineActionButton(
                        tooltip: '打开网址',
                        icon: Icons.open_in_new,
                        onPressed: () => _openUrl(item.url),
                      ),
                      _buildInlineActionButton(
                        tooltip: '复制链接',
                        icon: Icons.content_copy_outlined,
                        onPressed: () => _copyUrl(item.url),
                      ),
                      _buildInlineActionButton(
                        tooltip: '删除到回收站',
                        icon: Icons.delete_outline,
                        tintColor: Theme.of(
                          context,
                        ).colorScheme.errorContainer.withValues(alpha: 0.78),
                        onPressed: controller.loading
                            ? null
                            : () => _deleteBookmarkInline(item),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildTrashList(List<Bookmark> trash) {
    if (trash.isEmpty) {
      return const Center(child: Text('回收站是空的'));
    }

    final AppController controller = widget.controller;
    return ListView.builder(
      itemCount: trash.length,
      itemBuilder: (BuildContext context, int index) {
        final Bookmark item = trash[index];
        final String deletedAt =
            item.deletedAt == null ? '-' : _formatDateTime(item.deletedAt!);
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          elevation: 0,
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            leading: _selectionMode
                ? Checkbox(
                    value: _selectedIds.contains(item.id),
                    onChanged: (_) => _toggleSelected(item.id),
                  )
                : null,
            title: Text(
              item.title?.trim().isNotEmpty == true ? item.title! : item.url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '添加: ${_formatDateTime(item.createdAt)}  更新: ${_formatDateTime(item.updatedAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  '删除: $deletedAt',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            isThreeLine: false,
            onTap: () {
              if (_selectionMode) {
                _toggleSelected(item.id);
              }
            },
            onLongPress: () => _startSelection(item.id),
            trailing: _selectionMode
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _buildInlineActionButton(
                        tooltip: '复制链接',
                        icon: Icons.content_copy_outlined,
                        onPressed: () => _copyUrl(item.url),
                      ),
                      _buildInlineActionButton(
                        tooltip: '恢复',
                        icon: Icons.restore_from_trash,
                        tintColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.8),
                        onPressed: controller.loading
                            ? null
                            : () => controller.restoreBookmark(item.id),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  List<Bookmark> _applySearch(List<Bookmark> source) {
    final String query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source.where((Bookmark b) {
      final String title = (b.title ?? '').toLowerCase();
      final String url = b.url.toLowerCase();
      return title.contains(query) || url.contains(query);
    }).toList();
  }

  List<Bookmark> _applySort(List<Bookmark> source, {required bool fromTrash}) {
    final List<Bookmark> sorted = List<Bookmark>.from(source);
    sorted.sort((Bookmark a, Bookmark b) {
      switch (_sortOption) {
        case _SortOption.updatedDesc:
          if (fromTrash) {
            final DateTime ad = a.deletedAt ?? a.updatedAt;
            final DateTime bd = b.deletedAt ?? b.updatedAt;
            final int deletedCmp = bd.compareTo(ad);
            if (deletedCmp != 0) return deletedCmp;
          }
          final int updatedCmp = b.updatedAt.compareTo(a.updatedAt);
          if (updatedCmp != 0) return updatedCmp;
          return b.createdAt.compareTo(a.createdAt);
        case _SortOption.createdDesc:
          final int createdCmp = b.createdAt.compareTo(a.createdAt);
          if (createdCmp != 0) return createdCmp;
          return b.updatedAt.compareTo(a.updatedAt);
        case _SortOption.titleAsc:
          final String at =
              (a.title?.trim().isNotEmpty == true ? a.title! : a.url)
                  .toLowerCase();
          final String bt =
              (b.title?.trim().isNotEmpty == true ? b.title! : b.url)
                  .toLowerCase();
          final int titleCmp = at.compareTo(bt);
          if (titleCmp != 0) return titleCmp;
          return a.url.toLowerCase().compareTo(b.url.toLowerCase());
        case _SortOption.urlAsc:
          final int urlCmp = a.url.toLowerCase().compareTo(b.url.toLowerCase());
          if (urlCmp != 0) return urlCmp;
          return a.updatedAt.compareTo(b.updatedAt);
      }
    });
    return sorted;
  }

  String _sortOptionLabel(_SortOption option) {
    switch (option) {
      case _SortOption.updatedDesc:
        return '最近更新';
      case _SortOption.createdDesc:
        return '最近添加';
      case _SortOption.titleAsc:
        return '标题 A-Z';
      case _SortOption.urlAsc:
        return '网址 A-Z';
    }
  }

  void _onSortOptionSelected(_SortOption option) {
    if (_sortOption == option) {
      return;
    }
    setState(() {
      _sortOption = option;
    });
    unawaited(
      widget.controller.saveHomeSortPreference(
        _sortPreferenceFromOption(option),
      ),
    );
  }

  _SortOption _sortOptionFromPreference(HomeSortPreference preference) {
    switch (preference) {
      case HomeSortPreference.updatedDesc:
        return _SortOption.updatedDesc;
      case HomeSortPreference.createdDesc:
        return _SortOption.createdDesc;
      case HomeSortPreference.titleAsc:
        return _SortOption.titleAsc;
      case HomeSortPreference.urlAsc:
        return _SortOption.urlAsc;
    }
  }

  HomeSortPreference _sortPreferenceFromOption(_SortOption option) {
    switch (option) {
      case _SortOption.updatedDesc:
        return HomeSortPreference.updatedDesc;
      case _SortOption.createdDesc:
        return HomeSortPreference.createdDesc;
      case _SortOption.titleAsc:
        return HomeSortPreference.titleAsc;
      case _SortOption.urlAsc:
        return HomeSortPreference.urlAsc;
    }
  }

  void _pruneSelection(List<Bookmark> bookmarks, List<Bookmark> trash) {
    final Set<String> valid = <String>{
      ...bookmarks.map((Bookmark b) => b.id),
      ...trash.map((Bookmark b) => b.id),
    };
    _selectedIds.removeWhere((String id) => !valid.contains(id));
  }

  void _toggleTrashMode(bool showTrash) {
    setState(() {
      _showTrash = showTrash;
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _startSelection(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _enterSelectionMode(List<Bookmark> currentTabItems) {
    setState(() {
      _selectionMode = true;
      _selectedIds.clear();
    });
    if (currentTabItems.isEmpty) {
      _showSnack('当前列表没有可批量操作的数据');
    } else {
      _showSnack('已进入批量模式，请勾选或全选条目');
    }
  }

  void _toggleSelectAll(List<Bookmark> items) {
    final Set<String> ids = items.map((Bookmark item) => item.id).toSet();
    final bool allSelected = ids.isNotEmpty && ids.every(_selectedIds.contains);
    setState(() {
      if (allSelected) {
        _selectedIds.removeWhere((String id) => ids.contains(id));
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  bool _useCompactActionsLayout(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 900;
  }

  Future<void> _onCompactHomeAction(
    _CompactHomeAction action,
    AppController controller,
  ) async {
    switch (action) {
      case _CompactHomeAction.refreshAllTitles:
        await _refreshAllTitles();
        break;
      case _CompactHomeAction.refreshStaleTitles:
        await _refreshStaleTitles();
        break;
      case _CompactHomeAction.emptyTrash:
        await _emptyTrash();
        break;
      case _CompactHomeAction.backupNow:
        await controller.backupNow();
        break;
      case _CompactHomeAction.exportAllJson:
        await _exportAll(ExportFormat.json);
        break;
      case _CompactHomeAction.exportAllCsv:
        await _exportAll(ExportFormat.csv);
        break;
      case _CompactHomeAction.exportAllMd:
        await _exportAll(ExportFormat.md);
        break;
      case _CompactHomeAction.dedupExact:
        await _runDedup(removeExact: true, removeSimilar: false);
        break;
      case _CompactHomeAction.dedupSimilar:
        await _runDedup(removeExact: false, removeSimilar: true);
        break;
      case _CompactHomeAction.dedupAll:
        await _runDedup(removeExact: true, removeSimilar: true);
        break;
      case _CompactHomeAction.slimDown:
        await _runSlimDown();
        break;
      case _CompactHomeAction.changelog:
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => const ChangelogPage(),
          ),
        );
        break;
      case _CompactHomeAction.clearAllData:
        await _clearAllData();
        break;
      case _CompactHomeAction.about:
        _openAbout();
        break;
      case _CompactHomeAction.settings:
        await _openSettings(controller);
        break;
    }
  }

  Future<void> _onCompactSelectionAction(
    _CompactSelectionAction action, {
    required List<Bookmark> currentTabItems,
  }) async {
    switch (action) {
      case _CompactSelectionAction.toggleSelectAll:
        _toggleSelectAll(currentTabItems);
        break;
      case _CompactSelectionAction.restoreSelected:
        await _restoreSelected();
        break;
      case _CompactSelectionAction.deleteSelectedForever:
        await _deleteSelectedForever();
        break;
      case _CompactSelectionAction.refreshSelectedTitles:
        await _refreshSelectedTitles();
        break;
      case _CompactSelectionAction.deleteSelected:
        await _deleteSelected();
        break;
      case _CompactSelectionAction.exportSelectedJson:
        await _exportSelected(ExportFormat.json);
        break;
      case _CompactSelectionAction.exportSelectedCsv:
        await _exportSelected(ExportFormat.csv);
        break;
      case _CompactSelectionAction.exportSelectedMd:
        await _exportSelected(ExportFormat.md);
        break;
    }
  }

  void _openAbout() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const AboutPage(),
      ),
    );
  }

  Future<void> _openSettings(AppController controller) async {
    final AppSettings current = controller.settings;
    final AppSettings? next = await Navigator.of(context).push<AppSettings>(
      MaterialPageRoute<AppSettings>(
        builder: (BuildContext context) => SettingsPage(settings: current),
      ),
    );
    if (next != null) {
      await controller.saveSettings(next);
    }
  }

  Widget _buildTopBarTitle(
    AppController controller, {
    required bool compactActions,
  }) {
    if (_selectionMode) {
      return Text('已选择 ${_selectedIds.length} 条');
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool showSyncBadge = constraints.maxWidth >= 220;
        final bool compactBadge = compactActions || constraints.maxWidth < 320;
        return Row(
          children: <Widget>[
            Expanded(child: _buildTopModeSwitch(controller)),
            if (showSyncBadge) ...<Widget>[
              const SizedBox(width: 8),
              _buildTopSyncBadge(controller, compact: compactBadge),
            ],
          ],
        );
      },
    );
  }

  Widget _buildTopModeSwitch(AppController controller) {
    return SizedBox(
      height: 38,
      child: Row(
        children: <Widget>[
          _buildTopModeTab(
            label: '收藏',
            selected: !_showTrash,
            onTap: controller.loading || !_showTrash
                ? null
                : () => _toggleTrashMode(false),
          ),
          const SizedBox(width: 4),
          _buildTopModeTab(
            label: '回收站',
            selected: _showTrash,
            onTap: controller.loading || _showTrash
                ? null
                : () => _toggleTrashMode(true),
          ),
        ],
      ),
    );
  }

  Widget _buildTopModeTab({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color fg = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    final Color bg = selected
        ? Color.alphaBlend(
            theme.colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.14),
            theme.colorScheme.primaryContainer.withValues(alpha: 0.92),
          )
        : Color.alphaBlend(
            theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: isDark ? 0.7 : 0.86,
            ),
            theme.colorScheme.surface.withValues(alpha: isDark ? 0.66 : 0.9),
          );
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(right: label == '收藏' ? 6 : 0),
        child: _GlassTactileButton(
          tooltip: label,
          onPressed: onTap,
          visualEnabled: selected || onTap != null,
          singleLayer: true,
          radius: 999,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          tintColor: bg,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopSyncBadge(AppController controller, {required bool compact}) {
    final ThemeData theme = Theme.of(context);
    final _TopSyncState state = _resolveTopSyncState(controller);
    final Color fg;
    final Color bg;
    final IconData icon;
    switch (state) {
      case _TopSyncState.syncing:
        fg = theme.colorScheme.primary;
        bg = theme.colorScheme.primaryContainer.withValues(alpha: 0.55);
        icon = Icons.sync;
        break;
      case _TopSyncState.success:
        fg = theme.colorScheme.primary;
        bg = theme.colorScheme.primaryContainer.withValues(alpha: 0.55);
        icon = Icons.cloud_done_outlined;
        break;
      case _TopSyncState.error:
        fg = theme.colorScheme.error;
        bg = theme.colorScheme.errorContainer.withValues(alpha: 0.58);
        icon = Icons.error_outline;
        break;
      case _TopSyncState.notReady:
      case _TopSyncState.idle:
        fg = theme.colorScheme.onSurfaceVariant;
        bg = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.75);
        icon = Icons.cloud_off_outlined;
        break;
    }
    return _GlassTactileButton(
      onPressed: null,
      visualEnabled: true,
      singleLayer: true,
      radius: 999,
      tintColor: bg,
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: fg),
          if (!compact) ...<Widget>[
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 92),
              child: Text(
                _topSyncStatusText(controller),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  _TopSyncState _resolveTopSyncState(AppController controller) {
    if (controller.syncing) {
      return _TopSyncState.syncing;
    }
    final SyncRunDiagnostics? report = controller.lastSyncDiagnostics;
    if (report != null && report.success) {
      return _TopSyncState.success;
    }
    if (controller.syncError != null && controller.settings.syncReady) {
      return _TopSyncState.error;
    }
    if (controller.lastSyncAt != null && controller.settings.syncReady) {
      return _TopSyncState.success;
    }
    if (!controller.settings.syncReady) {
      return _TopSyncState.notReady;
    }
    return _TopSyncState.idle;
  }

  String _topSyncStatusText(AppController controller) {
    final _TopSyncState state = _resolveTopSyncState(controller);
    switch (state) {
      case _TopSyncState.syncing:
        return '同步中';
      case _TopSyncState.success:
        final DateTime? at =
            controller.lastSyncDiagnostics?.finishedAt ?? controller.lastSyncAt;
        if (at == null) {
          return '已同步';
        }
        final DateTime local = at.toLocal();
        final String hh = local.hour.toString().padLeft(2, '0');
        final String mm = local.minute.toString().padLeft(2, '0');
        return '已同步 $hh:$mm';
      case _TopSyncState.error:
        return '同步失败';
      case _TopSyncState.notReady:
        return '未配置';
      case _TopSyncState.idle:
        return '未同步';
    }
  }

  Widget _buildSyncActionButton(AppController controller) {
    final bool syncReady = controller.settings.syncReady;
    return IconButton(
      tooltip: syncReady ? '云同步' : '云同步（请先在设置中完成 WebDAV 配置）',
      onPressed: !syncReady ||
              controller.loading ||
              controller.syncing ||
              controller.backingUp
          ? null
          : () => _syncNow(controller),
      icon: const Icon(Icons.cloud_sync_outlined),
    );
  }

  Future<void> _syncNow(AppController controller) async {
    final bool success = await controller.syncNow(userInitiated: true);
    if (!mounted) return;
    final SyncRunDiagnostics? report = controller.lastSyncDiagnostics;
    if (!success) {
      controller.clearError();
      _showSnack('云同步失败：${_syncErrorText(controller.syncError ?? '')}');
      return;
    }
    _showSnack(_syncSuccessBrief(report));
  }

  Future<void> _triggerStartupAutoSync() async {
    final AppController controller = widget.controller;
    if (!controller.settings.syncReady) {
      return;
    }
    final bool success = await controller.runStartupSyncIfNeeded();
    if (!mounted) return;
    if (!success && controller.syncError != null) {
      _showSnack('自动云同步失败：${_syncErrorText(controller.syncError!)}');
      return;
    }
    if (success) {
      _showSnack(_syncSuccessBrief(controller.lastSyncDiagnostics, auto: true));
    }
  }

  Widget _buildSyncStatusBar(AppController controller) {
    final SyncRunDiagnostics? report = controller.lastSyncDiagnostics;
    Widget child = const SizedBox.shrink();
    String stateKey = 'empty';

    if (controller.syncing) {
      stateKey = 'syncing';
      child = Row(
        children: <Widget>[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('正在同步云端数据...', style: Theme.of(context).textTheme.bodySmall),
          if (report != null) ...<Widget>[
            const Spacer(),
            IconButton(
              tooltip: '查看上次同步详情',
              onPressed: () => _openSyncDiagnostics(controller),
              icon: const Icon(Icons.analytics_outlined, size: 18),
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            ),
          ],
        ],
      );
    } else if (report != null && report.success) {
      stateKey = 'success';
      final DateTime at = report.finishedAt.toLocal();
      final String hh = at.hour.toString().padLeft(2, '0');
      final String mm = at.minute.toString().padLeft(2, '0');
      final String retryText =
          report.retryCount > 0 ? ' · 重试${report.retryCount}' : '';
      child = Row(
        children: <Widget>[
          Icon(
            Icons.cloud_done_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '最近云同步：$hh:$mm · 上传${report.pushedOps} 下载${report.pulledOps}$retryText',
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: '查看同步诊断',
            onPressed: () => _openSyncDiagnostics(controller),
            icon: const Icon(Icons.analytics_outlined, size: 18),
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          ),
        ],
      );
    } else if (controller.syncError != null &&
        controller.settings.syncReady &&
        controller.settings.autoSyncOnChange) {
      stateKey = 'error';
      child = Row(
        children: <Widget>[
          Expanded(
            child: InkWell(
              onTap: () => _syncNow(controller),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '同步失败，点此重试：${_syncErrorText(controller.syncError!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (report != null)
            IconButton(
              tooltip: '查看同步诊断',
              onPressed: () => _openSyncDiagnostics(controller),
              icon: const Icon(Icons.analytics_outlined, size: 18),
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            ),
        ],
      );
    } else if (controller.lastSyncAt != null && controller.settings.syncReady) {
      stateKey = 'legacy-success';
      final DateTime at = controller.lastSyncAt!.toLocal();
      final String hh = at.hour.toString().padLeft(2, '0');
      final String mm = at.minute.toString().padLeft(2, '0');
      child = Row(
        children: <Widget>[
          Icon(
            Icons.cloud_done_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text('最近云同步：$hh:$mm', style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: child is SizedBox
          ? child
          : Padding(
              key: ValueKey<String>(stateKey),
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
              child: child,
            ),
    );
  }

  String _syncErrorText(String raw) {
    final String firstLine = raw
        .split(RegExp(r'[\r\n]+'))
        .first
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (firstLine.isEmpty) {
      return '未知错误';
    }
    if (firstLine.length <= 60) {
      return firstLine;
    }
    return '${firstLine.substring(0, 60)}...';
  }

  String _syncSuccessBrief(SyncRunDiagnostics? report, {bool auto = false}) {
    final String prefix = auto ? '自动云同步完成' : '云同步完成';
    if (report == null) {
      return prefix;
    }
    final String retry =
        report.retryCount > 0 ? '，重试 ${report.retryCount} 次' : '';
    return '$prefix：上传 ${report.pushedOps}，下载 ${report.pulledOps}$retry';
  }

  String _syncApplySummary(SyncRunDiagnostics report) {
    final int changed = report.appliedUpserts + report.appliedDeletes;
    if (changed <= 0) {
      return '本次无本地数据变更（仅完成同步校验）。';
    }
    return '本次已应用 $changed 条变更（更新 ${report.appliedUpserts}，删除 ${report.appliedDeletes}）。';
  }

  Future<void> _openSyncDiagnostics(AppController controller) async {
    final SyncRunDiagnostics? report = controller.lastSyncDiagnostics;
    if (report == null) {
      _showSnack('暂无同步诊断数据');
      return;
    }

    final ThemeData theme = Theme.of(context);
    final String status = report.success ? '成功' : '失败';
    final String? error = report.errorMessage;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '同步诊断',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text('状态：$status'),
                Text(
                  '开始：${_formatDateTime(report.startedAt, includeSeconds: true)}',
                ),
                Text(
                  '结束：${_formatDateTime(report.finishedAt, includeSeconds: true)}',
                ),
                Text('耗时：${_formatDuration(report.duration)}'),
                Text('尝试次数：${report.attemptCount}（重试 ${report.retryCount} 次）'),
                const SizedBox(height: 6),
                Text(_syncApplySummary(report)),
                const SizedBox(height: 10),
                Text('待上传操作：${report.localPendingOps}'),
                Text('实际上传：${report.pushedOps}'),
                Text('下载批次：${report.pulledBatchCount}'),
                Text('下载操作：${report.pulledOps}'),
                Text('应用更新：${report.appliedUpserts}'),
                Text('应用删除：${report.appliedDeletes}'),
                Text('过滤同设备：${report.filteredSelfDeviceOps}'),
                Text('过滤重复操作：${report.filteredDuplicateOps}'),
                Text('过滤过期操作：${report.filteredStaleOps}'),
                if (error != null && error.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text('错误信息', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  SelectableText(error),
                ],
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(
                              text: _syncDiagnosticsPlainText(report),
                            ),
                          );
                          if (!mounted) return;
                          _showSnack('已复制同步诊断');
                        },
                        icon: const Icon(Icons.copy_all_outlined),
                        label: const Text('复制诊断'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('关闭'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration value) {
    if (value.inMilliseconds < 1000) {
      return '${value.inMilliseconds}ms';
    }
    if (value.inSeconds < 60) {
      return '${value.inSeconds}s';
    }
    final int minutes = value.inMinutes;
    final int seconds = value.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  String _syncDiagnosticsPlainText(SyncRunDiagnostics report) {
    final String status = report.success ? '成功' : '失败';
    final StringBuffer buffer = StringBuffer()
      ..writeln('同步诊断')
      ..writeln('状态: $status')
      ..writeln(
        '开始: ${_formatDateTime(report.startedAt, includeSeconds: true)}',
      )
      ..writeln(
        '结束: ${_formatDateTime(report.finishedAt, includeSeconds: true)}',
      )
      ..writeln('耗时: ${_formatDuration(report.duration)}')
      ..writeln('尝试次数: ${report.attemptCount} (重试 ${report.retryCount} 次)')
      ..writeln(_syncApplySummary(report))
      ..writeln('待上传操作: ${report.localPendingOps}')
      ..writeln('实际上传: ${report.pushedOps}')
      ..writeln('下载批次: ${report.pulledBatchCount}')
      ..writeln('下载操作: ${report.pulledOps}')
      ..writeln('应用更新: ${report.appliedUpserts}')
      ..writeln('应用删除: ${report.appliedDeletes}')
      ..writeln('过滤同设备: ${report.filteredSelfDeviceOps}')
      ..writeln('过滤重复操作: ${report.filteredDuplicateOps}')
      ..writeln('过滤过期操作: ${report.filteredStaleOps}');
    final String? error = report.errorMessage;
    if (error != null && error.trim().isNotEmpty) {
      buffer
        ..writeln('错误信息:')
        ..writeln(error.trim());
    }
    return buffer.toString();
  }

  Widget _buildInlineActionButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    Color? tintColor,
  }) {
    final ThemeData theme = Theme.of(context);
    final bool enabled = onPressed != null;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: _GlassTactileButton(
        tooltip: tooltip,
        onPressed: onPressed,
        radius: 11,
        size: const Size.square(38),
        padding: EdgeInsets.zero,
        tintColor: tintColor ?? theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          icon,
          size: 18,
          color: enabled
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    _showSnack('已复制链接');
  }

  Future<void> _deleteBookmarkInline(Bookmark item) async {
    await widget.controller.deleteBookmark(item.id);
    if (!mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('已删除到回收站'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            widget.controller.restoreBookmark(item.id);
          },
        ),
      ),
    );
  }

  Future<void> _clearAllData() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('清空全部数据'),
          content: const Text('将清空收藏、回收站、同步记录和 WebDAV 配置，且无法恢复。是否继续？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认清空'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await widget.controller.clearAllData();
    if (!mounted) return;
    setState(() {
      _showTrash = false;
      _selectionMode = false;
      _selectedIds.clear();
      _urlController.clear();
      _searchController.clear();
    });
    _showSnack('已清空全部数据');
  }

  Future<void> _showTitleIssueActions(Bookmark item, String issue) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('无法自动获取标题'),
                subtitle: Text(issue),
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('重试获取标题'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await widget.controller.refreshTitle(item.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('打开链接手动确认'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _openUrl(item.url);
                },
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('保留网址并隐藏提醒'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await widget.controller.clearBookmarkNote(item.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openUrl(String raw) async {
    final Uri? uri = parseExternalHttpUri(raw);
    if (uri == null) {
      if (mounted) {
        _showSnack('打开失败，请检查链接格式是否正确');
      }
      return;
    }

    try {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        _showSnack('打开失败，请检查链接是否可访问');
      }
    } catch (_) {
      if (mounted) {
        _showSnack('打开失败，请检查链接是否可访问');
      }
    }
  }

  Future<void> _addUrl() async {
    final String input = _urlController.text.trim();
    if (input.isEmpty) return;
    _urlController.clear();
    await widget.controller.addUrl(input);
  }

  Future<void> _refreshStaleTitles() async {
    final int updated = await widget.controller.refreshStaleTitles();
    if (!mounted) return;
    _showSnack('已更新 $updated 条过期标题');
  }

  Future<void> _refreshAllTitles() async {
    final int updated = await widget.controller.refreshAllTitles();
    if (!mounted) return;
    _showSnack('已更新 $updated 条标题');
  }

  Future<void> _refreshSelectedTitles() async {
    final int updated = await widget.controller.refreshTitlesForBookmarks(
      _selectedIds.toList(),
    );
    if (!mounted) return;
    _showSnack('已更新 $updated 条已选标题');
    _clearSelection();
  }

  Future<void> _deleteSelected() async {
    final int affected = await widget.controller.deleteBookmarks(
      _selectedIds.toList(),
    );
    if (!mounted) return;
    _showSnack('已删除 $affected 条到回收站');
    _clearSelection();
  }

  Future<void> _restoreSelected() async {
    final int affected = await widget.controller.restoreBookmarks(
      _selectedIds.toList(),
    );
    if (!mounted) return;
    _showSnack('已恢复 $affected 条收藏');
    _clearSelection();
  }

  Future<void> _deleteSelectedForever() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('批量永久删除'),
          content: const Text('已选项会被永久删除且无法恢复，是否继续？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final int affected = await widget.controller.permanentlyDeleteTrash(
      _selectedIds.toList(),
    );
    if (!mounted) return;
    _showSnack('已永久删除 $affected 条');
    _clearSelection();
  }

  Future<void> _exportSelected(ExportFormat format) async {
    final String? targetPath = await _pickExportPath(
      format: format,
      prefix: _showTrash ? 'bookmarks_trash_selected' : 'bookmarks_selected',
    );
    if (targetPath == null) return;

    final ExportResult? result = await widget.controller.exportSelected(
      bookmarkIds: _selectedIds.toList(),
      fromTrash: _showTrash,
      format: format,
      targetPath: targetPath,
    );
    if (!mounted || result == null) return;
    _showSnack('已导出 ${result.count} 条到 ${result.path}');
    _clearSelection();
  }

  Future<void> _onHomeMenuAction(
    _HomeMenuAction action, {
    required AppController controller,
    required List<Bookmark> trash,
  }) async {
    switch (action) {
      case _HomeMenuAction.emptyTrash:
        if (trash.isEmpty) return;
        await _emptyTrash();
        break;
      case _HomeMenuAction.backupNow:
        await controller.backupNow();
        break;
      case _HomeMenuAction.exportAllJson:
        await _exportAll(ExportFormat.json);
        break;
      case _HomeMenuAction.exportAllCsv:
        await _exportAll(ExportFormat.csv);
        break;
      case _HomeMenuAction.exportAllMd:
        await _exportAll(ExportFormat.md);
        break;
      case _HomeMenuAction.dedupExact:
        await _runDedup(removeExact: true, removeSimilar: false);
        break;
      case _HomeMenuAction.dedupSimilar:
        await _runDedup(removeExact: false, removeSimilar: true);
        break;
      case _HomeMenuAction.dedupAll:
        await _runDedup(removeExact: true, removeSimilar: true);
        break;
      case _HomeMenuAction.slimDown:
        await _runSlimDown();
        break;
      case _HomeMenuAction.changelog:
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => const ChangelogPage(),
          ),
        );
        break;
      case _HomeMenuAction.clearAllData:
        await _clearAllData();
        break;
    }
  }

  Future<void> _exportAll(ExportFormat format) async {
    final String? targetPath = await _pickExportPath(
      format: format,
      prefix: 'bookmarks_all',
    );
    if (targetPath == null) return;

    final ExportResult? result = await widget.controller.exportAll(
      format: format,
      targetPath: targetPath,
      includeTrash: true,
    );
    if (!mounted || result == null) return;
    _showSnack('已导出 ${result.count} 条到 ${result.path}');
  }

  Future<void> _runDedup({
    required bool removeExact,
    required bool removeSimilar,
  }) async {
    final result = await widget.controller.deduplicate(
      removeExact: removeExact,
      removeSimilar: removeSimilar,
    );
    if (!mounted || result == null) return;

    _showSnack(
      '去重完成：重复 ${result.exactRemoved} 条，相似 ${result.similarRemoved} 条，共 ${result.totalRemoved} 条',
    );
  }

  Future<void> _runSlimDown() async {
    final SlimDownResult? result = await widget.controller.slimDown();
    if (!mounted || result == null) return;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('瘦身完成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('清理已推送同步日志: ${result.purgedOutboxRows} 条'),
              Text('清理过期回收站数据: ${result.purgedTrashRows} 条'),
              Text('清理无效数据: ${result.purgedInvalidRows} 条'),
              Text('清理过期删除墓碑: ${result.purgedExpiredTombstoneRows} 条'),
              Text(
                '数据库体积: ${_formatBytes(result.dbBytesBefore)} -> ${_formatBytes(result.dbBytesAfter)}',
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _emptyTrash() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('清空回收站'),
          content: const Text('清空后无法恢复，是否继续？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final int deleted = await widget.controller.emptyTrash();
    if (!mounted) return;
    _showSnack('已永久删除 $deleted 条收藏');
  }

  Future<String?> _pickExportPath({
    required ExportFormat format,
    required String prefix,
  }) async {
    final fileDialog = PlatformServices.instance.fileDialog;
    final String ext = _extensionForExportFormat(format);
    final String defaultName =
        '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    try {
      final String? savePath = await fileDialog.saveFile(
        dialogTitle: '选择导出文件位置',
        fileName: defaultName,
      );
      if (savePath == null || savePath.trim().isEmpty) {
        // 用户在保存对话框里取消时，直接结束，不再二次弹窗。
        return null;
      }
      return _ensureExt(savePath, ext);
    } catch (_) {
      // 某些平台不支持保存对话框，回退到目录选择。
    }

    final String? dir = await fileDialog.pickDirectory(
      dialogTitle: '选择导出目录',
    );
    if (dir == null || dir.trim().isEmpty) {
      return null;
    }
    return p.join(dir, defaultName);
  }

  String _ensureExt(String path, String ext) {
    final String lower = path.toLowerCase();
    final String suffix = '.$ext';
    if (lower.endsWith(suffix)) return path;
    return '$path$suffix';
  }

  String _extensionForExportFormat(ExportFormat format) {
    switch (format) {
      case ExportFormat.json:
        return 'json';
      case ExportFormat.csv:
        return 'csv';
      case ExportFormat.md:
        return 'md';
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    final double kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)}KB';
    final double mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)}MB';
    final double gb = mb / 1024;
    return '${gb.toStringAsFixed(2)}GB';
  }

  String _formatDateTime(DateTime value, {bool includeSeconds = false}) {
    final DateTime local = value.toLocal();
    final String yyyy = local.year.toString().padLeft(4, '0');
    final String mm = local.month.toString().padLeft(2, '0');
    final String dd = local.day.toString().padLeft(2, '0');
    final String hh = local.hour.toString().padLeft(2, '0');
    final String min = local.minute.toString().padLeft(2, '0');
    if (!includeSeconds) {
      return '$yyyy-$mm-$dd $hh:$min';
    }
    final String ss = local.second.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd $hh:$min:$ss';
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _GlassTactileButton extends StatefulWidget {
  const _GlassTactileButton({
    required this.child,
    required this.onPressed,
    this.tooltip,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.radius = 14,
    this.tintColor,
    this.visualEnabled,
    this.singleLayer = false,
    this.size,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tintColor;
  final bool? visualEnabled;
  final bool singleLayer;
  final Size? size;

  @override
  State<_GlassTactileButton> createState() => _GlassTactileButtonState();
}

class _GlassTactileButtonState extends State<_GlassTactileButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final bool visualEnabled = widget.visualEnabled ?? widget.onPressed != null;
    final Color tint =
        widget.tintColor ?? theme.colorScheme.surfaceContainerHighest;
    final Color topColor = Color.alphaBlend(
      Colors.white.withValues(alpha: isDark ? 0.14 : 0.3),
      tint,
    ).withValues(alpha: visualEnabled ? (isDark ? 0.78 : 0.88) : 0.54);
    final Color bottomColor = Color.alphaBlend(
      Colors.black.withValues(alpha: isDark ? 0.24 : 0.12),
      tint,
    ).withValues(alpha: visualEnabled ? (isDark ? 0.62 : 0.74) : 0.5);
    final Color flatTopColor = Color.alphaBlend(
      Colors.white.withValues(alpha: isDark ? 0.06 : 0.2),
      tint,
    ).withValues(alpha: visualEnabled ? (isDark ? 0.86 : 0.92) : 0.58);
    final Color flatBottomColor = Color.alphaBlend(
      Colors.black.withValues(alpha: isDark ? 0.1 : 0.05),
      tint,
    ).withValues(alpha: visualEnabled ? (isDark ? 0.82 : 0.9) : 0.55);
    final BorderRadius borderRadius = BorderRadius.circular(widget.radius);
    final BoxConstraints? constraints = widget.size == null
        ? null
        : BoxConstraints.tightFor(
            width: widget.size!.width,
            height: widget.size!.height,
          );

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, _pressed ? 1.6 : 0, 0),
      constraints: constraints,
      padding: widget.padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: widget.singleLayer ? Alignment.topCenter : Alignment.topLeft,
          end: widget.singleLayer
              ? Alignment.bottomCenter
              : Alignment.bottomRight,
          colors: widget.singleLayer
              ? <Color>[flatTopColor, flatBottomColor]
              : <Color>[topColor, bottomColor],
        ),
        border: Border.all(
          color: widget.singleLayer
              ? theme.colorScheme.outlineVariant.withValues(
                  alpha: visualEnabled ? (isDark ? 0.5 : 0.75) : 0.32,
                )
              : Colors.white.withValues(
                  alpha: visualEnabled ? (isDark ? 0.2 : 0.54) : 0.24,
                ),
        ),
        boxShadow: <BoxShadow>[
          if (!widget.singleLayer)
            BoxShadow(
              color: Colors.white.withValues(
                alpha: visualEnabled ? (isDark ? 0.07 : 0.34) : 0.08,
              ),
              blurRadius: _pressed ? 4 : 9,
              offset: const Offset(-1.5, -1.5),
            ),
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(
              alpha: visualEnabled
                  ? (widget.singleLayer
                      ? (isDark ? 0.24 : 0.14)
                      : (isDark ? 0.44 : 0.2))
                  : 0.12,
            ),
            blurRadius:
                widget.singleLayer ? (_pressed ? 6 : 12) : (_pressed ? 8 : 16),
            offset: Offset(
              0,
              widget.singleLayer ? (_pressed ? 2.5 : 5) : (_pressed ? 3.5 : 8),
            ),
          ),
        ],
      ),
      child: widget.singleLayer
          ? Center(child: widget.child)
          : ClipRRect(
              borderRadius: borderRadius,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            stops: const <double>[0, 0.55, 1],
                            colors: <Color>[
                              Colors.white.withValues(
                                alpha: isDark ? 0.18 : 0.38,
                              ),
                              Colors.transparent,
                              Colors.black.withValues(
                                alpha: isDark ? 0.2 : 0.09,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _GlassTexturePainter(
                          color:
                              (isDark ? Colors.white : Colors.black).withValues(
                            alpha:
                                visualEnabled ? (isDark ? 0.05 : 0.03) : 0.02,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(child: widget.child),
                ],
              ),
            ),
    );

    content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: borderRadius,
        onHighlightChanged: (bool pressed) {
          if (_pressed == pressed) return;
          setState(() {
            _pressed = pressed;
          });
        },
        child: content,
      ),
    );

    final String? tooltip = widget.tooltip;
    if (tooltip != null && tooltip.isNotEmpty) {
      return Tooltip(message: tooltip, child: content);
    }
    return content;
  }
}

class _GlassTexturePainter extends CustomPainter {
  const _GlassTexturePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final Paint paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.8;
    const double stepX = 11;
    const double stepY = 8;
    for (double y = 3; y < size.height; y += stepY) {
      final bool shifted = ((y / stepY).floor() % 2 == 0);
      final double startX = shifted ? 4 : 8;
      for (double x = startX; x < size.width; x += stepX) {
        final double length = ((x + y).round() % 3 == 0) ? 1.7 : 1.2;
        canvas.drawLine(Offset(x, y), Offset(x + length, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GlassTexturePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
