import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/utils/image_decode_width.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/video/application/movie_center_state.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/core/widgets/mobile_sheet_semantics.dart';

/// 托管 Films/Series 段的排序 chip 行（样例 `.chip-row` 胶囊）：
/// 最新 / 评分 / 年份 + 收藏过滤 + 尾部状态筛选溢出入口
/// （All/Matched/Pending/Failed 收进底部玻璃面板，不占常驻行）。
///
/// 仅供托管态使用；桌面三处共用件是 [MovieRedesignFilterSortBar]
/// （宽屏分区/居中分区/管理列表），工位直角形态不随本件变化。
class MovieRedesignMobileChips extends StatelessWidget {
  const MovieRedesignMobileChips({
    required this.sortBy,
    required this.onSortBy,
    required this.favoritesOnly,
    required this.onFavoritesOnly,
    required this.filter,
    required this.onFilter,
    super.key,
  });

  final MovieSortBy sortBy;
  final ValueChanged<MovieSortBy> onSortBy;

  /// 收藏过滤为本地展示态（不写入控制器筛选枚举）。
  final bool favoritesOnly;
  final ValueChanged<bool> onFavoritesOnly;

  final MovieLibraryFilter filter;
  final ValueChanged<MovieLibraryFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(
                  env: context.env,
                  label: l10n.videoMobileSortRecent,
                  selected: sortBy == MovieSortBy.dateAdded,
                  onTap: () => onSortBy(MovieSortBy.dateAdded),
                ),
                const SizedBox(width: 7),
                _chip(
                  env: context.env,
                  label: l10n.videoRating,
                  selected: sortBy == MovieSortBy.rating,
                  onTap: () => onSortBy(MovieSortBy.rating),
                ),
                const SizedBox(width: 7),
                _chip(
                  env: context.env,
                  label: l10n.videoYear,
                  selected: sortBy == MovieSortBy.releaseDate,
                  onTap: () => onSortBy(MovieSortBy.releaseDate),
                ),
                const SizedBox(width: 7),
                _chip(
                  env: context.env,
                  label: l10n.videoSectionFavorites,
                  selected: favoritesOnly,
                  onTap: () => onFavoritesOnly(!favoritesOnly),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _StatusFilterEntry(filter: filter, onFilter: onFilter),
      ],
    );
  }

  Widget _chip({
    required MobileEnvPalette env,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    // 样例 `.chip`：r11、白 5% 底 + 白 9% 描边、inkMuted 前景；
    // 选中态换成酸绿 10% 底 + 38% 描边 + ink 前景。
    // 字号取短标签档 10 而不是样例的 9px：样例 9px 是大写拉丁短词，
    // 中文两字词压到 9px 即回到 S1 那一类不可读。
    // 行高取 38 与同排的筛选钮对齐：样例 32 的命中区落在次级控件
    // 35-45 档之下，扩命中必然撑行，故按行高档落地。
    final accent = env.accentInk;
    return Material(
      color: selected ? accent.withValues(alpha: 0.10) : env.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(
          color: selected ? accent.withValues(alpha: 0.38) : env.line09,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          // 定高而非 minHeight：只给下限时容器会跟随父级有界高度拉伸，
          // 胶囊底色与描边会整块变形。
          height: 38,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppTypography.labelMicro,
              height: 1.2,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? env.ink : env.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// 状态筛选溢出入口：点开底部面板选择刮削状态（收藏过滤激活时隐藏）。
class _StatusFilterEntry extends StatelessWidget {
  const _StatusFilterEntry({required this.filter, required this.onFilter});

  final MovieLibraryFilter filter;
  final ValueChanged<MovieLibraryFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = filter != MovieLibraryFilter.all;
    return Tooltip(
      message: l10n.videoMobileStatusFilter,
      child: InkWell(
        onTap: () => _openSheet(context),
        borderRadius: BorderRadius.circular(10),
        child: SizedBox.square(
          dimension: 38,
          child: Icon(
            Icons.tune_rounded,
            size: 18,
            color: active ? context.env.ink : context.env.inkMuted,
          ),
        ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final options = <(MovieLibraryFilter, String)>[
      (MovieLibraryFilter.all, l10n.videoRedesignFilterAll),
      (MovieLibraryFilter.matched, l10n.videoRedesignFilterMatched),
      (MovieLibraryFilter.pending, l10n.videoRedesignFilterPending),
      (MovieLibraryFilter.failed, l10n.videoRedesignFilterFailed),
    ];
    // 面板经根导航器呈现，默认落在壳层之外：捕获宿主环境再重放。
    final ambience = MobileSheetAmbience.capture(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder:
          (sheetContext) => MobileSheetSemantics(
            child: ambience.wrap(
              _StatusFilterSheet(
                filter: filter,
                options: options,
                title: l10n.videoMobileStatusFilter,
                onSelected: (value) {
                  Navigator.of(sheetContext).pop();
                  onFilter(value);
                },
              ),
            ),
          ),
    );
  }
}

/// 状态筛选面板（样例 `.glass-sheet`：实底 #171E1C + 顶部 r28 + 把手）。
class _StatusFilterSheet extends StatelessWidget {
  const _StatusFilterSheet({
    required this.filter,
    required this.options,
    required this.title,
    required this.onSelected,
  });

  final MovieLibraryFilter filter;
  final List<(MovieLibraryFilter, String)> options;
  final String title;
  final ValueChanged<MovieLibraryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13, // ignore: font_size_whitelist
                        fontWeight: FontWeight.w700,
                        color: context.env.ink,
                      ),
                    ),
                  ),
                  for (final (value, label) in options)
                    _StatusFilterOptionRow(
                      label: label,
                      selected: value == filter,
                      onTap: () => onSelected(value),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 面板选项行：发丝线分隔、选中项酸绿勾。
class _StatusFilterOptionRow extends StatelessWidget {
  const _StatusFilterOptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MobilePressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.env.line07)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12, // ignore: font_size_whitelist
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? context.env.ink : context.env.inkMuted,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 18, color: context.env.accentInk),
          ],
        ),
      ),
    );
  }
}

