import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/files/domain/file_node.dart';

/// 文件类型功能编码色：六组「淡底 + 亮前景」（violet/blue/red/amber/
/// cyan/green）。属功能编码而非强调色，且按禁紫规范不落入 app/theme。
abstract final class FileEnvTypeColors {
  static const Color violet = Color(0xFFB3A4EF);
  static const Color violetBg = Color(0x267B64D5);
  static const Color blue = Color(0xFF91BAF2);
  static const Color blueBg = Color(0x2B4C84D2);
  static const Color red = Color(0xFFE69696);
  static const Color redBg = Color(0x24DA5050);
  static const Color amber = Color(0xFFE9BD7C);
  static const Color amberBg = Color(0x24D18A34);
  static const Color cyan = Color(0xFF7FD5CC);
  static const Color cyanBg = Color(0x2436A499);
  static const Color green = Color(0xFF9BD18D);
  static const Color greenBg = Color(0x244F9E41);

  /// 浅极性同位色。上面那批粉彩是暗玻璃上的取值，压在各自色舱底
  /// （14-17% 同色相叠加在 `#f1f4ed` 上）只有 1.35-1.74:1，
  /// 六类文件在浅色模式下靠颜色完全分不出来。这里按**保持色相、只压明度**
  /// 推出到舱底 ≥4.5：violet 4.62 / blue 4.65 / red 4.53 / amber 4.53 /
  /// cyan 4.76 / green 4.71。舱底沿用暗档那批淡底，浅态下它本身就是
  /// 一层柔和的同类色 wash。
  static const Color violetOnPaper = Color(0xFF6345DE);
  static const Color blueOnPaper = Color(0xFF175EBF);
  static const Color redOnPaper = Color(0xFFBB2D2D);
  static const Color amberOnPaper = Color(0xFF8C5D17);
  static const Color cyanOnPaper = Color(0xFF246E66);
  static const Color greenOnPaper = Color(0xFF3B6F2D);

  /// 视频分类信息条的前景色（与六组类型舱解耦）。
  static const Color videoCategory = Color(0xFF0EA5E9);
}

/// 移动壳层文件类型图形：40×40 r13 淡底亮前景的描边类型图标。
///
/// 六组功能编码色（violet/blue/red/amber/cyan/green）不占用强调色；
/// 多选选中时整格翻转为强调色底 + 对勾（与原型选中行一致）。
class FileEnvGlyph extends StatelessWidget {
  const FileEnvGlyph({required this.file, this.selected = false, super.key});

  final FileNode file;

  /// 多选选中态：底翻转为 lime，图标换对勾。
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: context.env.accent,
          borderRadius: BorderRadius.all(Radius.circular(13)),
        ),
        child: Center(
          child: OmniIcon(
            icon: OmniIcons.check,
            size: 18,
            color: context.env.onAccent,
          ),
        ),
      );
    }
    // 亮度即极性：本图形的落点全在 Files 托管面（MobileEnvironmentScope 默认
    // photographic=false），浅态一定是纸面，不会读到摄影档那张深玻璃表。
    final (foreground, background, glyph) = _resolve(
      file,
      onPaper: context.env.brightness == Brightness.light,
    );
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.all(Radius.circular(13)),
      ),
      child: Center(child: OmniIcon(icon: glyph, size: 18, color: foreground)),
    );
  }

  static (Color, Color, OmniIconsData) _resolve(
    FileNode file, {
    required bool onPaper,
  }) {
    Color fg(Color dark, Color light) => onPaper ? light : dark;
    if (file.isFolder) {
      return (
        fg(FileEnvTypeColors.blue, FileEnvTypeColors.blueOnPaper),
        FileEnvTypeColors.blueBg,
        OmniIcons.folder,
      );
    }
    final mime = file.mimeType ?? '';
    if (mime.startsWith('image/')) {
      return (
        fg(FileEnvTypeColors.green, FileEnvTypeColors.greenOnPaper),
        FileEnvTypeColors.greenBg,
        OmniIcons.image,
      );
    }
    if (mime.startsWith('video/')) {
      return (
        fg(FileEnvTypeColors.amber, FileEnvTypeColors.amberOnPaper),
        FileEnvTypeColors.amberBg,
        OmniIcons.film,
      );
    }
    if (mime.startsWith('audio/')) {
      return (
        fg(FileEnvTypeColors.cyan, FileEnvTypeColors.cyanOnPaper),
        FileEnvTypeColors.cyanBg,
        OmniIcons.music,
      );
    }
    if (_isArchive(mime)) {
      return (
        fg(FileEnvTypeColors.violet, FileEnvTypeColors.violetOnPaper),
        FileEnvTypeColors.violetBg,
        OmniIcons.grid,
      );
    }
    return (
      fg(FileEnvTypeColors.red, FileEnvTypeColors.redOnPaper),
      FileEnvTypeColors.redBg,
      OmniIcons.book,
    );
  }

  static bool _isArchive(String mime) {
    return mime.contains('zip') ||
        mime.contains('rar') ||
        mime.contains('7z') ||
        mime.contains('compressed') ||
        mime.contains('x-tar') ||
        mime.contains('gzip');
  }
}

