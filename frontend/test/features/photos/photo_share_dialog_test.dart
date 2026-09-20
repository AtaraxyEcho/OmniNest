import 'package:flutter/material.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_share_dialog.dart';

PhotoShareLink _link({required String id, DateTime? expiresAt}) {
  return PhotoShareLink(
    id: id,
    token: '',
    resourceType: 'PHOTO_ITEM',
    resourceId: 'res-1',
    accessCount: 2,
    createdAt: DateTime(2026, 9, 19),
    expiresAt: expiresAt,
  );
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required List<PhotoShareLink> shares,
  required Future<void> Function(String shareId) onRevoke,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder:
            (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  showPhotoShareDialog(
                    context,
                    title: '分享',
                    shares: shares,
                    onRevoke: onRevoke,
                  );
                },
                child: const Text('open'),
              ),
            ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('删除成功后就地移除该行且不关闭对话框', (tester) async {
    final revoked = <String>[];
    await _pumpDialog(
      tester,
      shares: [_link(id: 'share-1'), _link(id: 'share-2')],
      onRevoke: (id) async => revoked.add(id),
    );

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();

    expect(revoked, ['share-1']);
    // 对话框保持打开：仍能看到另一条链接与取消按钮。
    expect(find.text('取消'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('删除失败时提示错误并保留该行', (tester) async {
    await _pumpDialog(
      tester,
      shares: [_link(id: 'share-1')],
      onRevoke:
          (id) async =>
              throw const AppException(code: '404', message: '分享链接不存在'),
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    // 行保留、对话框不关、错误内联可见。
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    // 无 l10n 环境下内联错误展示稳定错误码。
    expect(find.textContaining('404'), findsOneWidget);
  });

  testWidgets('链接行以有效期状态标识而非空令牌', (tester) async {
    await _pumpDialog(
      tester,
      shares: [
        _link(id: 'share-1'),
        _link(id: 'share-exp', expiresAt: DateTime(2020, 1, 1)),
      ],
      onRevoke: (id) async {},
    );

    expect(find.text('永久有效'), findsOneWidget);
    expect(find.text('已过期'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
  });

  testWidgets('密码留空返回空字符串以显式创建无密码链接', (tester) async {
    (String, String)? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder:
                (context) => Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await showPhotoShareDialog(
                        context,
                        title: '分享',
                        shares: const [],
                        onRevoke: (id) async {},
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('创建链接'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.$1, '');
    expect(result!.$2, 'never');
  });
}
