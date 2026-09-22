import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_platform_qr_session_controller.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/domain/music_models.dart';

class _MockMusicApi extends Mock implements MusicApi {}

/// 轮询循环在 application 层，这里锁定它的状态机契约：
/// 会话申请、状态去重、过期收尾、确认后刷新、失败可见与取消。
void main() {
  late _MockMusicApi api;

  setUp(() {
    api = _MockMusicApi();
  });

  /// 等待首轮轮询完成（首轮无退避，立即执行）。
  Future<void> settleFirstPoll() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  ProviderContainer createContainer({Future<void> Function()? refresh}) {
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        if (refresh != null)
          platformQrLoginRefreshProvider.overrideWithValue(refresh),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  String qrBase64() => base64Encode(const <int>[137, 80, 78, 71]);

  void stubSession() {
    when(() => api.createNeteaseQrLogin()).thenAnswer(
      (_) async => QrLoginSession(loginKey: 'key-1', qrImageBase64: qrBase64()),
    );
  }

  test('start requests a session and decodes the QR bitmap once', () async {
    stubSession();
    when(
      () => api.checkNeteaseQrLogin('key-1'),
    ).thenAnswer((_) async => const QrLoginStatus(status: 'pending'));
    final container = createContainer();

    await container.read(platformQrSessionProvider.notifier).start();
    await settleFirstPoll();

    final state = container.read(platformQrSessionProvider);
    expect(state.status, PlatformQrDisplayStatus.waiting);
    expect(state.loginKey, 'key-1');
    expect(state.hasQrImage, isTrue);
    verify(() => api.createNeteaseQrLogin()).called(1);

    container.read(platformQrSessionProvider.notifier).cancel();
  });

  test('repeated identical status does not notify listeners again', () async {
    stubSession();
    when(
      () => api.checkNeteaseQrLogin('key-1'),
    ).thenAnswer((_) async => const QrLoginStatus(status: 'pending'));
    final container = createContainer();
    var notifications = 0;
    final subscription = container.listen<PlatformQrSessionState>(
      platformQrSessionProvider,
      (previous, next) => notifications++,
    );
    addTearDown(subscription.close);

    await container.read(platformQrSessionProvider.notifier).start();
    await settleFirstPoll();
    final afterFirstPoll = notifications;

    // 第二轮轮询拿到同样的 pending：状态未变化则不再通知，
    // 否则面板（含二维码位图）会每 2 秒重建一次，表现为闪烁。
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(notifications, afterFirstPoll);

    container.read(platformQrSessionProvider.notifier).cancel();
  });

  test(
    'confirmed status triggers platform refresh and stops polling',
    () async {
      stubSession();
      var refreshCalls = 0;
      when(
        () => api.checkNeteaseQrLogin('key-1'),
      ).thenAnswer((_) async => const QrLoginStatus(status: 'confirmed'));
      final container = createContainer(refresh: () async => refreshCalls++);

      await container.read(platformQrSessionProvider.notifier).start();
      await settleFirstPoll();

      expect(refreshCalls, 1);
      verify(() => api.checkNeteaseQrLogin('key-1')).called(1);
    },
  );

  test('expired status ends the session with a regeneratable state', () async {
    stubSession();
    when(
      () => api.checkNeteaseQrLogin('key-1'),
    ).thenAnswer((_) async => const QrLoginStatus(status: 'expired'));
    final container = createContainer();

    await container.read(platformQrSessionProvider.notifier).start();
    await settleFirstPoll();

    final state = container.read(platformQrSessionProvider);
    expect(state.status, PlatformQrDisplayStatus.expired);
    expect(state.canRegenerate, isTrue);
  });

  test('polling failure surfaces an error state with a message', () async {
    stubSession();
    when(() => api.checkNeteaseQrLogin('key-1')).thenThrow(DioExceptionStub());
    final container = createContainer();

    await container.read(platformQrSessionProvider.notifier).start();
    await settleFirstPoll();

    final state = container.read(platformQrSessionProvider);
    expect(state.status, PlatformQrDisplayStatus.error);
    expect(state.failureMessage, isNotNull);
    expect(state.canRegenerate, isTrue);

    container.read(platformQrSessionProvider.notifier).cancel();
  });

  test(
    'start reuses an unexpired session instead of requesting a new one',
    () async {
      stubSession();
      when(
        () => api.checkNeteaseQrLogin('key-1'),
      ).thenAnswer((_) async => const QrLoginStatus(status: 'pending'));
      final container = createContainer();
      final notifier = container.read(platformQrSessionProvider.notifier);

      await notifier.start();
      await settleFirstPoll();
      expect(verify(() => api.checkNeteaseQrLogin('key-1')).callCount, 1);

      // 再次进入扫码方式（例如切到手机号又切回）：已有未过期会话只续用，
      // 不会重新申请二维码，用户手上那张码仍然有效。
      await notifier.start();
      await settleFirstPoll();

      verify(() => api.createNeteaseQrLogin()).called(1);
      notifier.cancel();
    },
  );

  test('cancel stops the polling loop', () async {
    stubSession();
    when(
      () => api.checkNeteaseQrLogin('key-1'),
    ).thenAnswer((_) async => const QrLoginStatus(status: 'pending'));
    final container = createContainer();
    final notifier = container.read(platformQrSessionProvider.notifier);

    await notifier.start();
    await settleFirstPoll();
    notifier.cancel();
    final callsAtCancel =
        verify(() => api.checkNeteaseQrLogin('key-1')).callCount;
    expect(callsAtCancel, greaterThan(0));

    // 取消后不再有任何新的轮询请求（已有的调用已被上面 verify 消费）。
    await Future<void>.delayed(const Duration(seconds: 3));
    verifyNever(() => api.checkNeteaseQrLogin('key-1'));
  });
}

/// 模拟一次网络层异常（保持与真实调用一致的异常类型语义）。
class DioExceptionStub implements Exception {
  @override
  String toString() => 'DioExceptionStub';
}