/// 移动端 For you 段的影院 hero 卡（样例 cinema-hero）：精选项满宽
/// 压题图 + 渐变 + 等宽眉标 + 衬线标题 + 动作双钮。
///
/// 入参保持中性：续播项与非续播项（最近添加首项）都由调用方折算后传入，
/// 本件不感知进度与分集来源，避免兜底源一换就取到别条目的元数据。
class MovieMobileCinemaHero extends StatelessWidget {
  const MovieMobileCinemaHero({
    required this.title,
    required this.eyebrow,
    required this.primaryLabel,
    required this.onPlay,
    required this.onInfo,
    this.posterUrl,
    this.metaLine,
    this.badgeText,
    super.key,
  });

  final String title;
  final String? posterUrl;

  /// 标题上方的等宽眉标：续播项是「继续观看 · 进度 · 剩余分钟」，
  /// 非续播项是样例的精选标注（`videoHeroFeatured · videoHeroMovie`）。
  final String eyebrow;

  /// 主按钮文案：有进度为「继续播放」，无进度为「立即播放」。
  final String primaryLabel;

  /// 元数据行（★ 评分 · 年份 · 时长 · 类型），由调用方从 hero 项自身的
  /// 影片元数据拼装；取不到时退化为分集标注，再取不到就不渲染该行。
  final String? metaLine;

  /// 右上角规格徽标（样例 cinema-badge：4K · HDR）。
  final String? badgeText;

