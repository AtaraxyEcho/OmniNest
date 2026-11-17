import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/widgets/app_dropdown.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_metadata_edit_page.dart';

ReaderItemDetail _detail({
  String author = '托尔斯泰',
  String? isbn,
  DateTime? releaseDate,
  List<String>? genres,
  String? serialStatus,
}) {
  return ReaderItemDetail(
    item: ReaderItem(
      id: 'item-1',
      title: '战争与和平',
      itemType: 'EPUB',
      authorName: author,
      updatedAt: null,
      isbn: isbn,
      releaseDate: releaseDate,
      genres: genres,
      serialStatus: serialStatus,
    ),
  );
}

Future<void> _pumpPage(WidgetTester tester, ReaderItemDetail detail) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        readerItemDetailProvider.overrideWith((ref, itemId) async => detail),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: OmniNestTheme.dark(),
        home: const ReaderMetadataEditPage(itemId: 'item-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, String label) {
  return tester
      .widget<TextFormField>(find.widgetWithText(TextFormField, label))
      .controller!
      .text;
}

/// 元数据编辑页：表单只在首次拿到详情时回填一次。
void main() {
  testWidgets('详情字段回填到表单', (tester) async {
    await _pumpPage(
      tester,
      _detail(
        isbn: '978-0-00-000000-0',
        releaseDate: DateTime(2024, 5, 6),
        genres: const ['科幻', '长篇'],
        serialStatus: 'COMPLETED',
      ),
    );

    expect(_fieldText(tester, '作者'), '托尔斯泰');
    expect(_fieldText(tester, 'ISBN'), '978-0-00-000000-0');
    expect(_fieldText(tester, '发行日期'), '2024-05-06');
    expect(_fieldText(tester, '类型标签（逗号分隔）'), '科幻, 长篇');
    expect(find.text('已完结'), findsOneWidget);
  });

  testWidgets('清空字段后重绘不回弹旧值', (tester) async {
    await _pumpPage(tester, _detail());
    expect(_fieldText(tester, '作者'), '托尔斯泰');

    await tester.enterText(find.widgetWithText(TextFormField, '作者'), '');
    // 切换连载状态触发 setState：以前 build 里无条件回填会把旧作者名顶回来。
    await tester.tap(find.byType(AppDropdown<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已完结'));
    await tester.pumpAndSettle();

    expect(_fieldText(tester, '作者'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
