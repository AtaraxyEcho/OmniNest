import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/features/reader/application/reader_tts_speed_controller.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 阅读器 TTS 语音朗读控制栏。
class ReaderTtsControls extends ConsumerStatefulWidget {
  const ReaderTtsControls({required this.text, super.key});

  final String text;

  @override
  ConsumerState<ReaderTtsControls> createState() => _ReaderTtsControlsState();
}

class _ReaderTtsControlsState extends ConsumerState<ReaderTtsControls> {
  final FlutterTts _tts = FlutterTts();
  TtsState _state = TtsState.stopped;

  @override
  void initState() {
    super.initState();
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _state = TtsState.stopped);
    });
    _tts.setPauseHandler(() {
      if (mounted) setState(() => _state = TtsState.paused);
    });
    _tts.setContinueHandler(() {
      if (mounted) setState(() => _state = TtsState.playing);
    });
  }

  @override
  void didUpdateWidget(covariant ReaderTtsControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 朗读中章节切换：停止旧章朗读，从新章文本起点重新开始。
    if (widget.text != oldWidget.text && _state != TtsState.stopped) {
      unawaited(_restartForNewText());
    }
  }

  Future<void> _restartForNewText() async {
    try {
      await _tts.stop();
      if (!mounted) return;
      setState(() => _state = TtsState.stopped);
      final speed =
          ref.read(readerTtsSpeedControllerProvider).value ??
          ReaderTtsSpeedController.defaultSpeed;
      await _tts.setSpeechRate(speed);
      if (!mounted) return;
      await _tts.setLanguage(_detectLanguage(widget.text));
      if (!mounted) return;
      await _tts.speak(widget.text);
      if (mounted) setState(() => _state = TtsState.playing);
    } on Exception catch (e) {
      if (kDebugMode) readerDebugLog('TTS: restart failed: $e');
    }
  }

  /// 根据文本内容自动检测语言，中文返回 zh-CN，其他返回 en-US。
  String _detectLanguage(String text) {
    // 检测是否包含中文字符（CJK 统一汉字）
    final chinesePattern = RegExp(r'[一-鿿]');
    if (chinesePattern.hasMatch(text)) return 'zh-CN';
    return 'en-US';
  }

  Future<void> _toggle() async {
    if (!mounted) return;
    try {
      if (_state == TtsState.playing) {
        await _tts.pause();
        if (mounted) setState(() => _state = TtsState.paused);
      } else if (_state == TtsState.paused) {
        await _tts.setLanguage(_detectLanguage(widget.text));
        if (!mounted) return;
        await _tts.speak(widget.text);
        if (mounted) setState(() => _state = TtsState.playing);
      } else {
        final speed =
            ref.read(readerTtsSpeedControllerProvider).value ??
            ReaderTtsSpeedController.defaultSpeed;
        await _tts.setSpeechRate(speed);
        if (!mounted) return;
        await _tts.setLanguage(_detectLanguage(widget.text));
        if (!mounted) return;
        await _tts.speak(widget.text);
        if (mounted) setState(() => _state = TtsState.playing);
      }
    } on Exception catch (e) {
      if (kDebugMode) readerDebugLog('TTS: operation failed: $e');
    }
  }

  Future<void> _stop() async {
    try {
      await _tts.stop();
      if (mounted) setState(() => _state = TtsState.stopped);
    } on Exception catch (e) {
      if (kDebugMode) readerDebugLog('TTS: stop failed: $e');
    }
  }

  Future<void> _onSpeedChanged(double v) async {
    if (!mounted) return;
    await ref.read(readerTtsSpeedControllerProvider.notifier).setSpeed(v);
    if (!mounted) return;
    // 播放中实时生效
    if (_state == TtsState.playing) {
      try {
        await _tts.setSpeechRate(v);
      } on Exception catch (e) {
        if (kDebugMode) readerDebugLog('TTS: speed change failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final speed =
        ref.watch(readerTtsSpeedControllerProvider).value ??
        ReaderTtsSpeedController.defaultSpeed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.8),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(switch (_state) {
              TtsState.playing => Icons.pause_rounded,
              TtsState.paused => Icons.play_arrow_rounded,
              TtsState.stopped => Icons.play_arrow_rounded,
            }),
            tooltip: switch (_state) {
              TtsState.playing => AppLocalizations.of(context).readerTtsPause,
              _ => AppLocalizations.of(context).readerTtsPlay,
            },
            onPressed: widget.text.isEmpty ? null : _toggle,
          ),
          if (_state != TtsState.stopped)
            IconButton(
              icon: const Icon(Icons.stop_rounded),
              tooltip: AppLocalizations.of(context).readerTtsStop,
              onPressed: _stop,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: AppSlider(
              value: speed,
              min: 0.5,
              max: 2.0,
              divisions: 6,
              label: '${speed.toStringAsFixed(1)}x',
              onChanged: _onSpeedChanged,
            ),
          ),
          Text(
            '${speed.toStringAsFixed(1)}x',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // 清除回调，防止 dispose 后异步回调触发 setState
    _tts.setCompletionHandler(() {});
    _tts.setPauseHandler(() {});
    _tts.setContinueHandler(() {});
    // dispose 是同步方法，无法 await _tts.stop()。
    // 已通过上方清除回调来降低竞态影响；stop 的错误无处呈现，
    // dispose 期丢弃属预期。
    unawaited(_tts.stop());
    super.dispose();
  }
}

enum TtsState { playing, paused, stopped }