  final VoidCallback onPlay;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 样例 .cinema-hero：固定 348 高、r26；占位底用环境舞台色，
    // 文本层走环境墨阶（题图上永远是浅字）。
    return SizedBox(
      height: 348,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (posterUrl != null)
              // 签名 URL 的查询串每次刷新都会变：缓存键取不含查询串的路径，
              // 否则同一张题图每次进页都重新下载。
              CachedNetworkImage(
                imageUrl: posterUrl!,
                cacheKey: _posterCacheKey(posterUrl!),
                fit: BoxFit.cover,
                memCacheWidth: quantizedDecodeWidth(
                  logicalWidth: MediaQuery.sizeOf(context).width,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                  max: 2560,
                ),
                memCacheHeight: quantizedDecodeWidth(
                  logicalWidth: 348,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                  max: 2048,
                ),
                errorWidget: (_, _, _) => ColoredBox(color: context.env.stage),
              )
            else
              ColoredBox(color: context.env.stage),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                  stops: [0.42, 1],
                ),
              ),
            ),
            if (badgeText != null && badgeText!.isNotEmpty)
              Positioned(
                right: 14,
                top: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: MovieOverlayColors.badgeFill,
                    borderRadius: BorderRadius.circular(8),
                    // polarity-stable：压在影像上，对比由图片本身提供，两极性同值
                    border: Border.all(color: MovieOverlayColors.hairline),
                  ),
                  child: Text(
                    badgeText!,
                    style: _heroMonoStyle(
                      env: context.env,
                      size: 8,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 23),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: _heroMonoStyle(
                      env: context.env,
                      size: 9,
                      // polarity-stable：压在影像上，对比由图片本身提供，两极性同值
                      color: MovieOverlayColors.eyebrowOnImage,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _heroTitleStyle(context.env),
                  ),
                  const SizedBox(height: 6),
                  if (metaLine != null && metaLine!.isNotEmpty)
                    Text(
                      metaLine!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _heroMetaStyle(context.env),
                    ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      _HeroButton(
                        label: primaryLabel,
                        icon: Icons.play_arrow_rounded,
                        filled: true,
                        onTap: onPlay,
                      ),
                      const SizedBox(width: 9),
                      _HeroButton(
                        label: l10n.videoHeroInfo,
                        icon: Icons.more_horiz_rounded,
                        onTap: onInfo,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// hero 等宽眉标/徽标（样例 mono 9/8，字重 700/800）。
TextStyle _heroMonoStyle({
  required MobileEnvPalette env,
  required double size,
  Color? color,
  FontWeight weight = FontWeight.w700,
}) {
  return TextStyle(
    fontFamily: AppTypography.monoFamily,
    fontFamilyFallback: AppTypography.monoFamilyFallback,
    fontSize: size,
    letterSpacing: 1.5,
    height: 1.2,
    fontWeight: weight,
    color: color ?? env.ink,
  );
}

/// hero 标题：Instrument Serif 35，样例 cinema-info h2。
TextStyle _heroTitleStyle(MobileEnvPalette env) {
  return TextStyle(
    fontFamily: AppTypography.serifFamily,
    fontFamilyFallback: AppTypography.serifFamilyFallback,
    // ignore: font_size_whitelist
    fontSize: 35,
    height: 1.05,
    fontWeight: FontWeight.w400,
    color: env.ink,
  );
}

/// hero 元数据行：白 70%，题图上比 inkMuted 更贴样例。
TextStyle _heroMetaStyle(MobileEnvPalette env) {
  return TextStyle(
    // ignore: font_size_whitelist
    fontSize: 11,
    height: 1.4,
    color: env.white70,
  );
}

/// hero 动作钮：主钮米白实底深字（样例 .btn-primary），次钮深玻璃描边。
class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? context.env.onButtonInk : context.env.ink;
    return Material(
      color:
          filled
              ? context.env.buttonInk
              // 次钮压在海报图上，深玻璃与白描边由图提供对比，两极性同值。
              : MovieOverlayColors.secondaryButtonFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          // polarity-stable：压在影像上，对比由图片本身提供，两极性同值
          color:
              filled
                  ? Colors.transparent
                  : MovieOverlayColors.secondaryButtonBorder,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 43),
          padding: const EdgeInsets.symmetric(horizontal: 17),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  // ignore: font_size_whitelist
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 题图缓存键：去掉签名查询串，只保留路径。
String _posterCacheKey(String url) {
  final uri = Uri.tryParse(url);
  return uri == null ? url : uri.replace(query: '').toString();
}
