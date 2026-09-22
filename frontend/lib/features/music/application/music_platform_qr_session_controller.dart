import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/music/application/music_controller.dart';

/// 二维码登录面板的展示状态。
enum PlatformQrDisplayStatus {
  /// 尚未发起或已结束，面板显示"点击获取二维码"。
  idle,

  /// 正在申请会话。
  starting,

  /// 等待扫码。
  waiting,

  /// 已扫码，等待手机端确认。
  scanned,

  /// 二维码已过期（或超出轮询上限）。
  expired,

  /// 连续失败次数超限。
  error,

  /// 平台返回了未识别状态。
  unknown,
}

/// 平台二维码登录会话状态。
///
/// [qrBytes] 是解码后的二维码位图，与 [loginKey] 同生命周期：只在换码时重算，
/// 避免每次构建都重新解码 base64 导致图片重新解析（表现为二维码闪烁）。
class PlatformQrSessionState {
  const PlatformQrSessionState({
    this.status = PlatformQrDisplayStatus.idle,
    this.loginKey,
    this.qrBytes,
    this.unknownStatus,
    this.failureMessage,
    this.regenerating = false,
  });

  final PlatformQrDisplayStatus status;
  final String? loginKey;
  final Uint8List? qrBytes;
  final String? unknownStatus;

  /// 最近一次失败的用户可读文案，供面板在错误态展示。
  final String? failureMessage;
  final bool regenerating;

  /// 是否已有可用于展示的二维码。
  bool get hasQrImage => qrBytes != null && qrBytes!.isNotEmpty;

  /// 是否处于需要"重新生成"的可重试状态。
  bool get canRegenerate =>
      status == PlatformQrDisplayStatus.expired ||
      status == PlatformQrDisplayStatus.error ||
      status == PlatformQrDisplayStatus.unknown;

  /// 是否应在状态行展示进度指示。
  bool get busy =>
      status == PlatformQrDisplayStatus.starting ||
      status == PlatformQrDisplayStatus.waiting ||
      status == PlatformQrDisplayStatus.scanned ||
      regenerating;

  PlatformQrSessionState copyWith({
    PlatformQrDisplayStatus? status,
    String? loginKey,
    Uint8List? qrBytes,
    String? unknownStatus,
    String? failureMessage,
    bool? regenerating,
    bool clearQrBytes = false,
    bool clearUnknownStatus = false,
    bool clearFailureMessage = false,
  }) {
    return PlatformQrSessionState(
      status: status ?? this.status,
      loginKey: loginKey ?? this.loginKey,
      qrBytes: clearQrBytes ? null : (qrBytes ?? this.qrBytes),
      unknownStatus:
          clearUnknownStatus ? null : (unknownStatus ?? this.unknownStatus),
      failureMessage:
          clearFailureMessage ? null : (failureMessage ?? this.failureMessage),
      regenerating: regenerating ?? this.regenerating,
    );
  }
}

final platformQrSessionProvider =
    NotifierProvider<PlatformQrSessionController, PlatformQrSessionState>(
      PlatformQrSessionController.new,
    );

/// 扫码确认成功后的刷新动作。
///
/// 独立成 provider 有两个作用：把二维码会话控制器与音乐中心控制器解耦；
/// 让"确认后必须触发平台变更刷新"这一副作用可被单测直接断言。
final platformQrLoginRefreshProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref
        .read(musicCenterControllerProvider.notifier)
        .refreshAfterPlatformChange();
  };
});

/// 管理网易云二维码登录会话的申请与轮询。
///
/// 轮询属于 `AGENTS.md` 要求由 application 层持有的长流程：状态机与定时器都在此，
/// Widget 只负责发起命令与展示状态。这样面板被关闭或重建都不会把轮询留在 Widget
/// 生命周期里，也便于用单测覆盖退避、去重与中断。
class PlatformQrSessionController extends Notifier<PlatformQrSessionState> {
  /// 单次授权会话的最长轮询时长。
  static const Duration maximumPollingDuration = Duration(minutes: 3);

  /// 连续失败上限，超过后停止轮询并提示重试。
  static const int maximumConsecutiveFailures = 5;

  bool _cancelled = true;
  bool _loopActive = false;
  bool _completed = false;
  int _consecutiveFailures = 0;

  @override
  PlatformQrSessionState build() {
    // 换号时按依赖变化重建：二维码会话属于当前账号，不能跨账号残留。
    ref.watch(sessionEpochProvider);
    ref.onDispose(() => _cancelled = true);
    return const PlatformQrSessionState();
  }

