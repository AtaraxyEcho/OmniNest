import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/files/application/file_browser_models.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart'
    show FileManagerSectionMeta;

/// 工作区工具总入口（原型 `FeatureDirectory`）：分组列出壳层内已落地的
/// 工具页，行了 `.feature-link-grid` 卡片（66 高、r16、白 4.5% 底 +
/// 白 7% 描边、42 图标舱 + 11/9 双行 + 箭头）。
///
/// 只收已能在托管态打开的目标：原型里 `media-collections`、
/// `watch-history`、`scraper` 与 `music-scan` 都没有模块内入口，它们的
/// 托管形态落地后才进这张表，避免做成死键。
class WorkspaceToolsPage extends StatelessWidget {
  const WorkspaceToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = <_WorkspaceToolGroup>[
      _WorkspaceToolGroup(
        label: l10n.toolsGroupFiles,
        rows: _fileRows(context, l10n),
      ),
      _WorkspaceToolGroup(
        label: l10n.toolsGroupMedia,
        rows: <_WorkspaceToolRow>[
          _WorkspaceToolRow(
            icon: OmniIcons.music,
            title: l10n.musicHistoryTitle,
            detail: l10n.toolsMusicHistoryDetail,
            onTap: () => context.push('/music/history'),
          ),
        ],
      ),
    ];

    return MobilePageSurface(
      backdropOpacity: 0.92,
      child: Column(
        children: [
          MobileModuleHeader(
            title: l10n.toolsTitle,
            subtitle: l10n.toolsSubtitle,
            backTooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
              children: [
                const _WorkspaceToolsIntro(),
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 14, 0, 2),
                    child: Text(
                      group.label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9, // ignore: font_size_whitelist
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                        color: MobileEnvColors.inkFaint,
                      ),
                    ),
                  ),
                  for (final row in group.rows) _ToolGridRow(row: row),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Files 分区行直连 `/files?section=`：分区名与描述都取模块既有标签，
  /// 不另造文案。
  List<_WorkspaceToolRow> _fileRows(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    const sections = <FileManagerSection>[
      FileManagerSection.recent,
      FileManagerSection.favorites,
      FileManagerSection.myShares,
      FileManagerSection.offlineDownloads,
      FileManagerSection.storageStats,
      FileManagerSection.externalStorage,
      FileManagerSection.importTasks,
      FileManagerSection.uploadQueue,
    ];
    const glyphs = <OmniIconsData>[
      OmniIcons.clock,
      OmniIcons.heart,
      OmniIcons.share,
      OmniIcons.download,
      OmniIcons.cloud,
      OmniIcons.device,
      OmniIcons.list,
      OmniIcons.queue,
    ];
    return [
      for (final (index, section) in sections.indexed)
        _WorkspaceToolRow(
          icon: glyphs[index],
          title: section.labelOf(l10n),
          detail: section.descriptionOf(l10n),
          onTap: () => context.go('/files?section=${section.name}'),
        ),
    ];
  }
}

class _WorkspaceToolGroup {
  const _WorkspaceToolGroup({required this.label, required this.rows});

  final String label;
  final List<_WorkspaceToolRow> rows;
}

class _WorkspaceToolRow {
  const _WorkspaceToolRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final OmniIconsData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
}

/// 原型 `.feature-intro`：8px 酸绿眉标 + 34px 衬线标题 + 10px 说明。
class _WorkspaceToolsIntro extends StatelessWidget {
  const _WorkspaceToolsIntro();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.toolsIntroEyebrow.toUpperCase(),
            style: const TextStyle(
              fontSize: 8, // ignore: font_size_whitelist
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: MobileEnvColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.toolsIntroTitle,
            style: const TextStyle(
              fontFamily: AppTypography.serifFamily,
              fontFamilyFallback: AppTypography.serifFamilyFallback,
              fontSize: 34,
              height: 1.02,
              fontWeight: FontWeight.w400,
              color: MobileEnvColors.ink,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            l10n.toolsIntroBody,
            style: const TextStyle(
              fontSize: 10, // ignore: font_size_whitelist
              height: 1.55,
              color: MobileEnvColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单行卡片：整卡可点按，图标舱按稿子 `.notif-icon` 取酸绿底（与账户表、
/// Files 分区列表同族，`neutral` 只用于无状态语义的行）。
class _ToolGridRow extends StatelessWidget {
  const _ToolGridRow({required this.row});

  final _WorkspaceToolRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: MobilePressable(
        semanticLabel: row.title,
        onTap: row.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 66),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x0BFFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MobileEnvColors.line07),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MobileEnvColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: OmniIcon(
                  icon: row.icon,
                  size: 18,
                  color: MobileEnvColors.accent,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: MobileEnvColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      row.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9, // ignore: font_size_whitelist
                        color: MobileEnvColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const OmniIcon(
                icon: OmniIcons.chevron,
                size: 16,
                color: MobileEnvColors.ink40,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
