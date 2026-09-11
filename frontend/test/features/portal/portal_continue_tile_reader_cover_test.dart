import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/portal/application/portal_dashboard_providers.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_media_thumbnail.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_mobile_shell.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_image.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';
import 'package:omninest/features/video/domain/movie_models.dart';

void main() {
  testWidgets('继续使用列表中阅读卡片走 AuthCoverImage，不用接口路径当图片地址', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
          portalReaderDashboardProvider.overrideWith((ref) async {
            return ReaderDashboard(
              overview: const ReaderOverview(totalItems: 1, continueCount: 1),
              continueReading: [
                ReaderItem(
                  id: 'reader-1',
                  title: '测试书',
                  itemType: 'EPUB',
                  updatedAt: DateTime(2026, 9, 1),
                  // 后端真实形态：接口路径而非可直渲图片 URL。
                  coverUrl: '/files/cover-file-1/download-url',
                  progressPercent: 42,
                ),
              ],
              recentItems: const [],
            );
          }),
          portalMovieDashboardProvider.overrideWith(
            (ref) async => MovieDashboard.empty(),
          ),
          portalMusicSnapshotProvider.overrideWithValue(
            const AsyncValue.data(
              MusicPortalSnapshot(
                featuredTrack: null,
                featuredAlbum: null,
                activeTrack: null,
                queuePreview: [],
                recentTracks: [],
                recentPlayCount: 0,
                isPlaying: false,
              ),
            ),
          ),
          portalPhotoDashboardProvider.overrideWith(
            _EmptyPhotoDashboardController.new,
          ),
          portalStorageStatsProvider.overrideWith((ref) async {
            return const FileStorageStats(
              totalFiles: 0,
              totalFolders: 0,
              usedBytes: 0,
              quotaBytes: 0,
              quotaStatus: 'NORMAL',
              typeDistribution: [],
            );
          }),
          activeTaskSummaryProvider.overrideWith((ref) async {
            return const ActiveTaskSummary(activeCount: 0, failedCount: 0);
          }),
          appOnlineStatusProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const MobileShellScope(
            hosted: true,
            child: PortalMobileShell(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试书'), findsWidgets);
    expect(find.byType(AuthCoverImage), findsOneWidget);
    // 阅读封面不得再把 /files/{id}/download-url 交给网络图片组件。
    final networkThumbs =
        tester
            .widgetList<PortalMediaThumbnail>(find.byType(PortalMediaThumbnail))
            .toList();
    for (final thumb in networkThumbs) {
      expect(thumb.imageUrl, isNot(contains('/download-url')));
    }
  });
}

class _EmptyPhotoDashboardController extends PhotoDashboardController {
  @override
  Future<PhotoDashboard> build() async {
    return PhotoDashboard.empty();
  }
}
