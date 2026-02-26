import 'package:code/core/db/app_database.dart';
import 'package:code/features/library/data/library_repository.dart';
import 'package:code/features/library/library_tab_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LibraryTabView loads next page when scrolled to bottom', (
    WidgetTester tester,
  ) async {
    final List<TodoListItem> all = List<TodoListItem>.generate(
      80,
      (int i) => TodoListItem(
        id: 'id_$i',
        title: 'Todo #$i',
        priority: i % 3,
        status: TodoStatusCode.open,
      ),
    );

    Future<PagedResult<TodoListItem>> pageLoader(int page, int pageSize) async {
      if (page > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 160));
      }
      final int start = page * pageSize;
      final int end = (start + pageSize).clamp(0, all.length);
      final List<TodoListItem> slice = all.sublist(start, end);
      return PagedResult<TodoListItem>(
        items: slice,
        hasMore: slice.length == pageSize,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: LibraryTabView<TodoListItem>(
              pageLoader: pageLoader,
              pageSize: 50,
              emptyText: 'empty',
              itemBuilder: (BuildContext context, TodoListItem item) {
                return ListTile(title: Text(item.title));
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));

    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('library_loading_row')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('library_loading_row')), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Todo #79'),
      120,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Todo #79'), findsWidgets);
  });
}
