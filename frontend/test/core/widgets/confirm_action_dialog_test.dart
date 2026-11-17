import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/confirm_action_dialog.dart';

void main() {
  testWidgets(
    'confirmDestructiveAction only resolves true after confirmation',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () async {
                    result = await confirmDestructiveAction(
                      context,
                      title: '删除文件？',
                      message: '删除后会移入回收站。',
                      confirmLabel: '删除',
                    );
                  },
                  child: const Text('open'),
                ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    },
  );
}
