import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/realtime/realtime_api.dart';
import 'package:omninest/core/realtime/realtime_coordinator.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/realtime/realtime_stomp_client.dart';
import 'package:omninest/core/realtime/realtime_store.dart';
import 'package:omninest/core/storage/local_database_provider.dart';

/// 当前登录用户 id；token 周期刷新产生的新会话实例不会改变该值，
/// 协调器只跟随用户身份重建，避免长连接被无谓打断。
final realtimeSessionUserIdProvider = Provider<String?>((ref) {
  return ref.watch(
    authSessionProvider.select((async) => async.asData?.value.user?.id),
  );
});

/// 当前登录用户的全平台实时同步协调器。
final realtimeCoordinatorProvider = Provider<RealtimeCoordinator?>((ref) {
  final userId = ref.watch(realtimeSessionUserIdProvider);
  if (userId == null) {
    return null;
  }
  final environment = ref.watch(appEnvironmentProvider);
  if (environment == null) {
    return null;
  }
  final apiClient = ref.watch(apiClientProvider);
  final accessToken = apiClient.currentAccessToken();
  if (accessToken == null || accessToken.isEmpty) {
    return null;
  }

  final platform = defaultTargetPlatform;
  final isMobile =
      !kIsWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
  final store = RealtimeStore(
    database: ref.watch(localDatabaseProvider),
    serverKey: _serverKey(environment.apiBaseUrl),
    userId: userId,
  );
  final client = RealtimeStompClient(
    url: '${_withoutTrailingSlash(environment.wsBaseUrl)}/realtime',
    accessTokenResolver: () => apiClient.currentAccessToken() ?? '',
  );
  final coordinator = RealtimeCoordinator(
    api: RealtimeApi(apiClient),
    store: store,
    stompClient: client,
    connectivity: ref.watch(connectivityListenerProvider).onlineStream,
    refreshSession:
        () => ref.read(authSessionProvider.notifier).refreshSession(),
    suspendInBackground: isMobile,
    headInterval:
        isMobile ? const Duration(minutes: 5) : const Duration(minutes: 2),
  );
  unawaited(coordinator.start());
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return coordinator;
});

/// 实时脏范围广播流；未登录或协调器不可用时为 null。
final realtimeDirtyScopesStreamProvider = Provider<Stream<Set<RealtimeScope>>?>(
  (ref) {
    return ref.watch(realtimeCoordinatorProvider)?.dirtyScopes;
  },
);

/// 当前实时同步状态。
final realtimePhaseProvider = StreamProvider<RealtimePhase>((ref) async* {
  final coordinator = ref.watch(realtimeCoordinatorProvider);
  if (coordinator == null) {
    yield RealtimePhase.signedOut;
    return;
  }
  yield coordinator.phase;
  yield* coordinator.phases;
});

String _serverKey(String apiBaseUrl) {
  return _withoutTrailingSlash(apiBaseUrl).toLowerCase();
}

String _withoutTrailingSlash(String value) {
  return value.replaceFirst(RegExp(r'/+$'), '');
}
