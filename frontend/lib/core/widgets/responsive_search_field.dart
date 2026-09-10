import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/control_tokens.dart';

/// 响应式搜索框：最大宽度 [maxWidth]，窄屏时自动缩小。
class ResponsiveSearchField extends StatelessWidget {
  const ResponsiveSearchField({
    required this.onChanged,
    this.controller,
    this.hintText,
    this.maxWidth = 320,
    this.style,
    this.decoration,
    super.key,
  });

  final ValueChanged<String> onChanged;

  /// 可选外部控制器；不传时由输入框自行管理。
  final TextEditingController? controller;
  final String? hintText;
  final double maxWidth;
  final TextStyle? style;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
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
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
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
