import 'package:flutter/material.dart';

import '../../core/i18n/app_strings.dart';
import 'data/library_repository.dart';

typedef PageLoader<T> = Future<PagedResult<T>> Function(int page, int pageSize);
typedef ItemBuilder<T> = Widget Function(BuildContext context, T item);

class LibraryTabView<T> extends StatefulWidget {
  const LibraryTabView({
    super.key,
    required this.pageLoader,
    required this.itemBuilder,
    required this.emptyText,
    this.onItemsSnapshot,
    this.pageSize = LibraryRepository.defaultPageSize,
  });

  final PageLoader<T> pageLoader;
  final ItemBuilder<T> itemBuilder;
  final String emptyText;
  final ValueChanged<List<T>>? onItemsSnapshot;
  final int pageSize;

  @override
  State<LibraryTabView<T>> createState() => LibraryTabViewState<T>();
}

class LibraryTabViewState<T> extends State<LibraryTabView<T>>
    with AutomaticKeepAliveClientMixin<LibraryTabView<T>> {
  final ScrollController _scrollController = ScrollController();
  final List<T> _items = <T>[];

  bool _isLoading = false;
  bool _hasMore = true;
  bool _isInitialLoadDone = false;
  bool _isVisible = false;
  int _page = 0;
  int _animatedRangeStart = -1;
  int _animatedRangeLength = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadNextPage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isVisible = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_isInitialLoadDone && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return Center(child: Text(widget.emptyText));
    }

    return AnimatedOpacity(
      opacity: _isVisible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: ListView.builder(
        key: PageStorageKey<String>('${widget.key}_list'),
        controller: _scrollController,
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (index >= _items.length) {
            return const _LoadingRow();
          }

          final Widget content = widget.itemBuilder(context, _items[index]);
          if (_inAnimatedRange(index)) {
            return _InsertFadeSize(
              delay: Duration(
                milliseconds: ((index - _animatedRangeStart).clamp(0, 6)) * 20,
              ),
              child: content,
            );
          }
          return content;
        },
      ),
    );
  }

  Future<void> reload() async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _isInitialLoadDone = false;
      _animatedRangeStart = -1;
      _animatedRangeLength = 0;
    });
    widget.onItemsSnapshot?.call(<T>[]);
    await _loadNextPage();
  }

  void patchItem({
    required bool Function(T item) match,
    required T Function(T item) update,
  }) {
    final int index = _items.indexWhere(match);
    if (index < 0) {
      return;
    }

    setState(() {
      _items[index] = update(_items[index]);
    });
    widget.onItemsSnapshot?.call(List<T>.unmodifiable(_items));
  }

  void removeWhere(bool Function(T item) match) {
    final int before = _items.length;
    setState(() {
      _items.removeWhere(match);
    });
    if (_items.length != before) {
      widget.onItemsSnapshot?.call(List<T>.unmodifiable(_items));
    }
  }

  void _onScroll() {
    if (!_hasMore || _isLoading) {
      return;
    }

    final double remaining =
        _scrollController.position.maxScrollExtent - _scrollController.offset;

    if (remaining <= 240) {
      _loadNextPage();
    }
  }

  bool _inAnimatedRange(int index) {
    if (_animatedRangeStart < 0 || _animatedRangeLength <= 0) {
      return false;
    }
    return index >= _animatedRangeStart &&
        index < _animatedRangeStart + _animatedRangeLength;
  }

  Future<void> _loadNextPage() async {
    if (_isLoading || !_hasMore) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final PagedResult<T> result = await widget.pageLoader(
      _page,
      widget.pageSize,
    );

    if (!mounted) {
      return;
    }

    final int start = _items.length;
    setState(() {
      _items.addAll(result.items);
      _hasMore = result.hasMore;
      _page += 1;
      _isLoading = false;
      _isInitialLoadDone = true;
      _animatedRangeStart = start;
      _animatedRangeLength = result.items.length;
    });
    widget.onItemsSnapshot?.call(List<T>.unmodifiable(_items));

    if (result.items.isNotEmpty) {
      Future<void>.delayed(const Duration(milliseconds: 260), () {
        if (!mounted) {
          return;
        }
        setState(() {
          _animatedRangeStart = -1;
          _animatedRangeLength = 0;
        });
      });
    }
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('library_loading_row'),
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(AppStrings.loadingMore),
          ],
        ),
      ),
    );
  }
}

class _InsertFadeSize extends StatefulWidget {
  const _InsertFadeSize({required this.child, required this.delay});

  final Widget child;
  final Duration delay;

  @override
  State<_InsertFadeSize> createState() => _InsertFadeSizeState();
}

class _InsertFadeSizeState extends State<_InsertFadeSize> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) {
        setState(() {
          _visible = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: _visible ? widget.child : const SizedBox.shrink(),
      ),
    );
  }
}