  /// 发起或续用二维码登录会话。
  ///
  /// 已有未过期会话时只恢复轮询，不重新申请——面板关闭再打开不应浪费一次会话，
  /// 用户手上可能还拿着同一张二维码。
  Future<void> start() async {
    if (_loopActive) {
      return;
    }
    _cancelled = false;
    _completed = false;
    final existingKey = state.loginKey;
    if (existingKey != null && state.hasQrImage && !state.canRegenerate) {
      _consecutiveFailures = 0;
      unawaited(_runPolling(existingKey));
      return;
    }
    final created = await _requestSession(regenerating: false);
    if (!created || _cancelled) {
      return;
    }
    final key = state.loginKey;
    if (key != null) {
      unawaited(_runPolling(key));
    }
  }

  /// 二维码过期或失败后就地换码。
  Future<void> regenerate() async {
    if (state.regenerating || _completed) {
      return;
    }
    _cancelled = false;
    final requested = await _requestSession(regenerating: true);
    if (!requested || _cancelled) {
      return;
    }
    final key = state.loginKey;
    if (key != null) {
      unawaited(_runPolling(key));
    }
  }

  /// 停止轮询但保留会话状态，便于面板重新打开后续用。
  void cancel() {
    _cancelled = true;
  }

  /// 恢复为初始状态。
  void reset() {
    _cancelled = true;
    _completed = false;
    _consecutiveFailures = 0;
    state = const PlatformQrSessionState();
  }

  Future<bool> _requestSession({required bool regenerating}) async {
    state = state.copyWith(
      status: regenerating ? state.status : PlatformQrDisplayStatus.starting,
      regenerating: regenerating,
      clearUnknownStatus: true,
      clearFailureMessage: true,
    );
    try {
      final session = await ref.read(musicApiProvider).createNeteaseQrLogin();
      final bytes = _decodeQrBytes(session.qrImageBase64);
      state = PlatformQrSessionState(
        status: PlatformQrDisplayStatus.waiting,
        loginKey: session.loginKey,
        qrBytes: bytes,
      );
      _consecutiveFailures = 0;
      return true;
    } on Object catch (error) {
      state = state.copyWith(
        status: PlatformQrDisplayStatus.error,
        regenerating: false,
        failureMessage: describeUserFacingError(error).message,
      );
      return false;
    }
  }

  Future<void> _runPolling(String loginKey) async {
    if (_loopActive || _cancelled || _completed) {
      return;
    }
    _loopActive = true;
    final startedAt = DateTime.now();
    try {
      while (!_cancelled && !_completed) {
        if (DateTime.now().difference(startedAt) >= maximumPollingDuration) {
          _applyStatus(PlatformQrDisplayStatus.expired);
          return;
        }
        try {
          final status = await ref
              .read(musicApiProvider)
              .checkNeteaseQrLogin(loginKey);
          if (_cancelled || _completed) {
            return;
          }
          _consecutiveFailures = 0;
          switch (status.status) {
            case 'pending':
              _applyStatus(PlatformQrDisplayStatus.waiting);
            case 'scanned':
              _applyStatus(PlatformQrDisplayStatus.scanned);
            case 'confirmed':
              _completed = true;
              state = state.copyWith(
                status: PlatformQrDisplayStatus.waiting,
                regenerating: false,
              );
              await _refreshAfterLogin();
              return;
            case 'expired':
              _applyStatus(PlatformQrDisplayStatus.expired);
              return;
            default:
              _applyStatus(
                PlatformQrDisplayStatus.unknown,
                unknownStatus: status.status,
              );
          }
        } on Object catch (error) {
          if (_cancelled) {
            return;
          }
          _consecutiveFailures++;
          _applyStatus(
            PlatformQrDisplayStatus.error,
            failureMessage: describeUserFacingError(error).message,
          );
          if (_consecutiveFailures >= maximumConsecutiveFailures) {
            return;
          }
        }
        final seconds = switch (_consecutiveFailures) {
          0 => 2,
          1 => 3,
          2 => 6,
          _ => 12,
        };
        await Future<void>.delayed(Duration(seconds: seconds));
      }
    } finally {
      _loopActive = false;
    }
  }

  /// 仅在状态真正变化时写状态，避免同一状态反复通知引起整棵面板重建。
  void _applyStatus(
    PlatformQrDisplayStatus status, {
    String? unknownStatus,
    String? failureMessage,
  }) {
    if (state.status == status &&
        unknownStatus == state.unknownStatus &&
        failureMessage == null) {
      return;
    }
    state = state.copyWith(
      status: status,
      unknownStatus: unknownStatus,
      failureMessage: failureMessage,
      regenerating: false,
      clearUnknownStatus: unknownStatus == null,
    );
  }

  /// 登录确认后的刷新在 application 层完成：不依赖面板是否仍然存在。
  Future<void> _refreshAfterLogin() async {
    try {
      await ref.read(platformQrLoginRefreshProvider)();
    } on Object {
      // 刷新失败不影响"已登录"这一事实，账号资料可下次进入时再回源。
    }
  }

  static Uint8List? _decodeQrBytes(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final base64Str = raw.contains(',') ? raw.split(',').last : raw;
      return base64Decode(base64Str);
    } on FormatException {
      return null;
    }
  }
}
