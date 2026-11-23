import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 五大模块统一背景状态快照。
///
/// 集中承载影视轮播当前封面、照片最近查看 ID / 临时 URL、阅读最近打开书封与纸色兜底，
/// 供桌面壳层 `_AmbientLayer` 在 Home / Movies / Photos / Music / Reader 间
/// 统一解析环境光来源，避免跨页面直接耦合各自业务状态。
@immutable
class DesktopAmbientHints {
  const DesktopAmbientHints({
    this.moviesActiveUrl,
    this.photosLastViewedId,
    this.photosLastViewedUrl,
    this.readerLastOpenedUrl,
    this.readerFallbackTone,
  });

  static const Object _unset = Object();

  final String? moviesActiveUrl;
  final String? photosLastViewedId;
  final String? photosLastViewedUrl;
  final String? readerLastOpenedUrl;
  final Color? readerFallbackTone;

  DesktopAmbientHints copyWith({
    Object? moviesActiveUrl = _unset,
    Object? photosLastViewedId = _unset,
    Object? photosLastViewedUrl = _unset,
    Object? readerLastOpenedUrl = _unset,
    Object? readerFallbackTone = _unset,
  }) {
    return DesktopAmbientHints(
      moviesActiveUrl:
          identical(moviesActiveUrl, _unset)
              ? this.moviesActiveUrl
              : moviesActiveUrl as String?,
      photosLastViewedId:
          identical(photosLastViewedId, _unset)
              ? this.photosLastViewedId
              : photosLastViewedId as String?,
      photosLastViewedUrl:
          identical(photosLastViewedUrl, _unset)
              ? this.photosLastViewedUrl
              : photosLastViewedUrl as String?,
      readerLastOpenedUrl:
          identical(readerLastOpenedUrl, _unset)
              ? this.readerLastOpenedUrl
              : readerLastOpenedUrl as String?,
      readerFallbackTone:
          identical(readerFallbackTone, _unset)
              ? this.readerFallbackTone
              : readerFallbackTone as Color?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DesktopAmbientHints &&
        other.moviesActiveUrl == moviesActiveUrl &&
        other.photosLastViewedId == photosLastViewedId &&
        other.photosLastViewedUrl == photosLastViewedUrl &&
        other.readerLastOpenedUrl == readerLastOpenedUrl &&
        other.readerFallbackTone == readerFallbackTone;
  }

  @override
  int get hashCode => Object.hash(
    moviesActiveUrl,
    photosLastViewedId,
    photosLastViewedUrl,
    readerLastOpenedUrl,
    readerFallbackTone,
  );
}

/// 兼容别名：供跨模块统一引用桌面环境光提示 Notifier。
typedef DesktopAmbientHintsNotifier = DesktopAmbientHintController;

final desktopAmbientHintProvider =
    NotifierProvider<DesktopAmbientHintController, DesktopAmbientHints>(
      DesktopAmbientHintController.new,
    );

/// 桌面环境光统一状态总线控制器。
///
/// - `moviesActiveUrl` 仅驻留内存，随影院轮播与影视详情页实时同步；
/// - `photosLastViewedId` 经 300ms 防抖后持久化至 `omninest.desktop.ambient.photos.id`；
/// - `photosLastViewedUrl` 仅作为内存兼容兜底，不再持久化短期预签名 URL 以防 403 死锁；
/// - `readerLastOpenedUrl` / `readerFallbackTone` 持久化至 `omninest.desktop.ambient.reader`；
/// - 初始化时异步加载持久化记录，且绝不覆盖加载完成前已写入的新状态。
class DesktopAmbientHintController extends Notifier<DesktopAmbientHints> {
  static const String _photosIdPrefsKey = 'omninest.desktop.ambient.photos.id';
  static const String _photosPrefsKey = 'omninest.desktop.ambient.photos';
  static const String _readerPrefsKey = 'omninest.desktop.ambient.reader';
  static const Duration _photosPersistDebounce = Duration(milliseconds: 300);

  bool _loaded = false;
  bool _disposed = false;
  bool _photosDirty = false;
  bool _readerDirty = false;
  Timer? _photosDebounce;

