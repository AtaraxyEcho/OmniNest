import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/sync/preference_sync_handler.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/realtime/realtime_models.dart';

/// 捕获容器级 Ref，供直接构造同步 handler 使用。
final refHolderProvider = Provider<Ref>((ref) => ref);

class _SpyAuthNotifier extends AuthSessionNotifier {
  _SpyAuthNotifier(this.onReload);

  final void Function() onReload;

  @override
  Future<AuthSessionState> build() async =>
      const AuthSessionState.unauthenticated();

  @override
  Future<void> reloadProfile() async => onReload();
}

void main() {
  test('用户资料事件触发会话资料重拉', () async {
    var reloads = 0;
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(
          () => _SpyAuthNotifier(() => reloads += 1),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionProvider.future);
    expect(reloads, 0);

    final handler = PreferenceSyncHandler(container.read(refHolderProvider));
    final consumed = await handler.refresh([
      RealtimeInvalidation(
        key: 'pref-profile-1',
        scope: RealtimeScope.preferences,
        resourceType: 'USER_PROFILE',
        resourceId: 'USER_PROFILE',
        revision: 1,
        createdAt: DateTime.utc(2026, 9, 20),
      ),
    ]);

    expect(consumed, isTrue);
    expect(reloads, 1);
  });
}
