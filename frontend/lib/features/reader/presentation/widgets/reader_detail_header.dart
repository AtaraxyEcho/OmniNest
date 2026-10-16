import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';

/// 空间子页固定页头（样例 `.detail-header`：高 84、内衬
/// max(18px, safe-top) 14px 6px，左右各一枚 48 圆钮，中间单行标题 12/600）。
///
/// 状态栏避让沿用壳层既有约定（SafeArea 之外再给定高带）：样例的
/// `height:84` 是 border-box，浏览器 mock 里没有真实状态栏，手机上照抄定高
/// 会让 44dp 状态栏把 48 圆钮压掉近一半。
class ReaderDetailHeader extends StatelessWidget {
  const ReaderDetailHeader({
    required this.title,
    required this.onBack,
    this.actions = const <Widget>[],
    this.backTooltip,
    super.key,
  });

  final String title;
  final VoidCallback onBack;

  /// 右侧动作位（样例头部第二枚 `.icon-button`）；按出现顺序右对齐。
  final List<Widget> actions;
  final String? backTooltip;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 84,
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 6),
        child: Center(
          child: Row(
            children: [
              MobileGlassIconButton(
                tooltip:
                    backTooltip ??
                    MaterialLocalizations.of(context).backButtonTooltip,
                vector: OmniIcons.chevronLeft,
                onPressed: onBack,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.env.ink,
                      fontSize: AppTypography.bodySmall,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