  @override
  DesktopAmbientHints build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _photosDebounce?.cancel();
      _photosDebounce = null;
    });
    if (!_loaded) {
      unawaited(_loadPersisted());
    }
    return const DesktopAmbientHints();
  }

  static String? _normalize(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Future<void> _loadPersisted() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) {
        return;
      }
      final savedPhotoId = _normalize(prefs.getString(_photosIdPrefsKey));
      // 清理旧版本落盘的短期预签名 URL，防止过期 403 屏蔽鲜活首图。
      if (prefs.containsKey(_photosPrefsKey)) {
        unawaited(prefs.remove(_photosPrefsKey));
      }
      String? savedReaderUrl;
      Color? savedReaderTone;
      final rawReader = prefs.getString(_readerPrefsKey);
      if (rawReader != null && rawReader.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawReader);
          if (decoded is Map<String, dynamic>) {
            savedReaderUrl = _normalize(decoded['url'] as String?);
            final toneValue = decoded['tone'];
            if (toneValue is int) {
              savedReaderTone = Color(toneValue);
            }
          } else if (decoded is String) {
            savedReaderUrl = _normalize(decoded);
          }
        } on Object {
          savedReaderUrl = _normalize(rawReader);
        }
      }

      if (_disposed) {
        return;
      }
      var next = state;
      if (!_photosDirty && savedPhotoId != null) {
        next = next.copyWith(photosLastViewedId: savedPhotoId);
      }
      if (!_readerDirty &&
          (savedReaderUrl != null || savedReaderTone != null)) {
        next = next.copyWith(
          readerLastOpenedUrl: savedReaderUrl,
          readerFallbackTone: savedReaderTone,
        );
      }
      if (next != state) {
        state = next;
      }
    } on Object {
      // 无本地存储环境（如部分单测）静默降级为纯内存态。
    }
  }

  /// 更新影视影院轮播与详情页当前活跃封面（仅内存态）。
  void setMoviesCover(String? url) {
    final normalized = _normalize(url);
    if (state.moviesActiveUrl == normalized) {
      return;
    }
    state = state.copyWith(moviesActiveUrl: normalized);
  }

  /// 记录最近查看的照片稳定 ID，并在 300ms 防抖后持久化至 `SharedPreferences`。
  void rememberPhotoId(String? photoId) {
    final normalized = _normalize(photoId);
    _photosDirty = true;
    if (state.photosLastViewedId != normalized ||
        (normalized == null && state.photosLastViewedUrl != null)) {
      state = state.copyWith(
        photosLastViewedId: normalized,
        photosLastViewedUrl:
            normalized == null ? null : state.photosLastViewedUrl,
      );
    }
    _photosDebounce?.cancel();
    _photosDebounce = Timer(_photosPersistDebounce, () {
      if (_disposed) {
        return;
      }
      unawaited(_persistPhotoId(normalized));
    });
  }

  /// 清空照片背景记忆（ID 与临时 URL）并立即移除持久化键值。
  void clearPhotoHint() {
    _photosDirty = true;
    _photosDebounce?.cancel();
    _photosDebounce = null;
    if (state.photosLastViewedId != null || state.photosLastViewedUrl != null) {
      state = state.copyWith(
        photosLastViewedId: null,
        photosLastViewedUrl: null,
      );
    }
    unawaited(_persistPhotoId(null));
  }

  /// 兼容旧调用签名：记录内存中的临时照片 URL（不再落盘短期预签名 URL）。
  void rememberPhoto(String? url) => rememberPhotoViewed(url);

  /// 记录最近查看的照片临时封面 URL（仅内存兜底，不持久化预签名 URL）。
  void rememberPhotoViewed(String? url) {
    final normalized = _normalize(url);
    _photosDirty = true;
    if (state.photosLastViewedUrl != normalized) {
      state = state.copyWith(photosLastViewedUrl: normalized);
    }
  }

  /// 若当前记忆的照片封面与被删除/失效 URL 匹配，则立即清除。
  void clearPhotoViewedIfMatches(String url) {
    final normalized = _normalize(url);
    if (normalized == null || state.photosLastViewedUrl != normalized) {
      return;
    }
    _photosDirty = true;
    state = state.copyWith(photosLastViewedUrl: null);
  }

  /// 记录最近打开的图书封面与纸色兜底，并持久化至 `omninest.desktop.ambient.reader`。
  void rememberReaderBook(String? coverUrl, Color? fallbackTone) {
    final normalized = _normalize(coverUrl);
    _readerDirty = true;
    if (state.readerLastOpenedUrl == normalized &&
        state.readerFallbackTone == fallbackTone) {
      return;
    }
    state = state.copyWith(
      readerLastOpenedUrl: normalized,
      readerFallbackTone: fallbackTone,
    );
    unawaited(_persistReaderBook(normalized, fallbackTone));
  }

  Future<void> _persistPhotoId(String? photoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_photosPrefsKey)) {
        await prefs.remove(_photosPrefsKey);
      }
      if (photoId == null) {
        await prefs.remove(_photosIdPrefsKey);
      } else {
        await prefs.setString(_photosIdPrefsKey, photoId);
      }
    } on Object {
      // 忽略存储不可用异常。
    }
  }

  Future<void> _persistReaderBook(String? url, Color? fallbackTone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (url == null && fallbackTone == null) {
        await prefs.remove(_readerPrefsKey);
      } else {
        final payload = jsonEncode(<String, Object?>{
          'url': url,
          'tone': fallbackTone?.toARGB32(),
        });
        await prefs.setString(_readerPrefsKey, payload);
      }
    } on Object {
      // 忽略存储不可用异常。
    }
  }
}
