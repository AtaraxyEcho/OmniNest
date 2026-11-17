import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 延迟显示阅读位置恢复遮罩，避免缓存命中时闪烁加载画面。
///
/// 延迟窗口内以不透明底色遮住内容：恢复定位期间内容尚未落在目标
/// 位置（页模式需重算分页、滚动模式在首帧渲染于章首），直接透出会
/// 闪现章首再跳到阅读位置；底色先行、加载指示延后，两端都不闪。
class ReaderDeferredRestoreOverlay extends StatefulWidget {
  const ReaderDeferredRestoreOverlay({required this.settings, super.key});

  final ReaderViewSettings settings;

  @override
  State<ReaderDeferredRestoreOverlay> createState() =>
      _ReaderDeferredRestoreOverlayState();
}

class _ReaderDeferredRestoreOverlayState
    extends State<ReaderDeferredRestoreOverlay> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return ColoredBox(
        key: const Key('readerRestoreCover'),
        color: widget.settings.surfaceColor,
      );
    }
    final settings = widget.settings;
    return ColoredBox(
      color: settings.surfaceColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: settings.accentColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).readerRestoringProgress,
              style: TextStyle(
                fontSize: AppTypography.bodyMedium,
                color: settings.onSurfaceColor.withValues(alpha: 0.64),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
