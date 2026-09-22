import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';

/// 平台账号窗口的共用控件。
///
/// 抽出的目的是让扫码 / 手机号密码 / 手机号验证码 / 邮箱四条登录路径在字段高度、
/// 间距、圆角与四态（静置、聚焦、禁用、错误）上完全一致，避免各路径各自组装出
/// 不同观感。颜色只从窗口专用色阶取值（`windowCard` / `fieldFill` / `fieldBorder`），
/// 不再落到 Material 默认的禁用态色，避免浅色下出现灰底灰字的割裂感。

/// 控件统一高度，保证同排字段与按钮在同一水平线上。
const double kMusicPlatformControlHeight = 44;

/// 字段组内间距与区块间距，四条路径共用。
const double kMusicPlatformFieldGap = 12;
const double kMusicPlatformBlockGap = 16;

/// 账号窗口内的卡片容器。
class MusicPlatformCard extends StatelessWidget {
  const MusicPlatformCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.windowCard,
        borderRadius: BorderRadius.circular(colors.cardBorderRadius),
        border: Border.all(color: colors.fieldBorder.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: AppTypography.titleMedium,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: kMusicPlatformBlockGap),
          child,
        ],
      ),
    );
  }
}

/// 账号窗口内统一的文本输入框：顶部标签 + 实体填充 + 四态描边。
class MusicPlatformField extends StatelessWidget {
  const MusicPlatformField({
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.errorText,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.maxLength,
    this.prefixText,
    this.suffix,
    this.textInputAction,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final String? errorText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final int? maxLength;
  final String? prefixText;
  final Widget? suffix;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final hasError = errorText != null;
    final idleBorderColor =
        hasError
            ? colors.danger
            : enabled
            ? colors.fieldBorder
            : colors.fieldBorder.withValues(alpha: 0.5);
    final idleBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: idleBorderColor, width: hasError ? 1.2 : 1),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: AppTypography.bodySmall,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: kMusicPlatformControlHeight,
          child: TextField(
            controller: controller,
            enabled: enabled,
            obscureText: obscureText,
            keyboardType: keyboardType,
            maxLength: maxLength,
            onSubmitted: onSubmitted,
            textInputAction: textInputAction,
            style: TextStyle(
              color:
                  enabled
                      ? colors.onSurface
                      : colors.onSurface.withValues(alpha: 0.55),
              fontSize: AppTypography.bodyMedium,
            ),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: hint,
              prefixText: prefixText,
              prefixStyle: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: AppTypography.bodyMedium,
              ),
              hintStyle: TextStyle(
                color: colors.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              filled: true,
              fillColor:
                  enabled
                      ? colors.fieldFill
                      : colors.fieldFill.withValues(alpha: 0.6),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: idleBorder,
              enabledBorder: idleBorder,
              disabledBorder: idleBorder,
              focusedBorder: idleBorder.copyWith(
                borderSide: BorderSide(color: colors.primary, width: 1.4),
              ),
              errorBorder: idleBorder.copyWith(
                borderSide: BorderSide(color: colors.danger, width: 1.2),
              ),
              focusedErrorBorder: idleBorder.copyWith(
                borderSide: BorderSide(color: colors.danger, width: 1.4),
              ),
              errorStyle: TextStyle(
                color: colors.danger,
                fontSize: AppTypography.bodySmall,
              ),
              suffixIcon: suffix,
              suffixIconColor: colors.onSurfaceVariant,
              suffixIconConstraints: const BoxConstraints(minWidth: 40),
            ),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 6),
          Text(
            helper!,
            style: TextStyle(
              color: colors.onSurfaceVariant.withValues(alpha: 0.8),
              fontSize: AppTypography.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

/// 账号窗口内的主操作按钮：加载态保持品牌色系，而不是落成 Material 默认灰。
class MusicPlatformPrimaryButton extends StatelessWidget {
  const MusicPlatformPrimaryButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
    super.key,
  });

  final Color color;
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || busy;
    return SizedBox(
      width: double.infinity,
      height: kMusicPlatformControlHeight,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          // 禁用态显式指定品牌色降透明，避免落到 Material 默认灰底灰字。
          disabledBackgroundColor: color.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: disabled ? null : onPressed,
        icon:
            busy
                ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: AppTypography.bodyLarge,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 账号窗口内的次级操作按钮：描边形态，与主按钮共用高度与圆角。
class MusicPlatformSecondaryButton extends StatelessWidget {
  const MusicPlatformSecondaryButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    return SizedBox(
      width: double.infinity,
      height: kMusicPlatformControlHeight,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.onSurface,
          disabledForegroundColor: colors.onSurfaceVariant.withValues(
            alpha: 0.6,
          ),
          side: BorderSide(color: colors.fieldBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: busy ? null : onPressed,
        icon:
            busy
                ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.onSurfaceVariant,
                  ),
                )
                : Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: AppTypography.bodyLarge,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 破坏性操作的二次确认对话框。
///
/// 不使用裸 `AlertDialog`：默认对话框主题在浅色 + 深色壁纸场景下取深色底、
/// 在浅色实体场景取浅色底，与账号窗口叠放时观感割裂且排版局促。这里用与账号
/// 窗口同一份色阶（`windowCard` / `fieldBorder`）自绘容器，保证叠放一致。
Future<bool> showMusicPlatformConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final colors = context.musicColors;
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.windowCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.fieldBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.danger.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.logout_rounded,
                        color: colors.danger,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          title,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: AppTypography.titleMedium,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: AppTypography.bodyMedium,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(
                        cancelLabel,
                        style: const TextStyle(
                          fontSize: AppTypography.bodyMedium,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.danger,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text(
                        confirmLabel,
                        style: const TextStyle(
                          fontSize: AppTypography.bodyMedium,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
  );
  return confirmed == true;
}
