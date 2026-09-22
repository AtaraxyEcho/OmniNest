import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/session/session_reset_coordinator.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/music/application/music_history_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/portal/application/portal_paged_cards.dart';
import 'package:omninest/features/reader/domain/reader_item.dart';

class _ControllableAuthSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async =>
      const AuthSessionState.unauthenticated();

  void signInAs(String userId) {
    state = AsyncData(
      AuthSessionState(
        user: UserProfile(id: userId, username: userId, role: 'MEMBER'),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }

  void signOut() {
    state = const AsyncData(AuthSessionState.unauthenticated());
  }
}

class _CountingMusicHistoryNotifier extends MusicHistoryController {
  _CountingMusicHistoryNotifier(this.onBuild);

  final void Function() onBuild;

  @override
  Future<MusicHistoryState> build() async {
    onBuild();
    return const MusicHistoryState();
  }
}

void main() {
  test('cold-start login does not invalidate business providers', () async {
    var statsBuilds = 0;
    final container = ProviderContainer.test(
      overrides: [
        authSessionProvider.overrideWith(_ControllableAuthSessionNotifier.new),
        fileStorageStatsProvider.overrideWith((ref) {
          statsBuilds += 1;
          return const FileStorageStats(
            totalFiles: 0,
            totalFolders: 0,
            usedBytes: 0,
            quotaStatus: 'NORMAL',
            quotaBytes: 1024,
            typeDistribution: [],
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionResetCoordinatorProvider);
    final auth =
        container.read(authSessionProvider.notifier)
            as _ControllableAuthSessionNotifier;
    // 等待会话 provider 初始 build 完成后再驱动状态，避免 build 完成时覆写。
    await container.read(authSessionProvider.future);

    auth.signInAs('user-a');
    await container.read(fileStorageStatsProvider.future);

    expect(statsBuilds, 1);
  });

  test('same-user token refresh keeps business providers alive', () async {
    var statsBuilds = 0;
    final container = ProviderContainer.test(
      overrides: [
        authSessionProvider.overrideWith(_ControllableAuthSessionNotifier.new),
        fileStorageStatsProvider.overrideWith((ref) {
          statsBuilds += 1;
          return const FileStorageStats(
            totalFiles: 0,
            totalFolders: 0,
            usedBytes: 0,
            quotaStatus: 'NORMAL',
            quotaBytes: 1024,
            typeDistribution: [],
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionResetCoordinatorProvider);
    final auth =
        container.read(authSessionProvider.notifier)
            as _ControllableAuthSessionNotifier;
    await container.read(authSessionProvider.future);

    auth.signInAs('user-a');
    await container.read(fileStorageStatsProvider.future);
    auth.signInAs('user-a');
    await container.read(fileStorageStatsProvider.future);

    expect(statsBuilds, 1);
  });

  test('account switch and sign-out reset cached business providers', () async {
    var statsBuilds = 0;
    final container = ProviderContainer.test(
      overrides: [
        authSessionProvider.overrideWith(_ControllableAuthSessionNotifier.new),
        fileStorageStatsProvider.overrideWith((ref) {
          statsBuilds += 1;
          return FileStorageStats(
            totalFiles: statsBuilds,
            totalFolders: 0,
            usedBytes: 0,
            quotaStatus: 'NORMAL',
            quotaBytes: 1024,
            typeDistribution: [],
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionResetCoordinatorProvider);
    final auth =
        container.read(authSessionProvider.notifier)
            as _ControllableAuthSessionNotifier;
    await container.read(authSessionProvider.future);

    auth.signInAs('user-a');
    await container.read(fileStorageStatsProvider.future);
    expect(statsBuilds, 1);

    // 换号（A→B）触发重置，下一次读取重建。
    auth.signInAs('user-b');
    final afterSwitch = await container.read(fileStorageStatsProvider.future);
    expect(statsBuilds, 2);
    expect(afterSwitch.totalFiles, 2);

    // 登出（B→未认证）再次触发重置。
    auth.signOut();
    await container.read(fileStorageStatsProvider.future);
    expect(statsBuilds, 3);
  });

  test(
    'account switch resets music history and connector oauth caches',
    () async {
      var historyBuilds = 0;
      var oauthBuilds = 0;
      final container = ProviderContainer.test(
        overrides: [
          authSessionProvider.overrideWith(
            _ControllableAuthSessionNotifier.new,
          ),
          musicHistoryControllerProvider.overrideWith(
            () => _CountingMusicHistoryNotifier(() => historyBuilds += 1),
          ),
          adminConnectorOAuthAppsProvider.overrideWith((ref) async {
            oauthBuilds += 1;
            return const [];
          }),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionResetCoordinatorProvider);
      final auth =
          container.read(authSessionProvider.notifier)
              as _ControllableAuthSessionNotifier;
      await container.read(authSessionProvider.future);

      auth.signInAs('user-a');
      await container.read(musicHistoryControllerProvider.future);
      await container.read(adminConnectorOAuthAppsProvider.future);
      expect(historyBuilds, 1);
      expect(oauthBuilds, 1);

      // 换号后播放历史与连接器 OAuth 缓存不得跨账号残留。
      auth.signInAs('user-b');
      await container.read(musicHistoryControllerProvider.future);
      await container.read(adminConnectorOAuthAppsProvider.future);
      expect(historyBuilds, 2);
      expect(oauthBuilds, 2);
    },
  );

  test('account switch resets portal paged card caches', () async {
    var photosBuilds = 0;
    var shelfBuilds = 0;
    final container = ProviderContainer.test(
      overrides: [
        authSessionProvider.overrideWith(_ControllableAuthSessionNotifier.new),
        portalRecentPhotosProvider.overrideWith(
          () => _CountingPortalPhotosController(() => photosBuilds += 1),
        ),
        portalReaderShelfProvider.overrideWith(
          () => _CountingPortalShelfController(() => shelfBuilds += 1),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionResetCoordinatorProvider);
    final auth =
        container.read(authSessionProvider.notifier)
            as _ControllableAuthSessionNotifier;
    await container.read(authSessionProvider.future);

    auth.signInAs('user-a');
    await container.read(portalRecentPhotosProvider.future);
    await container.read(portalReaderShelfProvider.future);
    expect(photosBuilds, 1);
    expect(shelfBuilds, 1);

    // 门户卡片缓存用户内容（照片/书架），换号后不得残留。
    auth.signInAs('user-b');
    await container.read(portalRecentPhotosProvider.future);
    await container.read(portalReaderShelfProvider.future);
    expect(photosBuilds, 2);
    expect(shelfBuilds, 2);
  });
}

class _CountingPortalPhotosController extends PortalRecentPhotosController {
  _CountingPortalPhotosController(this.onBuild);

  final void Function() onBuild;

  @override
  Future<PortalPagedListState<PhotoItem>> build() async {
    onBuild();
    return PortalPagedListState<PhotoItem>();
  }
}

class _CountingPortalShelfController extends PortalReaderShelfController {
  _CountingPortalShelfController(this.onBuild);

  final void Function() onBuild;

  @override
  Future<PortalPagedListState<ReaderItem>> build() async {
    onBuild();
    return PortalPagedListState<ReaderItem>();
  }
}
