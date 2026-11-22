import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 五大模块统一背景状态快照。
///
/// 集中承载影视轮播当前封面、照片最近查看图、阅读最近打开书封与纸色兜底，
/// 供桌面壳层 `_AmbientLayer` 在 Home / Movies / Photos / Music / Reader 间
/// 统一解析环境光来源，避免跨页面直接耦合各自业务状态。
@immutable
class DesktopAmbientHints {
  const DesktopAmbientHints({
    this.moviesActiveUrl,
    this.photosLastViewedUrl,
    this.readerLastOpenedUrl,
    this.readerFallbackTone,
  });

  static const Object _unset = Object();

  final String? moviesActiveUrl;
  final String? photosLastViewedUrl;
  final String? readerLastOpenedUrl;
  final Color? readerFallbackTone;

  DesktopAmbientHints copyWith({
    Object? moviesActiveUrl = _unset,
    Object? photosLastViewedUrl = _unset,
    Object? readerLastOpenedUrl = _unset,
    Object? readerFallbackTone = _unset,
  }) {
    return DesktopAmbientHints(
      moviesActiveUrl:
          identical(moviesActiveUrl, _unset)
              ? this.moviesActiveUrl
              : moviesActiveUrl as String?,
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
        other.photosLastViewedUrl == photosLastViewedUrl &&
        other.readerLastOpenedUrl == readerLastOpenedUrl &&
        other.readerFallbackTone == readerFallbackTone;
  }

  @override
  int get hashCode => Object.hash(
    moviesActiveUrl,
    photosLastViewedUrl,
    readerLastOpenedUrl,
    readerFallbackTone,
  );
}

final desktopAmbientHintProvider =
    NotifierProvider<DesktopAmbientHintController, DesktopAmbientHints>(
      DesktopAmbientHintController.new,
    );

/// 桌面环境光统一状态总线控制器。
///
/// - `moviesActiveUrl` 仅驻留内存，随影院轮播实时同步；
/// - `photosLastViewedUrl` 经 300ms 防抖后持久化至 `omninest.desktop.ambient.photos`；
/// - `readerLastOpenedUrl` / `readerFallbackTone` 持久化至 `omninest.desktop.ambient.reader`；
/// - 初始化时异步加载持久化记录，且绝不覆盖加载完成前已写入的新状态。
class DesktopAmbientHintController extends Notifier<DesktopAmbientHints> {
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

  static String? _normalizeUrl(String? raw) {
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
      final savedPhoto = _normalizeUrl(prefs.getString(_photosPrefsKey));
      String? savedReaderUrl;
      Color? savedReaderTone;
      final rawReader = prefs.getString(_readerPrefsKey);
      if (rawReader != null && rawReader.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawReader);
          if (decoded is Map<String, dynamic>) {
            savedReaderUrl = _normalizeUrl(decoded['url'] as String?);
            final toneValue = decoded['tone'];
            if (toneValue is int) {
              savedReaderTone = Color(toneValue);
            }
          } else if (decoded is String) {
            savedReaderUrl = _normalizeUrl(decoded);
          }
        } on Object {
          savedReaderUrl = _normalizeUrl(rawReader);
        }
      }

      if (_disposed) {
        return;
      }
      var next = state;
      if (!_photosDirty && savedPhoto != null) {
        next = next.copyWith(photosLastViewedUrl: savedPhoto);
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

  /// 更新影视影院轮播当前活跃封面（仅内存态）。
  void setMoviesCover(String? url) {
    final normalized = _normalizeUrl(url);
    if (state.moviesActiveUrl == normalized) {
      return;
    }
    state = state.copyWith(moviesActiveUrl: normalized);
  }

  /// 记录最近查看的照片封面，并在 300ms 防抖后持久化。
  void rememberPhotoViewed(String? url) {
    final normalized = _normalizeUrl(url);
    _photosDirty = true;
    if (state.photosLastViewedUrl != normalized) {
      state = state.copyWith(photosLastViewedUrl: normalized);
    }
    _photosDebounce?.cancel();
    _photosDebounce = Timer(_photosPersistDebounce, () {
      if (_disposed) {
        return;
      }
      unawaited(_persistPhotoViewed(normalized));
    });
  }

  /// 若当前记忆的照片封面与被删除/失效 URL 匹配，则立即清除并落盘。
  void clearPhotoViewedIfMatches(String url) {
    final normalized = _normalizeUrl(url);
    if (normalized == null || state.photosLastViewedUrl != normalized) {
      return;
    }
    _photosDirty = true;
    _photosDebounce?.cancel();
    _photosDebounce = null;
    state = state.copyWith(photosLastViewedUrl: null);
    unawaited(_persistPhotoViewed(null));
  }

  /// 记录最近打开的图书封面与纸色兜底，并持久化至 `omninest.desktop.ambient.reader`。
  void rememberReaderBook(String? coverUrl, Color? fallbackTone) {
    final normalized = _normalizeUrl(coverUrl);
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

  Future<void> _persistPhotoViewed(String? url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (url == null) {
        await prefs.remove(_photosPrefsKey);
      } else {
        await prefs.setString(_photosPrefsKey, url);
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
