import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';

/// 工作区工具总入口（原型 `FeatureDirectory`）：分组列出壳层内已落地的
/// 工具页，行了 `.feature-link-grid` 卡片（66 高、r16、白 4.5% 底 +
/// 白 7% 描边、42 图标舱 + 11/9 双行 + 箭头）。
///
/// 收表规则只有一条：**模块内已有一级入口的页面不进这里**。Files 首页的
/// 四张分区卡与三枚工具快捷、音乐岛的播放历史都已各自可达，重复列在这里
/// 只会让同一页有两个入口；留下来的都是除深链外无处可去的页。
///
/// 行内默认 push：go 会换掉整条栈，从工具页进目标后系统返回直接退出应用。
/// 壳层分支路由（`/files`）是例外，见该行的注释。
class WorkspaceToolsPage extends StatelessWidget {
  const WorkspaceToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final env = context.env;
    final l10n = AppLocalizations.of(context);
    final groups = <_WorkspaceToolGroup>[
      _WorkspaceToolGroup(
        label: l10n.toolsGroupFiles,
        rows: <_WorkspaceToolRow>[
          _WorkspaceToolRow(
            icon: OmniIcons.share,
            title: l10n.filesMyShares,
            detail: l10n.filesMySharesDesc,
            // go 而不是 push：`/files` 是壳层分支路由，从壳外的根级页 push 它
            // 会让 go_router 再压入第二个壳层页面，Navigator 在
            // `_debugCheckDuplicatedPageKeys` 上断言重复 page key 并失去整棵内容
            // 树。四空间是同级目标，按导航规程走 go。
            onTap: () => context.go('/files?section=myShares'),
          ),
        ],
      ),
      _WorkspaceToolGroup(
        label: l10n.toolsGroupMedia,
        rows: <_WorkspaceToolRow>[
          _WorkspaceToolRow(
            icon: OmniIcons.film,
            title: l10n.videoSectionCollections,
            detail: l10n.toolsVideoCollectionsDetail,
            onTap: () => context.push('/video?section=collections'),
          ),
          _WorkspaceToolRow(
            icon: OmniIcons.list,
            title: l10n.videoSectionHistory,
            detail: l10n.videoHistorySubtitle,
            onTap: () => context.push('/video?section=history'),
          ),
          _WorkspaceToolRow(
            icon: OmniIcons.queue,
            title: l10n.musicDeckLocalManagement,
            detail: l10n.toolsMusicScanDetail,
            onTap: () => context.push('/music/scan'),
          ),
          _WorkspaceToolRow(
            icon: OmniIcons.sparkle,
            title: l10n.videoSectionMovieAdmin,
            detail: l10n.toolsScraperDetail,
            onTap: () => context.push('/video?section=management'),
          ),
        ],
      ),
      _WorkspaceToolGroup(
        label: l10n.toolsGroupPhotosReader,
        rows: <_WorkspaceToolRow>[
          _WorkspaceToolRow(
            icon: OmniIcons.image,
            title: l10n.photosGroupsTitle,
            detail: l10n.photosGroupsSubtitle,
            onTap: () => context.push('/photos/groups'),
          ),
          _WorkspaceToolRow(
            icon: OmniIcons.book,
            title: l10n.readerAdminModuleTitle,
            detail: l10n.toolsReaderAdminDetail,
            onTap: () => context.push('/reader/admin'),
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
                      style: TextStyle(
                        fontSize: AppTypography.labelMicro,
                        height: 1.45,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                        color: env.groupLabelInk,
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
    final env = context.env;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.toolsIntroEyebrow.toUpperCase(),
            style: TextStyle(
              fontSize: 8, // ignore: font_size_whitelist
              height: 1.45,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: env.groupLabelInk,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.toolsIntroTitle,
            style: TextStyle(
              fontFamily: AppTypography.serifFamily,
              fontFamilyFallback: AppTypography.serifFamilyFallback,
              fontSize: 34,
              height: 1.02,
              fontWeight: FontWeight.w400,
              color: env.ink,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            l10n.toolsIntroBody,
            style: TextStyle(
              fontSize: 10, // ignore: font_size_whitelist
              height: 1.55,
              color: env.inkMuted,
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
    final env = context.env;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: MobilePressable(
        semanticLabel: row.title,
        onTap: row.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 66),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: env.surfaceTint,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: env.line07),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: env.accentInk.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: OmniIcon(icon: row.icon, size: 18, color: env.accentInk),
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
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: env.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      row.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9, // ignore: font_size_whitelist
                        color: env.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OmniIcon(icon: OmniIcons.chevron, size: 16, color: env.ink40),
            ],
          ),
        ),
      ),
    );
  }
}
