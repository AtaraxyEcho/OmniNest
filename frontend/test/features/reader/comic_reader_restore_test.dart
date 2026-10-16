import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';
import 'package:omninest/features/reader/domain/comic_navigation.dart';
import 'package:omninest/features/reader/domain/reader_progress.dart';
import 'package:omninest/features/reader/presentation/pages/comic_reader_page.dart';

/// 摘要：漫画恢复位置的两条闸门——目录聚合节点的起点页，以及断网时的本地进度。
///
/// 页面的 `catalogNodeId` 只绑在叶子上，点季/卷这类聚合节点必然按页面找不到；
/// 服务端详情在离线时抛异常，旧实现把取详情与取本地进度放在同一个 try 里，
/// 异常一抛就连 SQLite 里那份进度一起跳过，断网续读永远回到第一页。
ComicManifest _manifest({int pages = 10, int manifestVersion = 1}) {
  return ComicManifest(
    itemId: 'comic-1',
    manifestVersion: manifestVersion,
    sources: const [
      ComicSource(id: 'src-1', fileFormat: 'ZIP', sourceName: 'vol.1'),
    ],
    catalog: const [
      ComicCatalogNode(id: 'root', nodeType: 'ROOT', title: 'Root'),
      ComicCatalogNode(
        id: 's1',
        nodeType: 'SEASON',
        title: 'Season 1',
        parentId: 'root',
        pageStartIndex: 4,
        pageEndIndex: 9,
      ),
      ComicCatalogNode(
        id: 'v2',
        nodeType: 'VOLUME',
        title: 'Volume 2',
        parentId: 'root',
        pageStartIndex: 20,
      ),
      ComicCatalogNode(
        id: 'c1',
        nodeType: 'CHAPTER',
        title: 'Chapter 1',
        parentId: 's1',
        pageStartIndex: 2,
      ),
    ],
    pages: [
      for (var i = 0; i < pages; i++)
        ComicPage(
          id: 'p$i',
          sourceId: 'src-1',
          sourcePath: 'vol.1/${i + 1}.jpg',
          pageIndex: i,
          sourcePageIndex: i,
          fingerprint: 'fp$i',
          catalogNodeId: i == 2 ? 'c1' : null,
          catalogKey: i == 3 ? 'k3' : null,
        ),
    ],
  );
}

ReaderProgress _server({
  int? pageIndex,
  String? pageId,
  double progressPercent = 0,
  DateTime? updatedAt,
  double? intraPageOffset,
}) {
  return ReaderProgress(
    readerItemId: 'comic-1',
    charOffset: pageIndex ?? 0,
    progressPercent: progressPercent,
    readingMode: 'webtoon',
    pageIndex: pageIndex,
    pageId: pageId,
    intraPageOffset: intraPageOffset,
    updatedAt: updatedAt ?? DateTime(2026, 10, 15, 12),
  );
}

Map<String, dynamic> _local({
  Object? pageIndex,
  Object? pageId,
  Object? catalogKey,
  Object? intraPageOffset,
  Object? chapterProgress,
  Object? manifestVersion,
  String? updatedAt,
}) {
  return <String, dynamic>{
    if (pageIndex != null) 'pageIndex': pageIndex,
    if (pageId != null) 'pageId': pageId,
    if (catalogKey != null) 'catalogKey': catalogKey,
    if (intraPageOffset != null) 'intraPageOffset': intraPageOffset,
    if (chapterProgress != null) 'chapterProgress': chapterProgress,
    if (manifestVersion != null) 'manifestVersion': manifestVersion,
    if (updatedAt != null) 'updatedAt': updatedAt,
  };
}

