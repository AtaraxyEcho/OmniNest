import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/comic_detail_page.dart';

const _comic = ReaderItem(
  id: 'comic-1',
  title: 'Sample Comic',
  itemType: 'CBZ',
  contentKind: 'COMIC',
  updatedAt: null,
);

List<ComicCatalogNode> _catalogFixture() => [
  const ComicCatalogNode(id: 'root', nodeType: 'ROOT', title: 'Root'),
  const ComicCatalogNode(
    id: 's1',
    nodeType: 'SEASON',
    title: 'Season 1',
    parentId: 'root',
  ),
  for (var i = 0; i < 300; i++)
    ComicCatalogNode(
      id: 'c$i',
      nodeType: 'CHAPTER',
      title: 'Chapter $i',
      parentId: 's1',
      sortOrder: i,
    ),
];

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: OmniNestTheme.light(),
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: RefreshIndicator(
                strokeWidth: 2.5,
                onRefresh: () async {},
                child: child,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _pumpDetail(WidgetTester tester) async {
  await tester.pumpWidget(
    _wrap(
      ComicDetailPage(item: _comic, chapters: _catalogFixture(), canRead: true),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('语义树启用下目录交互不触发 parentDataDirty 断言', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpDetail(tester);

    await tester.tap(find.text('Table of Contents'));
    await tester.pumpAndSettle();

    // 快速滚动往复：触发 sliver 行回收与新行挂载。
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -600),
      1000,
    );
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 600),
      1000,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.unfold_less_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.unfold_more_rounded));
    await tester.pumpAndSettle();

    // 过滚动触发 RefreshIndicator。
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 150));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('清单占位切换为详情页不触发语义断言', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(const Center(child: CircularProgressIndicator())),
    );
    await tester.pump();
    await tester.pumpWidget(
      _wrap(
        ComicDetailPage(
          item: _comic,
          chapters: _catalogFixture(),
          canRead: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
