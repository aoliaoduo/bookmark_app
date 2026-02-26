import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:code/app/app_shell.dart';
import 'package:code/app/router.dart';

void main() {
  testWidgets('App shell opens drawer', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AppShell(initialEntry: PrimaryEntry.focus),
        ),
      ),
    );

    expect(find.text('专注'), findsWidgets);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.text('导航'), findsOneWidget);
    expect(find.text('资料库'), findsOneWidget);
    expect(find.text('专注'), findsWidgets);
  });
}
