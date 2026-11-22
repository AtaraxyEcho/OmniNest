import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/widgets/desktop_shell_scope.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_management_models.dart';
import 'package:omninest/app/l10n/omni_localizations_delegates.dart';

class _AdminSession extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async => AuthSessionState(
    user: UserProfile(
      id: 'admin',
      username: 'admin',
      role: 'SUPER_ADMIN',
      roles: const {'SUPER_ADMIN'},
      permissions: const {'media:library:manage'},
    ),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );

  @override
  Future<bool> refreshSession() async => true;
}

class _ProvisionAdminSession extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async => AuthSessionState(
    user: UserProfile(
      id: 'admin',
      username: 'admin',
      role: 'SUPER_ADMIN',
      roles: const {'SUPER_ADMIN'},
      permissions: const {'media:library:manage', 'system:config:manage'},
    ),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );

  @override
  Future<bool> refreshSession() async => true;
}

void main() {
  testWidgets('desktop media library maps real source and scan data to cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_AdminSession.new),
          videoLibrarySourcesProvider.overrideWith(
            (ref) async => const [_source],
          ),
          videoStorageLocationsProvider.overrideWith(
            (ref) async => const [_location],
          ),
          latestMediaScanRunProvider(
            _source.id,
          ).overrideWith((ref) => Stream.value(_reviewRun)),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: kOmniNestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: DesktopShellScope(
              hosted: true,
              child: SingleChildScrollView(child: AdminMediaLibraryPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('电影收藏'), findsOneWidget);
    expect(find.text('已索引片目'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('等待审阅'), findsOneWidget);
    expect(find.text('审阅候选项'), findsOneWidget);
    expect(find.text('其他媒体库'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空媒体库可从可信挂载点一键初始化默认库源', (tester) async {
    tester.view.physicalSize = const Size(1440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_ProvisionAdminSession.new),
          videoLibrarySourcesProvider.overrideWith(
            (ref) async => const <VideoLibrarySource>[],
          ),
          videoStorageLocationsProvider.overrideWith(
            (ref) async => const <VideoStorageLocation>[],
          ),
          videoTrustedMountsProvider.overrideWith(
            (ref) async => const <VideoTrustedMount>[
              VideoTrustedMount(
                mountKey: 'library',
                displayName: '本机影视库',
                available: true,
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: kOmniNestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: DesktopShellScope(
              hosted: true,
              child: SingleChildScrollView(child: AdminMediaLibraryPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('初始化默认媒体库'), findsOneWidget);
    expect(find.text('本机影视库'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _location = VideoStorageLocation(
  id: 'location',
  name: '影视主库',
  providerType: 'LOCAL',
  mountKey: 'media',
  relativeRoot: '.',
  scopeType: 'SYSTEM',
  enabled: true,
  healthStatus: 'AVAILABLE',
);

const _source = VideoLibrarySource(
  id: 'source',
  name: '电影收藏',
  storageLocationId: 'location',
  relativeRoot: 'Movie',
  libraryType: VideoLibraryType.movie,
  importPolicy: 'MANUAL_REVIEW',
  visibility: MediaLibraryVisibility.private,
  enabled: true,
  scanStatus: 'READY',
  healthStatus: 'AVAILABLE',
  lastScannedCount: 18,
  lastCreatedCount: 14,
  indexedItemCount: 14,
  lastCandidateCount: 4,
  lastMissingCount: 0,
  version: 2,
);

const _reviewRun = MediaScanRun(
  id: 'review',
  librarySourceId: 'source',
  generation: 1,
  selectionRevision: 1,
  status: 'READY',
  phase: 'REVIEW',
  discoveredCount: 18,
  candidateCount: 4,
  existingCount: 14,
  conflictCount: 0,
  unmatchedCount: 0,
  missingCount: 0,
  selectedCount: 0,
  appliedCount: 0,
  failedCount: 0,
);
