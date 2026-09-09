import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Web 平台的背景视频视图。
/// 基于原生 HTML video 元素(平台视图):强制 muted + autoplay + loop + playsinline
/// 以满足浏览器自动播放策略;BoxFit 映射为 CSS object-fit。
/// 播放失败时切换到备用地址(内置壁纸),仍失败则收敛为空视图避免白屏。
class AppBackdropVideoView extends StatefulWidget {
  const AppBackdropVideoView({
    required this.source,
    required this.fit,
    required this.playing,
    required this.muted,
    this.fallbackSource,
    this.onSourceStale,
    super.key,
  });

  /// 服务端签名 URL 或内置资产的 Flutter 资产地址。
  final String source;
  final BoxFit fit;
  final bool playing;
  final bool muted;

  /// 播放失败时的备用地址(通常为内置壁纸资产 URL)。
  final String? fallbackSource;

  /// 主源打开失败时通知上层签名 URL 可能过期。
  final VoidCallback? onSourceStale;

  @override
  State<AppBackdropVideoView> createState() => _AppBackdropVideoViewState();
}

class _AppBackdropVideoViewState extends State<AppBackdropVideoView> {
  web.HTMLVideoElement? _element;
  String? _appliedSource;
  bool _failed = false;
  Timer? _retryTimer;
  int _attempts = 0;

  static const int _maxAttempts = 2;

  void _onElementCreated(Object element) {
    _element = element as web.HTMLVideoElement;
    final el = _element!;
    el.style.width = '100%';
    el.style.height = '100%';
    el.style.display = 'block';
    el.style.objectFit = _objectFit(widget.fit);
    el.muted = true;
    el.autoplay = true;
    el.loop = true;
    el.playsInline = true;
    el.setAttribute('playsinline', '');
    el.preload = 'auto';
    el.addEventListener('error', _handleError.toJS);
    el.addEventListener('loadeddata', _handleReady.toJS);
    _applySource();
  }

  @override
  void didUpdateWidget(AppBackdropVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fit != widget.fit) {
      _element?.style.objectFit = _objectFit(widget.fit);
    }
    _applySource();
  }

  void _applySource() {
    final el = _element;
    if (el == null || _failed) {
      return;
    }
    if (_appliedSource == widget.source) {
      _syncPlayback(el);
      return;
    }
    _appliedSource = widget.source;
    el.src = widget.source;
    if (widget.playing) {
      _play(el);
    }
  }

  void _syncPlayback(web.HTMLVideoElement el) {
    if (widget.playing) {
      _play(el);
    } else {
      el.pause();
    }
  }

  void _play(web.HTMLVideoElement el) {
    el.play().toDart.then((_) {}, onError: (Object _) {});
  }

  void _handleReady(web.Event event) {
    _attempts = 0;
  }

  void _handleError(web.Event event) {
    final fallback = widget.fallbackSource;
    if (_appliedSource != null &&
        fallback != null &&
        _appliedSource != fallback) {
      debugPrint('背景视频播放失败,回退内置壁纸');
      widget.onSourceStale?.call();
      _appliedSource = fallback;
      final el = _element;
      if (el != null) {
        el.src = fallback;
        _play(el);
      }
      return;
    }
    if ((_appliedSource ?? '').startsWith('http')) {
      widget.onSourceStale?.call();
    }
    _attempts++;
    if (_attempts <= _maxAttempts) {
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 2), () {
        final el = _element;
        if (el == null || _failed) {
          return;
        }
        el.src = _appliedSource ?? '';
        if (widget.playing) {
          _play(el);
        }
      });
      return;
    }
    if (!_failed) {
      setState(() => _failed = true);
      debugPrint('背景视频多次播放失败,收敛为空背景等待对账或用户操作');
    }
  }

  String _objectFit(BoxFit fit) {
    return fit == BoxFit.contain ? 'contain' : 'cover';
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    final el = _element;
    if (el != null) {
      el.pause();
      el.removeAttribute('src');
      el.load();
    }
    _element = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const SizedBox.shrink();
    }
    return SizedBox.expand(
      child: HtmlElementView.fromTagName(
        tagName: 'video',
        onElementCreated: _onElementCreated,
      ),
    );
  }
}
