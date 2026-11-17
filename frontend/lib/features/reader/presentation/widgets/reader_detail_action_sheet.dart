import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';

/// 详情页右上角「更多」面板（样例 `.glass-sheet` + `.feature-list` 行族）：
/// 编辑元数据 / 重新解析 / 删除书籍。
///
/// 样例的 more 钮只接了「编辑元数据」一件事，删除确认则是它把「更多」当成
/// 删除入口的产品逻辑错误；这里把详情页已有的三个动作收进同一片浮层，
/// 删除仍走原有的永久删除确认框。
class ReaderDetailActionSheet extends StatelessWidget {
  const ReaderDetailActionSheet({
    required this.onEditMetadata,
    required this.onReparse,
    required this.onDelete,
    super.key,
  });

  final VoidCallback onEditMetadata;
  final VoidCallback onReparse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: ColoredBox(
            color: context.env.sheetSolid,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.env.line15,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SheetHead(
                      eyebrow: l10n.bookDetailHeader.toUpperCase(),
                      title: l10n.coreMore,
                    ),
                    MobileFeatureListRow(
                      icon: OmniIcons.settings,
                      title: l10n.bookDetailMetadata,
                      detail: l10n.readerDetailActionMetadataDesc,
                      onTap: onEditMetadata,
                    ),
                    MobileFeatureListRow(
                      icon: OmniIcons.cloud,
                      title: l10n.readerDetailReparse,
                      detail: l10n.readerDetailActionReparseDesc,
                      onTap: onReparse,
                    ),
                    MobileFeatureListRow(
                      icon: OmniIcons.close,
                      neutralIcon: true,
                      title: l10n.readerDeleteBook,
                      detail: l10n.readerDeleteBookHint,
                      onTap: onDelete,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 面板头（样例 `.sheet-head`）：等宽眉标 + 衬线面板名。
class _SheetHead extends StatelessWidget {
  const _SheetHead({required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.env.accentInk,
              fontSize: AppTypography.labelMicro,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.env.ink,
              fontFamily: AppTypography.serifFamily,
              fontFamilyFallback: AppTypography.serifFamilyFallback,
              fontSize: AppTypography.headlineSection,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
