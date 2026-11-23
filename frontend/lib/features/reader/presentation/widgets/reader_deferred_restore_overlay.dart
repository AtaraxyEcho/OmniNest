import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 延迟显示阅读位置恢复遮罩，避免缓存命中时闪烁加载画面。
///
/// 延迟窗口内以不透明底色遮住内容：恢复定位期间内容尚未落在目标
/// 位置（页模式需重算分页、滚动模式在首帧渲染于章首），直接透出会
/// 闪现章首再跳到阅读位置；底色先行、加载指示延后，两端都不闪。
class ReaderDeferredRestoreOverlay extends StatefulWidget {
  const ReaderDeferredRestoreOverlay({
    required this.settings,
    this.visible = true,
    super.key,
  });

  final ReaderViewSettings settings;
  final bool visible;

  @override
  State<ReaderDeferredRestoreOverlay> createState() =>
      _ReaderDeferredRestoreOverlayState();
}

class _ReaderDeferredRestoreOverlayState
    extends State<ReaderDeferredRestoreOverlay> {
  Timer? _timer;
  bool _showIndicator = false;

  void _armIndicatorTimer() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 180), () {
      if (mounted && widget.visible) {
        setState(() => _showIndicator = true);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      _armIndicatorTimer();
    }
  }

  @override
  void didUpdateWidget(covariant ReaderDeferredRestoreOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.visible && widget.visible) {
      _showIndicator = false;
      _armIndicatorTimer();
    } else if (oldWidget.visible && !widget.visible) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animationsDisabled =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final settings = widget.settings;
    final content =
        !_showIndicator
            ? ColoredBox(
              key: const Key('readerRestoreCover'),
              color: settings.surfaceColor,
            )
            : ColoredBox(
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
    // 遮盖进入即时生效防止章首闪现，定位完成后 160ms 柔和淡出消除硬切闪烁。
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1.0 : 0.0,
        duration:
            animationsDisabled || widget.visible
                ? Duration.zero
                : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        alwaysIncludeSemantics: true,
        child: content,
      ),
    );
  }
}
