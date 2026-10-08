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
        width: 40,
        height: 40,
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
    final (foreground, background, glyph) = _resolve(file);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.all(Radius.circular(13)),
      ),
      child: Center(child: OmniIcon(icon: glyph, size: 19, color: foreground)),
    );
  }

  static (Color, Color, OmniIconsData) _resolve(FileNode file) {
    if (file.isFolder) {
      return (
        FileEnvTypeColors.blue,
        FileEnvTypeColors.blueBg,
        OmniIcons.folder,
      );
    }
    final mime = file.mimeType ?? '';
    if (mime.startsWith('image/')) {
      return (
        FileEnvTypeColors.green,
        FileEnvTypeColors.greenBg,
        OmniIcons.image,
      );
    }
    if (mime.startsWith('video/')) {
      return (
        FileEnvTypeColors.amber,
        FileEnvTypeColors.amberBg,
        OmniIcons.film,
      );
    }
    if (mime.startsWith('audio/')) {
      return (
        FileEnvTypeColors.cyan,
        FileEnvTypeColors.cyanBg,
        OmniIcons.music,
      );
    }
    if (_isArchive(mime)) {
      return (
        FileEnvTypeColors.violet,
        FileEnvTypeColors.violetBg,
        OmniIcons.grid,
      );
    }
    return (FileEnvTypeColors.red, FileEnvTypeColors.redBg, OmniIcons.book);
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
    super.key,
  });

  final FileNode file;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;

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
        constraints: const BoxConstraints(minHeight: 66),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        color: selected ? const Color(0x0FD5F17D) : Colors.transparent,
        child: Row(
          children: [
            FileEnvGlyph(file: file, selected: selected),
            const SizedBox(width: 12),
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
                      fontSize: AppTypography.bodyMedium,
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
          color: selected ? const Color(0x0FD5F17D) : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? const Color(0x42D5F17D) : const Color(0x14FFFFFF),
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