void main() {
  group('目录聚合节点的起点页（M4）', () {
    test('叶子节点按页面直绑落位', () {
      expect(resolveComicCatalogStartPage(_manifest(), 'c1'), 2);
    });

    test('季与卷这类聚合节点按 pageStartIndex 落位', () {
      // 聚合节点下面没有一页直接绑着它的 id：只按页面找就会回退到旧进度，
      // 表现成"点了目录没反应"。
      expect(resolveComicCatalogStartPage(_manifest(), 's1'), 4);
      expect(
        resolveComicCatalogStartPage(_manifest(pages: 30), 'v2'),
        20,
        reason: '卷起点在清单里有效时必须照收',
      );
    });

    test('节点起点越界或节点不存在时不回退到页 0', () {
      // 返回 null 表示"这个节点落不了位"，由调用方继续按旧进度走；
      // 返回 0 会把读者扔到第一页，等于把清单里的一次目录改动当成本章开头。
      expect(resolveComicCatalogStartPage(_manifest(), 'v2'), isNull);
      expect(resolveComicCatalogStartPage(_manifest(), 'nope'), isNull);
    });
  });

  group('离线恢复本地进度（M3）', () {
    test('服务端进度取不到时仍恢复本地保存的页码', () {
      final restore = resolveComicRestore(
        manifest: _manifest(),
        serverProgress: null,
        localProgress: _local(pageIndex: 6, updatedAt: '2026-10-15T10:00:00Z'),
      );
      expect(restore.page, 6, reason: '断网续读回到第一页就是这份进度白存了');
    });

    test('本地记录更新时压过服务端，服务端更新时用服务端', () {
      final localNewer = resolveComicRestore(
        manifest: _manifest(),
        serverProgress: _server(
          pageIndex: 1,
          updatedAt: DateTime(2026, 10, 15, 1),
        ),
        localProgress: _local(pageIndex: 6, updatedAt: '2026-10-15T10:00:00Z'),
      );
      expect(localNewer.page, 6);

      final serverNewer = resolveComicRestore(
        manifest: _manifest(),
        serverProgress: _server(
          pageIndex: 1,
          updatedAt: DateTime(2026, 10, 15, 23),
        ),
        localProgress: _local(pageIndex: 6, updatedAt: '2026-10-15T10:00:00Z'),
      );
      expect(serverNewer.page, 1);
    });

    test('服务端那份没有时间戳时相信本地', () {
      final localWithoutStamp = resolveComicRestore(
        manifest: _manifest(),
        serverProgress: ReaderProgress(
          readerItemId: 'comic-1',
          charOffset: 1,
          progressPercent: 0,
          readingMode: 'webtoon',
          pageIndex: 1,
          updatedAt: null,
        ),
        localProgress: _local(pageIndex: 6, updatedAt: '2026-10-15T10:00:00Z'),
      );
      expect(localWithoutStamp.page, 6);
    });

    test('本地那份没有时间戳时相信服务端', () {
      final serverHasStamp = resolveComicRestore(
        manifest: _manifest(),
        serverProgress: _server(
          pageIndex: 1,
          updatedAt: DateTime(2026, 10, 15, 1),
        ),
        localProgress: _local(pageIndex: 6),
      );
      expect(serverHasStamp.page, 1);
    });

    test('锚点优先于页码：稳定页面 id 命中时按 id 落位', () {
      final restore = resolveComicRestore(
        manifest: _manifest(),
        serverProgress: null,
        localProgress: _local(pageId: 'p5', pageIndex: 9),
      );
      expect(restore.page, 5);
    });

    test('只有比例时按总页数换算，页内偏移一起带出', () {
      final restore = resolveComicRestore(
        manifest: _manifest(),
        serverProgress: _server(progressPercent: 0.5),
        localProgress: null,
      );
      expect(restore.page, 4, reason: '50% × 10 页应落在第 5 页（下标 4）');

      final withOffset = resolveComicRestore(
        manifest: _manifest(),
        serverProgress: null,
        localProgress: _local(
          pageIndex: 6,
          intraPageOffset: 0.25,
          updatedAt: '2026-10-15T10:00:00Z',
        ),
      );
      expect(withOffset.intraPageOffset, 0.25);
    });

    test('两份进度都没有时回到首页且不带偏移', () {
      final restore = resolveComicRestore(
        manifest: _manifest(),
        serverProgress: null,
        localProgress: null,
      );
      expect(restore.page, 0);
      expect(restore.intraPageOffset, 0.0);
    });

    test('清单版本变了就不信旧页码，只按比例重算', () {
      final restore = resolveComicRestore(
        manifest: _manifest(manifestVersion: 7),
        serverProgress: null,
        localProgress: _local(
          pageIndex: 6,
          manifestVersion: 2,
          chapterProgress: 0.3,
          updatedAt: '2026-10-15T10:00:00Z',
        ),
      );
      expect(restore.page, 2, reason: '跨版本只能按 30% × 10 页重算，照抄旧下标会把读者放到别的画面上');
      expect(restore.page, isNot(6));
    });
  });

  group('阅读器内跳页判据（R4）', () {
    test('聚合目录节点的起点页与阅读页里的目录点击同源', () {
      // 目录页签与阅读页内目录都必须按 pageStartIndex 兜底：一处兜底一处不兜，
      // 就是"从详情页点了没反应、从阅读页里点却能动"。
      final manifest = _manifest(pages: 30);
      expect(resolveComicCatalogStartPage(manifest, 's1'), 4);
      expect(resolveComicCatalogStartPage(manifest, 'v2'), 20);
      expect(resolveComicCatalogStartPage(manifest, 'c1'), 2);
      expect(resolveComicCatalogStartPage(manifest, 'missing'), isNull);
    });

    test('滚动模式停在页中间时回页首不是无操作', () {
      expect(
        comicJumpIsNoOp(
          targetIndex: 0,
          currentPageIndex: 0,
          intraPageOffset: 0.6,
          isPageMode: false,
        ),
        isFalse,
        reason: '按 Home 要回到第 0 页顶部，只看页码会把它短路掉',
      );
      expect(
        comicJumpIsNoOp(
          targetIndex: 0,
          currentPageIndex: 0,
          intraPageOffset: 0.0,
          isPageMode: false,
        ),
        isTrue,
      );
      expect(
        comicJumpIsNoOp(
          targetIndex: 3,
          currentPageIndex: 4,
          intraPageOffset: 0.9,
          isPageMode: true,
        ),
        isFalse,
      );
      expect(
        comicJumpIsNoOp(
          targetIndex: 4,
          currentPageIndex: 4,
          intraPageOffset: 0.9,
          isPageMode: true,
        ),
        isTrue,
        reason: '翻页模式一屏就是一页，页内偏移对翻页没有意义',
      );
    });
  });
}
