import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/reader/application/reader_comic_service.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_item_detail_page.dart';

final _user = UserProfile(
  id: 'u1',
  username: 'tester',
  role: 'ADMIN',
  permissions: {'media:write'},
);

const _readyItem = ReaderItem(
  id: 'comic-1',
  title: 'Sample Comic',
  itemType: 'CBZ',
  contentKind: 'COMIC',
  updatedAt: null,
);

const _parsingItem = ReaderItem(
  id: 'comic-1',
  title: 'Sample Comic',
  itemType: 'CBZ',
  contentKind: 'COMIC',
  importStatus: 'PARSING',
  updatedAt: null,
);

class _FakeAuthSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    return AuthSessionState(user: _user);
  }
}

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

ComicManifest _manifest({
  String importStatus = 'READY',
  ComicParseTask? parseTask,
}) {
  return ComicManifest(
    itemId: 'comic-1',
    importStatus: importStatus,
    parseTask: parseTask,
    sources: const [
      ComicSource(id: 'src1', fileFormat: 'CBZ', sourceName: 'book.cbz'),
    ],
    catalog: _catalogFixture(),
    pages: [
      for (var i = 0; i < 12; i++)
        ComicPage(
          id: 'p$i',
          sourceId: 'src1',
          pageIndex: i,
          sourcePath: 'p/$i',
        ),
    ],
  );
}

Future<void> _pumpReader(
  WidgetTester tester, {
  required ReaderItem item,
  required Stream<ComicManifestMonitorState> monitor,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(_FakeAuthSessionNotifier.new),
        readerItemDetailProvider(
          'comic-1',
        ).overrideWith((ref) => Future.value(ReaderItemDetail(item: item))),
        comicManifestMonitorProvider('comic-1').overrideWith((ref) => monitor),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: OmniNestTheme.light(),
        home: const ReaderItemDetailPage(itemId: 'comic-1'),
      ),
    ),
  );
}

void main() {
  testWidgets('语义树启用下漫画详情完整链路交互无断言', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpReader(
      tester,
      item: _readyItem,
      monitor: Stream.value(ComicManifestMonitorState(manifest: _manifest())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Table of Contents'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Table of Contents'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 150));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('解析中到就绪的清单换树不触发语义断言', (tester) async {
    final semantics = tester.ensureSemantics();
    final monitor = StreamController<ComicManifestMonitorState>();
    addTearDown(() => monitor.close());

    // 首轮失效重取仍返回解析中条目，随后服务端视角更新为就绪，
    // 与真实流程一致：失效循环恰好走一轮后收敛。
    var currentItem = _parsingItem;
    final overrides = [
      authSessionProvider.overrideWith(_FakeAuthSessionNotifier.new),
      readerItemDetailProvider('comic-1').overrideWith(
        (ref) => Future.value(ReaderItemDetail(item: currentItem)),
      ),
      comicManifestMonitorProvider(
        'comic-1',
      ).overrideWith((ref) => monitor.stream),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.light(),
          home: const ReaderItemDetailPage(itemId: 'comic-1'),
        ),
      ),
    );

    monitor.add(
      ComicManifestMonitorState(
        manifest: _manifest(
          importStatus: 'PENDING',
          parseTask: const ComicParseTask(
            id: 't1',
            status: 'PARSING',
            progress: 40,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // 清单就绪：终态与本地解析标志不一致，包装器会安排 500ms 失效重取。
    monitor.add(
      ComicManifestMonitorState(
        manifest: _manifest(
          importStatus: 'READY',
          parseTask: const ComicParseTask(
            id: 't1',
            status: 'FINISHED',
            progress: 100,
          ),
        ),
      ),
    );
    await tester.pump();
    currentItem = _readyItem;
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pumpAndSettle();
    // 兜底消化包装器可能再次安排的失效定时器。
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