/// 移动壳层文件行：类型彩色图形 + 名称/大小·日期 + 可选检视入口。
///
/// 列表态与首页内联列表共用；选中态整行 lime 淡底。
class FileEnvRow extends StatelessWidget {
  const FileEnvRow({
    required this.file,
    required this.selected,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onMore,
    this.showChevron = false,
    super.key,
  });

  final FileNode file;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;

  /// 可进入下一层的行尾箭头：稿子 `.feature-list > button > .icon:last-child`。
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localizations = MaterialLocalizations.of(context);
    final sub =
        file.isFolder
            ? l10n.filesFolder
            : '${formatFileSize(file.sizeBytes)}'
                '${file.updatedAt == null ? '' : ' · ${localizations.formatShortDate(file.updatedAt!)}'}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      child: Container(
        // 稿子 `.feature-list > button`：min-height 69、上下 6 内边距、
        // 行间一条 --line 发丝线；标题 11/600、副行 9 muted、间隙 3。
        constraints: const BoxConstraints(minHeight: 69),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color:
              selected ? context.env.accentInk.withValues(alpha: 0.06) : null,
          border: Border(bottom: BorderSide(color: context.env.line07)),
        ),
        child: Row(
          children: [
            FileEnvGlyph(file: file, selected: selected),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.env.ink,
                      fontSize: AppTypography.labelSmall,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // ignore: font_size_whitelist
                    style: TextStyle(
                      color: context.env.inkMuted,
                      // ignore: font_size_whitelist
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            if (onMore != null)
              IconButton(
                tooltip: AppLocalizations.of(context).filesMoreActions,
                onPressed: onMore,
                icon: OmniIcon(
                  icon: OmniIcons.more,
                  size: 20,
                  color: context.env.inkMuted,
                ),
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            if (showChevron) ...[
              const SizedBox(width: 8),
              OmniIcon(
                icon: OmniIcons.chevron,
                size: 16,
                color: context.env.ink40,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 移动壳层文件瓦片：17 圆角白 4% 卡面 + 收藏星标。
class FileEnvTile extends StatelessWidget {
  const FileEnvTile({
    required this.file,
    required this.selected,
    required this.favorite,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    super.key,
  });

  final FileNode file;
  final bool selected;
  final bool favorite;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final sub =
        file.isFolder
            ? null
            : '${formatFileSize(file.sizeBytes)}'
                '${file.updatedAt == null ? '' : ' · ${localizations.formatShortDate(file.updatedAt!)}'}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              selected
                  ? context.env.accentInk.withValues(alpha: 0.06)
                  : context.env.surfaceTint,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color:
                selected
                    ? context.env.accentInk.withValues(alpha: 0.26)
                    : context.env.line07,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FileEnvGlyph(file: file, selected: selected),
                const Spacer(),
                if (favorite)
                  OmniIcon(
                    icon: OmniIcons.heart,
                    size: 15,
                    color: context.env.accentInk,
                  ),
              ],
            ),
            const Spacer(),
            Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.env.ink,
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (sub != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.env.inkMuted,
                    fontSize: AppTypography.labelMicro,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
