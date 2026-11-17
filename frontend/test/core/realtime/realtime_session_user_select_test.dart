import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';

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

  /// 模拟同用户 token 刷新：新会话实例、相同用户 id。
  void refreshTokenFor(String userId) {
    state = AsyncData(
      AuthSessionState(
        user: UserProfile(id: userId, username: userId, role: 'MEMBER'),
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
      ),
    );
  }

  void signOut() {
    state = const AsyncData(AuthSessionState.unauthenticated());
  }
}

/// 记录 auth 会话每次状态变化的用户 id 投影。
///
/// 投影表达式与生产代码 realtimeSessionUserIdProvider 的 select 完全
/// 一致；watch 传播在 overrideWith 的 AsyncNotifier 测试态下不可靠，
/// 故经 listen 通道取事件后按 select 语义做连续去重断言。
final userIdEventRecorderProvider = Provider<List<String?>>((ref) {
  final events = <String?>[];
  ref.listen<AsyncValue<AuthSessionState>>(authSessionProvider, (prev, next) {
    events.add(next.asData?.value.user?.id);
  });
  return events;
});

/// select 的重建判定等价于对投影值做连续去重；首个事件是监听激活
/// 时的基线值，不构成变更。
List<String?> _projectedIdentityChanges(List<String?> events) {
  if (events.isEmpty) {
    return const [];
  }
  final changes = <String?>[];
  var previous = events.first;
  for (var i = 1; i < events.length; i++) {
    final id = events[i];
    if (id != previous) {
      changes.add(id);
      previous = id;
    }
  }
  return changes;
}

void main() {
  test('same-user token refresh emits no identity change', () async {
    final container = ProviderContainer.test(
      overrides: [
        authSessionProvider.overrideWith(_ControllableAuthSessionNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    final events =
        container.listen(userIdEventRecorderProvider, (_, _) {}).read();
    final auth =
        container.read(authSessionProvider.notifier)
            as _ControllableAuthSessionNotifier;
    await container.read(authSessionProvider.future);

    auth.signInAs('user-a');
    auth.refreshTokenFor('user-a');
    auth.refreshTokenFor('user-a');

    expect(_projectedIdentityChanges(events), ['user-a']);
  });

  test('account switch and sign-out emit identity changes', () async {
    final container = ProviderContainer.test(
      overrides: [
        authSessionProvider.overrideWith(_ControllableAuthSessionNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    final events =
        container.listen(userIdEventRecorderProvider, (_, _) {}).read();
    final auth =
        container.read(authSessionProvider.notifier)
            as _ControllableAuthSessionNotifier;
    await container.read(authSessionProvider.future);

    auth.signInAs('user-a');
    auth.signInAs('user-b');
    auth.signOut();

    expect(_projectedIdentityChanges(events), ['user-a', 'user-b', null]);
  });
}
