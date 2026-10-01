import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/realtime/realtime_scope_handler.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_history_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';

/// 音乐作用域实时失效刷新处理器。
class MusicSyncHandler implements RealtimeScopeHandler {
  MusicSyncHandler(this.ref);

  final Ref ref;
  final RealtimeRevisionTracker _auxiliaryRevisions = RealtimeRevisionTracker();

  /// 播放历史事件不重拉曲库——重拉会更换封面签名 URL，导致封面卡重载闪烁；
  /// 历史页改走读时重解析的稳定封面端点，可安全单独刷新。
  static const String _playHistoryResourceType = 'MUSIC_PLAY_HISTORY';

  /// 平台账号变更事件：凭据保存/清除已在后端整体失效回源缓存，本地重建即可
  /// 命中预热或回源一次；强制刷新会把缓存再失效一遍，扫码确认后等于全量回源两遍。
  static const String _platformLibraryResourceType = 'MUSIC_PLATFORM';

  @override
  RealtimeScope get scope => RealtimeScope.music;

  @override
  bool appliesTo(RealtimeInvalidation invalidation) => true;

  @override
  Future<bool> refresh(List<RealtimeInvalidation> invalidations) async {
    final auxiliary = _auxiliaryRevisions.pending(invalidations);
    if (_isPlayHistoryOnly(auxiliary)) {
      if (ref.exists(musicHistoryControllerProvider)) {
        final _ = await ref.refresh(musicHistoryControllerProvider.future);
      }
      if (ref.exists(musicCenterControllerProvider)) {
        await ref.read(musicCenterControllerProvider.future);
      }
      _auxiliaryRevisions.clear(invalidations);
      return true;
    }
    if (auxiliary.isNotEmpty && ref.exists(musicDashboardProvider)) {
      final _ = await ref.refresh(musicDashboardProvider.future);
    }
    if (auxiliary.isNotEmpty && ref.exists(musicPlatformLibraryProvider)) {
      if (_isPlatformChangeOnly(auxiliary)) {
        ref.invalidate(musicPlatformLibraryProvider);
        await ref.read(musicPlatformLibraryProvider.future);
      } else {
        await ref.read(musicPlatformLibraryProvider.future);
        await ref
            .read(musicPlatformLibraryProvider.notifier)
            .refreshForRealtime();
      }
    }
    _auxiliaryRevisions.markCompleted(auxiliary);
    // 音乐模块未激活时直接消费失效记录，首次打开自取最新。
    if (!ref.exists(musicCenterControllerProvider)) return true;
    await ref.read(musicCenterControllerProvider.future);
    await ref.read(musicCenterControllerProvider.notifier).refreshForRealtime();
    _auxiliaryRevisions.clear(invalidations);
    return true;
  }

  bool _isPlayHistoryOnly(List<RealtimeInvalidation> invalidations) {
    return invalidations.isNotEmpty &&
        invalidations.every(
          (invalidation) =>
              invalidation.resourceType == _playHistoryResourceType,
        );
  }

  /// 本批失效是否全部来自平台账号变更（登录确认/断开）。混合批次保持既有
  /// 强刷路径，避免曲库扫描等事件被降级成缓存优先。
  bool _isPlatformChangeOnly(List<RealtimeInvalidation> invalidations) {
    return invalidations.isNotEmpty &&
        invalidations.every(
          (invalidation) =>
              invalidation.resourceType == _platformLibraryResourceType,
        );
  }
}
