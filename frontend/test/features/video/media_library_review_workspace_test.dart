import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_management_models.dart';
import 'package:omninest/features/video/presentation/widgets/movie_management.dart';

const _source = VideoLibrarySource(
  id: 'movie',
  name: '电影收藏',
  storageLocationId: 'storage',
  relativeRoot: 'Movie',
  libraryType: VideoLibraryType.movie,
  importPolicy: 'MANUAL_REVIEW',
  visibility: MediaLibraryVisibility.private,
  enabled: true,
  scanStatus: 'READY',
  healthStatus: 'AVAILABLE',
  lastScannedCount: 24,
  lastCreatedCount: 0,
  lastCandidateCount: 3,
  lastMissingCount: 0,
  version: 0,
);

const _readyRun = MediaScanRun(
  id: 'run-1',
  librarySourceId: 'movie',
  generation: 3,
  selectionRevision: 5,
  status: 'READY',
  phase: 'REVIEW',
  discoveredCount: 10,
  candidateCount: 4,
  existingCount: 18,
  conflictCount: 0,
  unmatchedCount: 1,
  missingCount: 0,
  selectedCount: 2,
  appliedCount: 16,
  failedCount: 0,
);

Future<void> _pump(
  WidgetTester tester, {
  required MediaScanRun? run,
  MediaPage<MediaScanTreeNode>? treePage,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        latestMediaScanRunProvider(
          'movie',
        ).overrideWith((ref) => Stream.value(run)),
        if (treePage != null)
          mediaScanTreeProvider((
            runId: run!.id,
            parentNodeId: null,
            page: 0,
          )).overrideWith((ref) async => treePage),
      ],
      child: MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: MediaLibraryReviewWorkspace(source: _source),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('无扫描运行时展示发现引导空态', (tester) async {
    await _pump(tester, run: null);
    expect(find.byIcon(Icons.manage_search_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('运行中展示任务进度面板', (tester) async {
    await _pump(
      tester,
      run: const MediaScanRun(
        id: 'run-2',
        librarySourceId: 'movie',
        generation: 4,
        selectionRevision: 6,
        status: 'DISCOVERING',
        phase: 'DISCOVERY',
        discoveredCount: 5,
        candidateCount: 0,
        existingCount: 18,
        conflictCount: 0,
        unmatchedCount: 0,
        missingCount: 0,
        selectedCount: 0,
        appliedCount: 0,
        failedCount: 0,
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('审阅态展示摘要栏与媒体树节点', (tester) async {
    await _pump(
      tester,
      run: _readyRun,
      treePage: const MediaPage<MediaScanTreeNode>(
        items: [
          MediaScanTreeNode(
            nodeId: 'node-1',
            nodeType: 'FILE',
            title: '电影A.mkv',
            hasChildren: false,
            childCount: 0,
            candidateCount: 0,
            selectedCount: 1,
            issueCount: 0,
            selectionState: 'SELECTED',
          ),
        ],
        page: 0,
        size: 50,
        totalElements: 1,
        totalPages: 1,
      ),
    );
    expect(find.text('电影A.mkv'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文件夹节点原地展开懒加载子节点', (tester) async {
    const folderPage = MediaPage<MediaScanTreeNode>(
      items: [
        MediaScanTreeNode(
          nodeId: 'folder-1',
          nodeType: 'DIRECTORY',
          title: '剧集A',
          hasChildren: true,
          childCount: 1,
          candidateCount: 2,
          selectedCount: 0,
          issueCount: 0,
          selectionState: 'NONE',
        ),
      ],
      page: 0,
      size: 50,
      totalElements: 1,
      totalPages: 1,
    );
    const childPage = MediaPage<MediaScanTreeNode>(
      items: [
        MediaScanTreeNode(
          nodeId: 'file-1',
          nodeType: 'FILE',
          title: '第1集.mkv',
          hasChildren: false,
          childCount: 0,
          candidateCount: 1,
          selectedCount: 0,
          issueCount: 0,
          selectionState: 'NONE',
          matchStatus: 'NEW',
        ),
      ],
      page: 0,
      size: 50,
      totalElements: 1,
      totalPages: 1,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          latestMediaScanRunProvider(
            'movie',
          ).overrideWith((ref) => Stream.value(_readyRun)),
          mediaScanTreeProvider((
            runId: 'run-1',
            parentNodeId: null,
            page: 0,
          )).overrideWith((ref) async => folderPage),
          mediaScanTreeProvider((
            runId: 'run-1',
            parentNodeId: 'folder-1',
            page: 0,
          )).overrideWith((ref) async => childPage),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: MediaLibraryReviewWorkspace(source: _source),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('剧集A'), findsOneWidget);
    expect(find.text('第1集.mkv'), findsNothing);
    await tester.tap(find.text('剧集A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('第1集.mkv'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
