import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';

/// OAuth 授权弹窗的关闭时机：打开/复制后必须保持打开，只有用户确认完成才关闭。
void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required Future<void> Function(BuildContext) onOpen,
    required Future<void> Function(BuildContext) onCopy,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed:
                        () => showExternalOAuthAuthorizeDialog(
                          context,
                          l10n: AppLocalizations.of(context),
                          url: 'https://example.com/oauth',
                          onOpen: onOpen,
                          onCopy: onCopy,
                        ),
                    child: const Text('open-dialog'),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open-dialog'));
    await tester.pumpAndSettle();
  }

  testWidgets('打开与复制链接不会关闭授权弹窗', (tester) async {
    var opened = 0;
    var copied = 0;
    await pumpDialog(
      tester,
      onOpen: (_) async {
        opened++;
      },
      onCopy: (_) async {
        copied++;
      },
    );

    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('复制链接'));
    await tester.pumpAndSettle();
    expect(copied, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('我已完成授权关闭弹窗', (tester) async {
    await pumpDialog(tester, onOpen: (_) async {}, onCopy: (_) async {});

    await tester.tap(find.text('我已完成授权'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('取消关闭弹窗且不触发打开或复制', (tester) async {
    var opened = 0;
    var copied = 0;
    await pumpDialog(
      tester,
      onOpen: (_) async {
        opened++;
      },
      onCopy: (_) async {
        copied++;
      },
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(opened, 0);
    expect(copied, 0);
  });
}
