import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 稿子的章末两块：`.chapter-end` 发丝线行 + `.next-chapter` 下一章卡。
///
/// 稿子那一行写的是"本章还剩约 7 分钟"，是原型里的假数据；这里换成真实的
/// 章节位次与全书进度，不编造剩余时长。
class ReaderChapterEndCard extends StatelessWidget {
  const ReaderChapterEndCard({
    required this.settings,
    required this.chapterLabel,
    this.nextChapterTitle,
    this.onNextChapter,
    super.key,
  });

  /// `.chapter-end` 的上下外边距，稿子 52/26。
  static const double _dividerTopGap = 52;
  static const double _dividerBottomGap = 26;

  /// `.next-chapter` 的 min-height 与内边距，稿子 76 与 16/13。
  static const double _nextCardMinHeight = 76;
  static const EdgeInsets _nextCardPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 13,
  );

  /// 卡内"下一章"小字与章题之间的间隙。
  static const double _titleGap = 4;

  /// 卡边框宽度：渲染的 `Border.all(width:)` 与高度公式共用这一份。
  static const double _nextCardBorderWidth = 1;

  /// 右侧箭头图标的舱位高度，同时是卡片 Row 的交叉轴下限。
  static const double _nextCardIconSize = 18;

  /// 发丝线行里"线—字—线"的间距，以及一条线要闻留的宽度（就是它自己的厚度 1px）。
  ///
  /// 小字的宽度上界由这两项推出来，界与渲染共用同一组常量：把 14 或 1 改掉而忘了
  /// 改上界，窄窗里就会重新溢出。
  static const double _hairlineGap = 14;
  static const double _hairlineMinWidth = 1;

  /// 两行文字的字号与行高倍率。
  ///
  /// 行盒必须显式钉住：字族的原生行高在 1.1~1.5 之间浮动，交给字体自己算时
  /// 同一个 fontSize 各平台差出亚像素，下面的确定高度就比渲染矮——列表用
  /// `itemExtentBuilder` 下发的是紧约束，矮一点直接报 RenderFlex overflow。
  static const double _labelLineHeight = 1.4;
  static const double _titleLineHeight = 1.4;
  static const double _titleFontSize = 15;

  /// 行盒向上取整后的排版高度。
  ///
  /// 1.25 缩放的小字排版值是 17.5、1.5 缩放的章题是 31.5；平台把行盒取整到哪一格
  /// 因字体与缩放档而异，向上收一行最多少留 1px 空白，反过来是裁字。卡片按这个值
  /// 反过来**规定**自己的行盒（见 [_lineBox]），确定高度与渲染之间不留取整差。
  ///
  /// 缩放必须**逐字号**问 [scaler]：框架只把 scaler 乘在 fontSize 上，行盒再按放大后的
  /// 字号算。平台的非线性无障碍缩放（Android）对不同字号给不同倍率，用 `scale(1)` 当
  /// 统一倍率会让小字行与章题行各差一格。
  static double _lineExtent(
    double fontSize,
    double lineHeight,
    TextScaler scaler,
  ) => (lineHeight * scaler.scale(fontSize)).ceilToDouble();

  /// 小字行与章题行的排版高度，随卡片实际所在内容层的文字缩放同步放大。
  ///
  /// 这两个值是卡片**自己**的行盒高度（见 `build` 里的 [_lineBox]），不是对平台排版的
  /// 预测：列表下发紧约束，预测差一格就是 `RenderFlex overflow`。
  static double _labelLineExtent(TextScaler scaler) =>
      _lineExtent(AppTypography.labelMicro, _labelLineHeight, scaler);

  static double _titleLineExtent(TextScaler scaler) =>
      _lineExtent(_titleFontSize, _titleLineHeight, scaler);

  /// `.chapter-end` 占位：上下 52/26 外边距 + 一行 10px 小字（默认缩放下 92）。
  static double dividerHeightFor(TextScaler scaler) =>
      _dividerTopGap + _labelLineExtent(scaler) + _dividerBottomGap;

  /// `.next-chapter` 卡的排版高度：min-height 与「两行文字（或箭头图标舱）+ 上下内边距 + 边框」取大。
  ///
  /// 边框必须算进来：`Border.all` 的 1px 由 DecoratedBox 加在自身尺寸里，`min-height`
  /// 只在内容不足 76 时兜底，内容超过 76 之后边框就是实打实的 2px（此前漏算，1.5 缩放
  /// 下确定高度比渲染矮 2.5px，紧约束下直接顶破父级）。
  static double nextCardHeightFor(TextScaler scaler) {
    final rows = math.max(
      _labelLineExtent(scaler) + _titleGap + _titleLineExtent(scaler),
      _nextCardIconSize,
    );
    return math.max(
      _nextCardMinHeight,
      rows + _nextCardPadding.vertical + _nextCardBorderWidth * 2,
    );
  }

  /// 滚动列表末尾条目要用确定高度，这里给出卡片高度。
  ///
  /// [scaler] 必须是卡片**渲染时**生效的那份缩放，即内容层的系统缩放
  /// （`FontScaleScope.systemScalerOf`）：卡片在 `withSystemScaleOnly` 子树里排版，
  /// 按页面环境值（系统×应用字体档位）推算会在档位低于标准时比渲染矮整整一行，
  /// 紧约束下直接报 overflow；高于标准时反向多留一段空白。
  static double heightFor({
    required bool hasNextChapter,
    required TextScaler scaler,
  }) =>
      dividerHeightFor(scaler) +
      (hasNextChapter ? nextCardHeightFor(scaler) : 0);

  final ReaderViewSettings settings;
  final String chapterLabel;

  /// 末章为 null：只留发丝线行，不摆一个点了没反应的"下一章"。
  final String? nextChapterTitle;
  final VoidCallback? onNextChapter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final next = nextChapterTitle;
    // 与 `heightFor` 同一份缩放：卡片渲染时生效的就是内容层这一份。
    final scaler = MediaQuery.textScalerOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            0,
            _dividerTopGap,
            0,
            _dividerBottomGap,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 小字是这一行唯一的不可压缩项：它的自然宽度一旦超过整行减去两条发丝线
              // 与两个间距，Row 就横向溢出（实测 3 倍文字缩放在 400px 宽下溢 52px，
              // 读者看到的是黄黑条纹）。发丝线只需留住 1px，所以给小字一个上界，
              // 让它用省略号收尾，而不是把两侧线挤出行外。
              final labelMaxWidth =
                  constraints.hasBoundedWidth
                      ? math.max(
                        0.0,
                        constraints.maxWidth -
                            _hairlineGap * 2 -
                            _hairlineMinWidth * 2,
                      )
                      : double.infinity;
              return Row(
                children: [
                  Expanded(child: _hairline()),
                  SizedBox(width: _hairlineGap),
                  // 单行是下面确定高度的前提：窄窗里让位号换行会多出一行。
                  _lineBox(
                    _labelLineExtent(scaler),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: labelMaxWidth),
                      child: Text(
                        chapterLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: settings.onSurfaceVariantColor,
                          fontSize: AppTypography.labelMicro,
                          height: _labelLineHeight,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: _hairlineGap),
                  Expanded(child: _hairline()),
                ],
              );
            },
          ),
        ),
        if (next != null)
          Semantics(
            // 卡内两行文字（"下一章" + 章题）自己就是读屏内容，不再叠 label。
            button: true,
            child: InkWell(
              onTap: onNextChapter,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: _nextCardMinHeight,
                ),
                padding: _nextCardPadding,
                decoration: BoxDecoration(
                  color: settings.controlSurfaceColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: settings.lineColor,
                    width: _nextCardBorderWidth,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _lineBox(
                            _labelLineExtent(scaler),
                            Text(
                              l10n.readerNextChapter,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: settings.onSurfaceVariantColor,
                                fontSize: AppTypography.labelMicro,
                                height: _labelLineHeight,
                              ),
                            ),
                          ),
                          const SizedBox(height: _titleGap),
                          _lineBox(
                            _titleLineExtent(scaler),
                            Text(
                              next,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: settings.onSurfaceColor,
                                fontSize: _titleFontSize,
                                height: _titleLineHeight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    OmniIcon(
                      icon: OmniIcons.arrow,
                      size: _nextCardIconSize,
                      color: settings.onSurfaceVariantColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 把一行文字钉在 [height] 的行盒里。
  ///
  /// 滚动列表按 [heightFor] 下发紧约束，平台把行盒取整到哪一格是它自己的事：
  /// 猜差一格就是 `RenderFlex overflow`（移动端实测 1.00px）。这里让排版高度
  /// 由本文件给值，与确定高度同源，取整余量落在行盒内部的空白上。
  static Widget _lineBox(double height, Widget child) =>
      SizedBox(height: height, child: child);

  Widget _hairline() =>
      Container(height: _hairlineMinWidth, color: settings.lineColor);
}
