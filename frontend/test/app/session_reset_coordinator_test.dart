import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/session/session_reset_coordinator.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';

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
}
