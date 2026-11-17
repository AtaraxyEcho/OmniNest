import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';

/// 新版分区标题：衬线中文主标题 + 英文辅助小字 + 条目计数 + 副标题 + 底部分隔线。
class MovieRedesignSectionHeader extends StatelessWidget {
  const MovieRedesignSectionHeader({
    required this.title,
    this.subtitleEn,
    this.count,
    this.subtitle,
    super.key,
  });

  final String title;

  /// 标题右侧的英文辅助标注。
  final String? subtitleEn;

  /// 条目计数，为空时不显示。
  final int? count;

  /// 分区副标题。
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final l10n = AppLocalizations.of(context);
    // 对应原型 text-2xl sm:text-3xl 的响应式标题字号。
    final atSm = movieRedesignAtSm(MediaQuery.sizeOf(context).width);
    final titleSize = atSm ? 30.0 : 24.0;
    final secondarySize = atSm ? 14.0 : 12.0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: text.display(size: titleSize),
                  maxLines: 1,
                ),
              ),
              if (subtitleEn != null) ...[
                const SizedBox(width: 10),
                Text(
                  subtitleEn!,
                  style: text.body(
                    size: secondarySize,
                    color: palette.mutedForeground,
                  ),
                ),
              ],
              if (count != null) ...[
                const SizedBox(width: 10),
                Text(
                  l10n.videoRedesignItemsCount(count!),
                  style: text.mono(
                    size: AppTypography.bodySmall,
                    color: palette.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: text.body(
                size: secondarySize,
                color: palette.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
