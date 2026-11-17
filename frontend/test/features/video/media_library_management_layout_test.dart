import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/presentation/widgets/movie_management.dart';
import 'package:omninest/features/video/presentation/widgets/movie_shell.dart';

void main() {
  testWidgets('review workspace exposes candidate hierarchy inline', (
    tester,
  ) async {
    await _pumpReviewWorkspace(
      tester,
      reviewRun: _readyRun,
      reviewPage: _reviewPage,
      reviewChildNodeId: 'SERIES:1',
      reviewChildPage: _reviewChildPage,
    );

    // 媒体树为父子嵌套列表：根层节点直接可见，无右侧详情面板。
    expect(find.text('候选电影'), findsOneWidget);
    expect(find.text('示例剧集'), findsOneWidget);
    expect(find.textContaining('选择左侧候选'), findsNothing);

    // 文件夹节点原地展开懒加载子节点。
    await tester.tap(find.text('示例剧集'));
    await tester.pumpAndSettle();

    expect(find.text('示例剧集 第1集'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('access workspace switches to paged selected users', (
    tester,
  ) async {
    await _pumpAccessPanel(tester);

    expect(
      find.widgetWithText(RadioListTile<MediaLibraryVisibility>, '私人'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(RadioListTile<MediaLibraryVisibility>, '指定用户'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(RadioListTile<MediaLibraryVisibility>, '全部成员'),
      findsOneWidget,
    );

    await tester.tap(
      find.widgetWithText(RadioListTile<MediaLibraryVisibility>, '指定用户'),
    );
    await tester.pumpAndSettle();

    expect(find.text('家庭成员'), findsOneWidget);
    expect(find.text('@member'), findsOneWidget);
    expect(find.text('保存访问权限'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('management navigation follows media library permission', (
    tester,
  ) async {
    Future<void> pumpSidebar(bool canManage) {
      return tester.pumpWidget(
        MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: MovieSidebar(
              section: MovieSection.movies,
              canManage: canManage,
              closeOnSelect: false,
            ),
          ),
        ),
      );
    }

    await pumpSidebar(false);
    expect(find.text('影片管理'), findsNothing);
    expect(find.text('管理工具'), findsNothing);

    await pumpSidebar(true);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('影片管理'), findsOneWidget);
    expect(find.text('管理工具'), findsOneWidget);
  });
}

Future<void> _pumpReviewWorkspace(
  WidgetTester tester, {
  MediaScanRun? reviewRun,
  MediaPage<MediaScanTreeNode>? reviewPage,
  String? reviewChildNodeId,
  MediaPage<MediaScanTreeNode>? reviewChildPage,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        latestMediaScanRunProvider(
          'movie',
        ).overrideWith((ref) => Stream.value(reviewRun)),
        if (reviewRun != null && reviewPage != null)
          mediaScanTreeProvider((
            runId: reviewRun.id,
            parentNodeId: null,
            page: 0,
          )).overrideWith((ref) async => reviewPage),
        if (reviewRun != null &&
            reviewChildNodeId != null &&
            reviewChildPage != null)
          mediaScanTreeProvider((
            runId: reviewRun.id,
            parentNodeId: reviewChildNodeId,
            page: 0,
          )).overrideWith((ref) async => reviewChildPage),
      ],
      child: MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 900,
              child: MediaLibraryReviewWorkspace(
                source: _librarySources.first,
                treeHeight: 400,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpAccessPanel(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mediaLibraryAccessProvider('movie').overrideWith(
          (ref) async => const MediaLibraryAccessSettings(
            librarySourceId: 'movie',
            visibility: MediaLibraryVisibility.private,
            selectedUserIds: <String>{},
            version: 0,
          ),
        ),
        mediaLibraryAccessUsersProvider((query: '', page: 0)).overrideWith(
          (ref) async => const MediaPage<MediaLibraryUserCandidate>(
            items: [
              MediaLibraryUserCandidate(
                id: 'member-id',
                username: 'member',
                displayName: '家庭成员',
                status: 'ACTIVE',
              ),
            ],
            page: 0,
            size: 50,
            totalElements: 1,
            totalPages: 1,
          ),
        ),
      ],
      child: MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 480,
              child: MediaLibraryAccessPanel(source: _librarySources.first),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _librarySources = [
  VideoLibrarySource(
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
  ),
];

const _readyRun = MediaScanRun(
  id: 'run-ready',
  librarySourceId: 'movie',
  generation: 2,
  selectionRevision: 4,
  status: 'READY',
  phase: 'DISCOVERY',
  discoveredCount: 26,
  candidateCount: 24,
  existingCount: 2,
  conflictCount: 1,
  unmatchedCount: 0,
  missingCount: 0,
  selectedCount: 3,
  appliedCount: 0,
  failedCount: 0,
);

const _reviewChildPage = MediaPage<MediaScanTreeNode>(
  items: [
    MediaScanTreeNode(
      nodeId: 'EPISODE:1',
      nodeType: 'FILE',
      title: '示例剧集 第1集',
      hasChildren: false,
      childCount: 0,
      candidateCount: 1,
      selectedCount: 1,
      issueCount: 0,
      selectionState: 'ALL',
      matchStatus: 'NEW',
    ),
  ],
  page: 0,
  size: 100,
  totalElements: 1,
  totalPages: 1,
);

const _reviewPage = MediaPage<MediaScanTreeNode>(
  items: [
    MediaScanTreeNode(
      nodeId: 'MOVIE:1',
      nodeType: 'MOVIE',
      title: '候选电影',
      subtitle: 'Movie/Candidate.2026.mkv',
      hasChildren: false,
      childCount: 0,
      candidateCount: 1,
      selectedCount: 1,
      issueCount: 0,
      selectionState: 'ALL',
      matchStatus: 'NEW',
    ),
    MediaScanTreeNode(
      nodeId: 'SERIES:1',
      nodeType: 'SERIES',
      title: '示例剧集',
      hasChildren: true,
      childCount: 2,
      candidateCount: 23,
      selectedCount: 2,
      issueCount: 1,
      selectionState: 'PARTIAL',
      matchStatus: 'AMBIGUOUS',
    ),
  ],
  page: 0,
  size: 100,
  totalElements: 2,
  totalPages: 1,
);
