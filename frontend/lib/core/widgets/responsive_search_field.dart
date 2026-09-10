import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/control_tokens.dart';

/// 各模块顶栏/筛选栏共用搜索框。
///
/// 尺寸、前后缀图标与填充色统一走 [AppControlTokens] 与主题，
/// 浅色模式下使用 surfaceContainerLow，避免纯白搜索框。
class ResponsiveSearchField extends StatelessWidget {
  const ResponsiveSearchField({
    required this.onChanged,
    this.controller,
    this.hintText,
    this.maxWidth,
    this.style,
    this.decoration,
    super.key,
  });

  final ValueChanged<String> onChanged;

  /// 可选外部控制器；不传时由输入框自行管理。
  final TextEditingController? controller;
  final String? hintText;

  /// 最大宽度；为空时取 [AppControlTokens.searchFieldWidth]。
  final double? maxWidth;
  final TextStyle? style;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth ?? AppControlTokens.searchFieldWidth,
        minHeight: AppControlTokens.fieldHeight,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: style,
        decoration:
            decoration ??
            InputDecoration(
              isDense: true,
              filled: true,
              hintText: hintText ?? l10n.coreSearchHint,
              hintStyle: theme.inputDecorationTheme.hintStyle,
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              prefixIconConstraints: BoxConstraints(
                minWidth: AppControlTokens.fieldPrefixIconWidth,
                minHeight: 0,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  AppControlTokens.controlRadius,
                ),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppControlTokens.fieldHorizontalPadding,
                vertical: AppControlTokens.fieldVerticalPadding,
              ),
            ),
      ),
    );
  }
}
