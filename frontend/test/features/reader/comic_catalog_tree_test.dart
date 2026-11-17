import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/comic_detail_page.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_catalog_tree.dart';

List<ComicCatalogNode> _fixture() => const [
  ComicCatalogNode(id: 'root', nodeType: 'ROOT', title: 'Root'),
  ComicCatalogNode(
    id: 's1',
    nodeType: 'SEASON',
    title: 'Season 1',
    parentId: 'root',
  ),
  ComicCatalogNode(
    id: 'c1',
    nodeType: 'CHAPTER',
    title: 'Chapter 1',
    parentId: 's1',
  ),
  ComicCatalogNode(
    id: 'c2',
    nodeType: 'CHAPTER',
    title: 'Chapter 2',
    parentId: 's1',
    sortOrder: 1,
  ),
  ComicCatalogNode(
    id: 'v1',
    nodeType: 'VOLUME',
    title: 'Volume 1',
    parentId: 'root',
    sortOrder: 1,
  ),
  ComicCatalogNode(
    id: 'c3',
    nodeType: 'CHAPTER',
    title: 'Chapter 3',
    parentId: 'v1',
  ),
];

List<ComicCatalogNode> _thousandChapterFixture() => [
  const ComicCatalogNode(id: 'root', nodeType: 'ROOT', title: 'Root'),
  const ComicCatalogNode(
    id: 's1',
    nodeType: 'SEASON',
    title: 'Season 1',
    parentId: 'root',
  ),
  for (var i = 0; i < 1000; i++)
    ComicCatalogNode(
      id: 'c$i',
      nodeType: 'CHAPTER',
      title: 'Chapter $i',
      parentId: 's1',
      sortOrder: i,
    ),
];

void main() {
  group('ComicCatalogController', () {
    test('默认展开全部父级并按排序扁平化', () {
      final controller = ComicCatalogController(nodes: _fixture());
      expect(controller.flatRows.map((r) => r.node.id).toList(), [
        's1',
        'c1',
        'c2',
        'v1',
        'c3',
      ]);
      expect(controller.flatRows.map((r) => r.depth).toList(), [0, 1, 1, 0, 1]);
    });

    test('toggle 折叠与恢复子树', () {
      final controller = ComicCatalogController(nodes: _fixture());
      controller.toggle('s1');
      expect(controller.flatRows.map((r) => r.node.id), ['s1', 'v1', 'c3']);
      controller.toggle('s1');
      expect(controller.flatRows.map((r) => r.node.id).toList(), [
        's1',
        'c1',
        'c2',
        'v1',
        'c3',
      ]);
    });

    test('collapseAll 与 expandAll', () {
      final controller = ComicCatalogController(nodes: _fixture());
      controller.collapseAll();
      expect(controller.flatRows.map((r) => r.node.id), ['s1', 'v1']);
      controller.expandAll();
      expect(controller.flatRows.map((r) => r.node.id).toList(), [
        's1',
        'c1',
        'c2',
        'v1',
        'c3',
      ]);
    });

    test('currentPageId 解析当前节点并展开祖先路径', () {
      final nodes = _fixture();
      final controller = ComicCatalogController(nodes: nodes);
      controller.collapseAll();
      expect(controller.resolvedCurrentNodeId, isNull);
      controller.update(
        nodes: nodes,
        pages: const [
          ComicPage(
            id: 'p1',
            sourceId: 'src',
            pageIndex: 0,
            sourcePath: 'a',
            catalogNodeId: 'c2',
          ),
        ],
        currentPageId: 'p1',
      );
      expect(controller.resolvedCurrentNodeId, 'c2');
      // 仅展开当前节点的祖先链，兄弟卷保持折叠。
      expect(controller.flatRows.map((r) => r.node.id).toList(), [
        's1',
        'c1',
        'c2',
        'v1',
      ]);
    });

    test('相同输入不重复通知', () {
      final nodes = _fixture();
      final pages = <ComicPage>[];
      final controller = ComicCatalogController(nodes: nodes, pages: pages);
      var notified = 0;
      controller.addListener(() => notified++);
      controller.update(nodes: nodes, pages: pages);
      expect(notified, 0);
      controller.toggle('s1');
      expect(notified, 1);
    });
  });

  testWidgets('千章目录由 SliverList 按需构建', (tester) async {
    const comic = ReaderItem(
      id: 'comic-1',
      title: 'Sample Comic',
      itemType: 'CBZ',
      contentKind: 'COMIC',
      updatedAt: null,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.light(),
          home: Scaffold(
            body: ComicDetailPage(
              item: comic,
              chapters: _thousandChapterFixture(),
              canRead: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Table of Contents'));
    await tester.pumpAndSettle();

    // 仅可见区域与 cacheExtent 范围内行被构建，而非全量 1000 行。
    final builtRows =
        tester
            .widgetList<Text>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Text &&
                    (widget.data?.startsWith('Chapter ') ?? false),
              ),
            )
            .length;
    expect(builtRows, lessThan(200));
    expect(find.text('Chapter 999'), findsNothing);

    // 深偏移直接跳转：验证末章在滚动到位后才按需构建，无布局异常。
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Chapter 999'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('目录页签支持展开/收起全部', (tester) async {
    const comic = ReaderItem(
      id: 'comic-1',
      title: 'Sample Comic',
      itemType: 'CBZ',
      contentKind: 'COMIC',
      updatedAt: null,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.light(),
          home: Scaffold(
            body: ComicDetailPage(
              item: comic,
              chapters: _thousandChapterFixture(),
              canRead: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Table of Contents'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 0'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.unfold_less_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 0'), findsNothing);

    await tester.tap(find.byIcon(Icons.unfold_more_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
