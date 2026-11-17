import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

/// 将统一可播放对象解析为后端签发的播放计划。
class MusicPlaybackResolver {
  MusicPlaybackResolver(this._api, {String Function()? preferredOnlineQuality})
    : _preferredOnlineQuality = preferredOnlineQuality;

  final MusicApi _api;
  final String Function()? _preferredOnlineQuality;
  final Map<String, _CachedPlaybackPlan> _cache = {};
  final Map<String, Future<MusicPlaybackPlan>> _pending = {};

  String _cacheKey(MusicPlayableItem item) {
    final quality = switch (item.ref) {
      OnlineMusicRef() => _preferredOnlineQuality?.call() ?? 'exhigh',
      LocalMusicRef() => '',
    };
    return '${item.playableKey}|$quality';
  }

  /// 根据类型安全的来源引用请求对应播放计划。
  Future<MusicPlaybackPlan> resolve(MusicPlayableItem item) async {
    final key = _cacheKey(item);
    final cached = _cache[key];
    if (cached != null && cached.isUsable) {
      return cached.plan;
    }
    final pending = _pending[key];
    if (pending != null) {
      return pending;
    }
    final future = _resolveUncached(item);
    _pending[key] = future;
    try {
      final resolved = await future;
      _cache[key] = _CachedPlaybackPlan(resolved);
      return resolved;
    } finally {
      _pending.remove(key);
    }
  }

  /// 提前解析即将播放的曲目，失败时由真正播放请求统一处理。
  Future<void> prefetch(MusicPlayableItem item) async {
    try {
      await resolve(item);
    } on Object {
      return;
    }
  }

  Future<MusicPlaybackPlan> _resolveUncached(MusicPlayableItem item) async {
    final plan = switch (item.ref) {
      LocalMusicRef(:final trackId) => _api.playbackPlan(trackId),
      OnlineMusicRef(:final platform, :final songId) => _api.onlinePlaybackPlan(
        platform.apiValue,
        songId,

        quality: _preferredOnlineQuality?.call() ?? 'exhigh',
      ),
    };
    final resolved = await plan;
    return resolved.copyWith(
      trackId: item.track.id,
      durationSeconds: resolved.durationSeconds ?? item.track.durationSeconds,
    );
  }
}

class _CachedPlaybackPlan {
  _CachedPlaybackPlan(this.plan) : cachedAt = DateTime.now();

  final MusicPlaybackPlan plan;
  final DateTime cachedAt;

  bool get isUsable {
    final expiresAt = plan.expiresAt;
    if (expiresAt != null) {
      return DateTime.now().isBefore(
        expiresAt.subtract(const Duration(seconds: 15)),
      );
    }
    return DateTime.now().difference(cachedAt) < const Duration(minutes: 5);
  }
}
