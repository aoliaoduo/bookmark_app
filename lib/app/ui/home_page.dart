import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../core/domain/bookmark.dart';
import '../app_controller.dart';
import '../export/export_service.dart';
import '../maintenance/maintenance_service.dart';
import '../settings/app_settings.dart';
import 'about_page.dart';
import 'changelog_page.dart';
import 'settings_page.dart';

enum _HomeMenuAction {
  exportAllJson,
  exportAllCsv,
  dedupExact,
  dedupSimilar,
  dedupAll,
  slimDown,
  changelog,
}

enum _SelectionMenuAction { exportSelectedJson, exportSelectedCsv }

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
  bool _searchExpanded = false;
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

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

        final List<Bookmark> bookmarks = _applySearch(allBookmarks);
        final List<Bookmark> trash = _applySearch(allTrash);
        final List<Bookmark> currentItems = _showTrash ? trash : bookmarks;

        _pruneSelection(allBookmarks, allTrash);

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _selectionMode
                  ? '已选择 ${_selectedIds.length} 条'
                  : (_showTrash ? '回收站' : '网址收藏'),
            ),
            actions: _selectionMode
                ? _buildSelectionActions(controller, currentItems)
                : _buildNormalActions(controller, trash, currentItems),
          ),
          body: Column(
            children: <Widget>[
              if (!_showTrash)
                _buildInputArea(controller)
              else
                _buildTrashHint(),
              if (_searchExpanded || _searchController.text.isNotEmpty)
                _buildSearchArea(),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: <Widget>[
                    Text(
                      _showTrash
                          ? '回收站模式'
                          : '自动更新周期: 每 ${controller.settings.titleRefreshDays} 天',
                    ),
                    const Spacer(),
                    Text('收藏 ${allBookmarks.length} / 回收站 ${allTrash.length}'),
                  ],
                ),
              ),
              Expanded(
                child: _showTrash
                    ? _buildTrashList(trash)
                    : _buildBookmarkList(bookmarks),
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
    List<Bookmark> currentItems,
  ) {
    final List<Widget> actions = <Widget>[
      IconButton(
        tooltip: _searchExpanded ? '收起搜索' : '搜索',
        onPressed: _toggleSearch,
        icon: Icon(_searchExpanded ? Icons.search_off : Icons.search),
      ),
      IconButton(
        tooltip: _showTrash ? '返回收藏' : '查看回收站',
        onPressed: () => _toggleTrashMode(!_showTrash),
        icon: Icon(_showTrash ? Icons.home_outlined : Icons.delete_outline),
      ),
      IconButton(
        tooltip: '批量操作',
        onPressed: () => _enterSelectionMode(currentItems),
        icon: const Icon(Icons.checklist),
      ),
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
      IconButton(
        tooltip: '清空回收站',
        onPressed: controller.loading || trash.isEmpty ? null : _emptyTrash,
        icon: const Icon(Icons.delete_sweep),
      ),
      IconButton(
        tooltip: '云同步',
        onPressed: controller.loading ? null : controller.syncNow,
        icon: const Icon(Icons.sync),
      ),
      IconButton(
        tooltip: '云备份',
        onPressed: controller.loading ? null : controller.backupNow,
        icon: const Icon(Icons.backup),
      ),
      PopupMenuButton<_HomeMenuAction>(
        tooltip: '更多功能',
        onSelected: (_HomeMenuAction action) => _onHomeMenuAction(action),
        itemBuilder: (BuildContext context) =>
            <PopupMenuEntry<_HomeMenuAction>>[
          const PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.exportAllJson,
            child: Text('导出全部(JSON)'),
          ),
          const PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.exportAllCsv,
            child: Text('导出全部(CSV)'),
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
        ],
      ),
      IconButton(
        tooltip: '关于',
        onPressed: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => const AboutPage(),
            ),
          );
        },
        icon: const Icon(Icons.info_outline),
      ),
      IconButton(
        tooltip: '设置',
        onPressed: controller.loading
            ? null
            : () async {
                final AppSettings current = controller.settings;
                final AppSettings? next =
                    await Navigator.of(context).push<AppSettings>(
                  MaterialPageRoute<AppSettings>(
                    builder: (BuildContext context) =>
                        SettingsPage(settings: current),
                  ),
                );
                if (next != null) {
                  await controller.saveSettings(next);
                }
              },
        icon: const Icon(Icons.settings),
      ),
    ]);

    return actions;
  }

  List<Widget> _buildSelectionActions(
    AppController controller,
    List<Bookmark> currentTabItems,
  ) {
    final bool hasSelection = _selectedIds.isNotEmpty;
    final bool allSelected = currentTabItems.isNotEmpty &&
        currentTabItems
            .every((Bookmark item) => _selectedIds.contains(item.id));
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
        onSelected: (_SelectionMenuAction action) {
          if (action == _SelectionMenuAction.exportSelectedJson) {
            _exportSelected(ExportFormat.json);
          } else {
            _exportSelected(ExportFormat.csv);
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
        ],
      ),
    );

    return actions;
  }

  Widget _buildInputArea(AppController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _urlController,
              enabled: !controller.loading,
              decoration: const InputDecoration(
                hintText: '输入网址，例如 https://example.com',
              ),
              onSubmitted: (_) => _addUrl(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: controller.loading ? null : _addUrl,
            icon: const Icon(Icons.add_link),
            label: const Text('收藏'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 10),
            Icon(
              Icons.search,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '搜索标题或网址',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              IconButton(
                tooltip: '清空搜索',
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.clear, size: 18),
              ),
            IconButton(
              tooltip: '收起搜索',
              onPressed: () {
                setState(() {
                  _searchExpanded = false;
                });
              },
              icon: const Icon(Icons.expand_less, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrashHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '当前查看回收站，可恢复或永久删除条目',
          style: Theme.of(context).textTheme.bodySmall,
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
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: _selectionMode
                ? Checkbox(
                    value: _selectedIds.contains(item.id),
                    onChanged: (_) => _toggleSelected(item.id),
                  )
                : null,
            title: Text(
              item.title?.trim().isNotEmpty == true ? item.title! : '(未获取标题)',
            ),
            subtitle: Text(item.url),
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
                : SizedBox(
                    width: 128,
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          tooltip: '打开网址',
                          onPressed: () => _openUrl(item.url),
                          icon: const Icon(Icons.open_in_new),
                        ),
                        IconButton(
                          tooltip: '更新标题',
                          onPressed: controller.loading
                              ? null
                              : () => controller.refreshTitle(item.id),
                          icon: const Icon(Icons.refresh),
                        ),
                        IconButton(
                          tooltip: '删除到回收站',
                          onPressed: controller.loading
                              ? null
                              : () => controller.deleteBookmark(item.id),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
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
        final String deletedAt = item.deletedAt?.toLocal().toString() ?? '-';
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: _selectionMode
                ? Checkbox(
                    value: _selectedIds.contains(item.id),
                    onChanged: (_) => _toggleSelected(item.id),
                  )
                : null,
            title: Text(
              item.title?.trim().isNotEmpty == true ? item.title! : item.url,
            ),
            subtitle: Text('删除时间: $deletedAt'),
            onTap: () {
              if (_selectionMode) {
                _toggleSelected(item.id);
              }
            },
            onLongPress: () => _startSelection(item.id),
            trailing: _selectionMode
                ? null
                : IconButton(
                    tooltip: '恢复',
                    onPressed: controller.loading
                        ? null
                        : () => controller.restoreBookmark(item.id),
                    icon: const Icon(Icons.restore_from_trash),
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

  void _pruneSelection(List<Bookmark> bookmarks, List<Bookmark> trash) {
    final Set<String> valid = <String>{
      ...bookmarks.map((Bookmark b) => b.id),
      ...trash.map((Bookmark b) => b.id),
    };
    _selectedIds.removeWhere((String id) => !valid.contains(id));
  }

  void _toggleSearch() {
    setState(() {
      _searchExpanded = !_searchExpanded;
      if (!_searchExpanded && _searchController.text.isEmpty) {
        _searchController.clear();
      }
    });
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

  Future<void> _openUrl(String raw) async {
    final Uri uri = Uri.parse(raw);
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _showSnack('打开失败，请检查链接是否可访问');
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
    final int affected =
        await widget.controller.deleteBookmarks(_selectedIds.toList());
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

  Future<void> _onHomeMenuAction(_HomeMenuAction action) async {
    switch (action) {
      case _HomeMenuAction.exportAllJson:
        await _exportAll(ExportFormat.json);
        break;
      case _HomeMenuAction.exportAllCsv:
        await _exportAll(ExportFormat.csv);
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
    final String ext = format == ExportFormat.json ? 'json' : 'csv';
    final String defaultName =
        '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    try {
      final String? savePath = await FilePicker.platform.saveFile(
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

    final String? dir = await FilePicker.platform.getDirectoryPath(
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    final double kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)}KB';
    final double mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)}MB';
    final double gb = mb / 1024;
    return '${gb.toStringAsFixed(2)}GB';
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
