import 'package:flutter/material.dart';

import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';

/// 样例 `.route-err`（`reader.css:62`）：居中的一段说明 + 一颗「再试一次」。
///
/// `display:grid; gap:12; place-content:center; justify-items:center;
/// min-height:40vh`，按钮 `padding 8/16 · r10 · bg raise2 · color text` ——
/// 对应 [DesktopButtonVariant.soft]。桌面不用移动端的 `AppErrorView`：
/// 那一版走 `FilledButton`，实底强调色在这套皮肤里是主操作，不是错误动作。
class DesktopErrorView extends StatelessWidget {
  const DesktopErrorView({
    required this.message,
    this.onRetry,
    this.onBack,
    this.retryLabel,
    this.minHeightFactor = 0.4,
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  /// 重试按钮文案；样例 `.route-err` 用的是 “Try again”，与通用 `coreRetry`
  /// 的 “Retry” 不同，崩溃边界因此单独传入。
  final String? retryLabel;

  /// `min-height:40vh`；整页占位（如路由崩溃边界）可调大。
  final double minHeightFactor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: MediaQuery.sizeOf(context).height * minHeightFactor,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: DesktopType.medium(
                  skin.text2,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (onRetry != null || onBack != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  if (onBack != null)
                    DesktopButton(
                      label: l10n.coreBack,
                      variant: DesktopButtonVariant.ghost,
                      onPressed: onBack,
                    ),
                  if (onRetry != null)
                    DesktopButton(
                      label: retryLabel ?? l10n.coreRetry,
                      variant: DesktopButtonVariant.soft,
                      onPressed: onRetry,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
