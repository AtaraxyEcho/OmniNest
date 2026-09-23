import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/preferences/preference_snapshot.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:shared_preferences/shared_preferences.dart';

const musicVisualizerPreferenceScope = 'music.player.visual.v1';

/// 播放器视觉偏好。冷启动会先用本地缓存发布首帧值，因此 `provider.future`
/// 只代表首个已发布值，不代表远端已确认。
final musicVisualizerPreferencesProvider = AsyncNotifierProvider<
  MusicVisualizerPreferencesNotifier,
  PortalMusicVisualizerPreferences
>(MusicVisualizerPreferencesNotifier.new);

class MusicVisualizerPreferencesNotifier
    extends AsyncNotifier<PortalMusicVisualizerPreferences> {
  static const _legacyScope = 'portal.music_visualizer';
  static const _legacyLocalKey = 'music_player_visual_v1';
  static const _olderLegacyLocalKey = 'portal_music_visualizer_preferences';

  /// 冷启动首帧缓存：单键自带归属 userId 与远端 version，读取不依赖会话恢复。
  static const _localCacheKey = 'music_player_visual_v1_cache';

  String? _userId;
  PortalMusicVisualizerPreferences? _published;
  int? _publishedVersion;

  @override
  Future<PortalMusicVisualizerPreferences> build() async {
    final cached = await _loadCached();
    final local = await _loadLegacyLocal();
    if (cached != null) {
      // 缓存命中即先出图，避免首帧画成默认布局后再整舞台重排；账号不符时
      // 这份快照会在会话就绪后被作废，改由远端结果接管。
      _published = cached.preferences;
      _publishedVersion = cached.version;
      state = AsyncData(cached.preferences);
    }
    final session = await ref.watch(authSessionProvider.future);
    final userId = session.user?.id;
    _userId = userId;
    if (userId == null) {
      return _published ?? local;
    }
    if (cached != null && cached.userId != userId) {
      _published = null;
      _publishedVersion = null;
    }
    final service = ref.read(preferenceSyncServiceProvider);
    var snapshot = await service.load(
      userId: userId,
      scope: musicVisualizerPreferenceScope,
    );
    if (snapshot.preferences.isEmpty) {
      final legacySnapshot = await service.load(
        userId: userId,
        scope: _legacyScope,
      );
      final migrated =
          legacySnapshot.preferences.isEmpty
              ? local
              : PortalMusicVisualizerPreferences.fromJson(
                legacySnapshot.preferences,
              );
      snapshot = await service.patch(
        userId: userId,
        scope: musicVisualizerPreferenceScope,
        changes: migrated.toJson(),
      );
      if (legacySnapshot.version != null) {
        await service.delete(userId: userId, scope: _legacyScope);
      }
    }
    await _clearLegacyLocal();
    return _adopt(snapshot, publish: false);
  }

  Future<void> saveVisual(PortalMusicVisualizerSettings visual) async {
    final current =
        state.asData?.value ?? const PortalMusicVisualizerPreferences();
    await _save(current.copyWith(visual: visual));
  }

  Future<void> restoreDefaults() async {
    await _save(const PortalMusicVisualizerPreferences());
  }

  /// 从远端重新同步播放器视觉偏好，并保留本地待提交变更。
  Future<void> refreshFromRemote() async {
    final userId = _userId;
    if (userId == null) return;
    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .synchronize(userId: userId, scope: musicVisualizerPreferenceScope);
    if (_userId != userId) return;
    await _adopt(snapshot, publish: true);
  }

  Future<void> _save(PortalMusicVisualizerPreferences preferences) async {
    _published = preferences;
    _publishedVersion = null;
    state = AsyncData(preferences);
    final userId = _userId;
    if (userId == null) {
      return;
    }
    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .patch(
          userId: userId,
          scope: musicVisualizerPreferenceScope,
          changes: preferences.toJson(),
        );
    await _adopt(snapshot, publish: true);
  }

  /// 采用远端快照。版本未变说明内容与已发布档位同源，直接复用旧实例，
  /// 让发布短路；内容变化时解析新值、回写首帧缓存。
  Future<PortalMusicVisualizerPreferences> _adopt(
    PreferenceSnapshot snapshot, {
    required bool publish,
  }) async {
    final version = snapshot.version;
    final published = _published;
    if (published != null && version != null && version == _publishedVersion) {
      return published;
    }
    final preferences = PortalMusicVisualizerPreferences.fromJson(
      snapshot.preferences,
    );
    _published = preferences;
    _publishedVersion = version;
    if (publish) {
      state = AsyncData(preferences);
    }
    await _writeCached(preferences, version: version);
    return preferences;
  }

  Future<_CachedVisualPreferences?> _loadCached() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_localCacheKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final json = Map<String, dynamic>.from(decoded);
      final userId = json['userId'];
      final payload = json['preferences'];
      if (userId is! String || payload is! Map) {
        return null;
      }
      return _CachedVisualPreferences(
        userId: userId,
        version: (json['version'] as num?)?.toInt(),
        preferences: PortalMusicVisualizerPreferences.fromJson(
          Map<String, dynamic>.from(payload),
        ),
      );
    } on FormatException {
      await preferences.remove(_localCacheKey);
      return null;
    }
  }

  Future<void> _writeCached(
    PortalMusicVisualizerPreferences preferences, {
    required int? version,
  }) async {
    final userId = _userId;
    if (userId == null) {
      return;
    }
    final store = await SharedPreferences.getInstance();
    await store.setString(
      _localCacheKey,
      jsonEncode(<String, Object?>{
        'userId': userId,
        'version': version,
        'preferences': preferences.toJson(),
      }),
    );
  }

  Future<PortalMusicVisualizerPreferences> _loadLegacyLocal() async {
    final preferences = await SharedPreferences.getInstance();
    final raw =
        preferences.getString(_legacyLocalKey) ??
        preferences.getString(_olderLegacyLocalKey);
    if (raw == null || raw.isEmpty) {
      return const PortalMusicVisualizerPreferences();
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? PortalMusicVisualizerPreferences.fromJson(decoded)
          : const PortalMusicVisualizerPreferences();
    } on FormatException {
      return const PortalMusicVisualizerPreferences();
    }
  }

  Future<void> _clearLegacyLocal() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_legacyLocalKey);
    await preferences.remove(_olderLegacyLocalKey);
  }
}

/// 首帧缓存条目：记录归属账号与对应的远端版本，供跨账号校验和发布短路使用。
class _CachedVisualPreferences {
  const _CachedVisualPreferences({
    required this.userId,
    required this.version,
    required this.preferences,
  });

  final String userId;
  final int? version;
  final PortalMusicVisualizerPreferences preferences;
}
