import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../core/domain/bookmark.dart';
import '../../core/metadata/title_fetch_note.dart';
import '../app_controller.dart';
import '../export/export_service.dart';
import '../maintenance/maintenance_service.dart';
import '../settings/app_settings.dart';
import 'about_page.dart';
import 'changelog_page.dart';
import 'settings_page.dart';

enum _HomeMenuAction {
  emptyTrash,
  backupNow,
  exportAllJson,
  exportAllCsv,
  dedupExact,
  dedupSimilar,
  dedupAll,
  slimDown,
  changelog,
  clearAllData,
}

enum _SelectionMenuAction { exportSelectedJson, exportSelectedCsv }

enum _CompactHomeAction {
  refreshAllTitles,
  refreshStaleTitles,
  emptyTrash,
  backupNow,
  exportAllJson,
  exportAllCsv,
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
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
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

        final List<Bookmark> bookmarks = _applySearch(allBookmarks);
        final List<Bookmark> trash = _applySearch(allTrash);
        final List<Bookmark> currentItems = _showTrash ? trash : bookmarks;
        final bool compactActions = _useCompactActionsLayout(context);

        _pruneSelection(allBookmarks, allTrash);

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _selectionMode
                  ? '已选择 ${_selectedIds.length} 条'
                  : (_showTrash ? '回收站' : '粮仓'),
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
          body: Column(
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
    List<Bookmark> currentItems, {
    required bool compactActions,
  }) {
    if (compactActions) {
      return <Widget>[
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
              enabled: !controller.loading,
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
        tooltip: _showTrash ? '返回收藏' : '查看回收站',
        onPressed: () => _toggleTrashMode(!_showTrash),
        icon: Icon(_showTrash ? Icons.home_outlined : Icons.delete_outline),
      ),
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
        onSelected: (_HomeMenuAction action) => _onHomeMenuAction(
          action,
          controller: controller,
          trash: trash,
        ),
        itemBuilder: (BuildContext context) =>
            <PopupMenuEntry<_HomeMenuAction>>[
          PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.emptyTrash,
            enabled: !controller.loading && trash.isNotEmpty,
            child: const Text('清空回收站'),
          ),
          PopupMenuItem<_HomeMenuAction>(
            value: _HomeMenuAction.backupNow,
            enabled: !controller.loading,
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
        currentTabItems
            .every((Bookmark item) => _selectedIds.contains(item.id));

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
            _onCompactSelectionAction(
              action,
              currentTabItems: currentTabItems,
            );
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
                hintText: '输入网址',
              ),
              onSubmitted: (_) => _addUrl(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(104, 56),
              ),
              onPressed: controller.loading ? null : _addUrl,
              icon: const Icon(Icons.add_link),
              label: const Text('收藏'),
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
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.24 : 0.08,
              ),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
          color: theme.colorScheme.surface.withValues(alpha: 0.9),
        ),
        padding: const EdgeInsets.only(left: 10),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.search,
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
        final String? issue = parseTitleFetchFailureNote(item.note);
        final String titleText = item.title?.trim().isNotEmpty == true
            ? item.title!
            : (issue == null ? '(未获取标题)' : '(标题抓取失败)');
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: _selectionMode
                ? Checkbox(
                    value: _selectedIds.contains(item.id),
                    onChanged: (_) => _toggleSelected(item.id),
                  )
                : null,
            title: Text(titleText),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(item.url),
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
                        color: Theme.of(context)
                            .colorScheme
                            .errorContainer
                            .withValues(alpha: 0.72),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '标题获取失败：$issue',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                          Text(
                            '处理',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            isThreeLine: issue != null,
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

  Widget _buildSyncActionButton(AppController controller) {
    final bool syncReady = controller.settings.syncReady;
    return IconButton(
      tooltip: syncReady ? '云同步' : '云同步（请先在设置中完成 WebDAV 配置）',
      onPressed: !syncReady || controller.loading || controller.syncing
          ? null
          : () => _syncNow(controller),
      icon: const Icon(Icons.cloud_sync_outlined),
    );
  }

  Future<void> _syncNow(AppController controller) async {
    final bool success = await controller.syncNow(userInitiated: true);
    if (!mounted) return;
    if (!success) {
      controller.clearError();
      _showSnack('云同步失败：${_syncErrorText(controller.syncError ?? '')}');
      return;
    }
    _showSnack('云同步完成');
  }

  Future<void> _triggerStartupAutoSync() async {
    final AppController controller = widget.controller;
    if (!controller.settings.syncReady ||
        !controller.settings.autoSyncOnLaunch) {
      return;
    }
    final bool success = await controller.runStartupSyncIfNeeded();
    if (!mounted) return;
    if (!success && controller.syncError != null) {
      _showSnack('自动云同步失败：${_syncErrorText(controller.syncError!)}');
      return;
    }
    if (success) {
      _showSnack('自动云同步完成');
    }
  }

  Widget _buildSyncStatusBar(AppController controller) {
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
          Text(
            '正在同步云端数据...',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    } else if (controller.syncError != null &&
        controller.settings.syncReady &&
        controller.settings.autoSyncOnChange) {
      stateKey = 'error';
      child = InkWell(
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
      );
    } else if (controller.lastSyncAt != null && controller.settings.syncReady) {
      stateKey = 'success';
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
          Text(
            '最近云同步：$hh:$mm',
            style: Theme.of(context).textTheme.bodySmall,
          ),
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

  Widget _buildInlineActionButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      splashRadius: 18,
      icon: Icon(icon, size: 21),
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
          content: const Text(
            '将清空收藏、回收站、同步记录和 WebDAV 配置，且无法恢复。是否继续？',
          ),
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
