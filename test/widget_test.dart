import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:code/app/app_shell.dart';
import 'package:code/app/router.dart';
import 'package:code/core/i18n/app_strings.dart';

void main() {
  testWidgets('App shell opens drawer', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AppShell(initialEntry: PrimaryEntry.focus)),
      ),
    );

    expect(find.text(AppStrings.focus), findsWidgets);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.navTitle), findsOneWidget);
    expect(find.text(AppStrings.library), findsOneWidget);
    expect(find.text(AppStrings.focus), findsWidgets);
  });
}
