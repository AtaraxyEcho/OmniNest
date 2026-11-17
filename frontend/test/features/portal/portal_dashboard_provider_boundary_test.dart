import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/admin/admin_dashboard.dart';
import 'package:omninest/features/files/file_dashboard.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/photos/photo_dashboard.dart';
import 'package:omninest/features/portal/application/portal_dashboard_providers.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';
import 'package:omninest/features/video/video_dashboard.dart';

void main() {
  test('Portal 摘要复用各模块公开只读 Provider', () {
    expect(
      identical(portalStorageStatsProvider, fileStorageStatsProvider),
      isTrue,
    );
    expect(
      identical(portalMovieDashboardProvider, movieDashboardProvider),
      isTrue,
    );
    expect(
      identical(portalMusicSnapshotProvider, musicPortalSnapshotProvider),
      isTrue,
    );
    expect(
      identical(
        portalMusicPlaybackTimelineProvider,
        musicPortalPlaybackTimelineProvider,
      ),
      isTrue,
    );
    expect(
      identical(portalMusicActionsProvider, musicPortalActionsProvider),
      isTrue,
    );
    expect(
      identical(portalPhotoDashboardProvider, photoDashboardProvider),
      isTrue,
    );
    expect(
      identical(portalAdminSummaryProvider, adminConsoleSummaryProvider),
      isTrue,
    );
    expect(
      identical(portalReaderDashboardProvider, readerDashboardProvider),
      isTrue,
    );
  });
}
