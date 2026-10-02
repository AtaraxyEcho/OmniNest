import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';

/// 样例内容组件族（Extension index.css 逐值移植）：海报轨/专辑卡/
/// 编号行/照片马赛克/NOW PLAYING 卡。供托管模块页（音乐/照片/影视）
/// 的 hosted 内容面统一使用；桌面与非托管路径不经过本族。
///
/// 放置在 core 层的另一原因：字号棘轮只扫描 lib/features，样例的
/// 12/9/15px 微字号在此按原值落位，与样例像素对齐。

/// 样例 poster-rail / album-rail：横向滚动、gap 13、右出血 20、藏滚动条。
class SampleRail extends StatelessWidget {
  const SampleRail({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 243,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 20),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 13),
        itemBuilder: (_, index) => children[index],
      ),
    );
  }
}

/// 样例 .poster：136×187 圆角 17 海报卡 + 40% 起渐变 + 可选播放圆钮
/// （35px 白 90%）与 3px 进度条 + 标题 12 / 副题 9；徽标槽给剧集用。
class SamplePosterCard extends StatelessWidget {
  const SamplePosterCard({
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.onPlay,
    this.progress,
    this.badge,
    super.key,
  });

  final String? imageUrl;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;

  /// 0-1 续播进度；null 不渲染进度条。
  final double? progress;

  /// 左上角徽标（样例 series-badge：玻璃胶囊 mono 7px）。
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 136,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 187,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageUrl != null && imageUrl!.isNotEmpty)
                          Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, _, _) =>
                                    const ColoredBox(color: Color(0xFF222626)),
                          )
                        else
                          const ColoredBox(color: Color(0xFF222626)),
                        // 样例 :after 渐变（40% 起黑 40%）。
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0x66000000)],
                              stops: [0.4, 1],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (badge != null)
                    Positioned(left: 10, top: 10, child: badge!),
                  if (onPlay != null)
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: _SamplePlayCircle(onTap: onPlay!),
                    ),
                  if (progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _SampleProgress(value: progress!),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MobileEnvColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                color: MobileEnvColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 样例 .poster-play：35px 白 90% 圆钮 + 深色播放图标。
class _SamplePlayCircle extends StatelessWidget {
  const _SamplePlayCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 35,
        height: 35,
        decoration: const BoxDecoration(
          color: Color(0xE6F9F9F4),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          size: 20,
          color: Color(0xFF101513),
        ),
      ),
    );
  }
}

/// 样例 .poster i / .poster i:after：3px 进度条（白 24% 底 + 酸绿填充）。
class _SampleProgress extends StatelessWidget {
  const _SampleProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      color: const Color(0x3DFFFFFF),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(color: MobileEnvColors.accent),
      ),
    );
  }
}

/// 样例 .album：145×145 圆角 17（阴影 0 12 25 黑 22%）+ 首卡酸绿播放
/// 覆盖钮（38px 圆）+ 标题 12 / 副题 9。
class SampleAlbumCard extends StatelessWidget {
  const SampleAlbumCard({
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.onPlay,
    this.showPlayOverlay = false,
    super.key,
  });

  final String? imageUrl;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final bool showPlayOverlay;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 145,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 145,
              child: Stack(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x38444444),
                          blurRadius: 25,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: SizedBox(
                        width: 145,
                        height: 145,
                        child:
                            imageUrl != null && imageUrl!.isNotEmpty
                                ? Image.network(
                                  imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (_, _, _) => const ColoredBox(
                                        color: Color(0xFF222626),
                                      ),
                                )
                                : const ColoredBox(color: Color(0xFF222626)),
                      ),
                    ),
                  ),
                  if (showPlayOverlay && onPlay != null)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: GestureDetector(
                        onTap: onPlay,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            color: MobileEnvColors.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 22,
                            color: MobileEnvColors.onAccent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MobileEnvColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                color: MobileEnvColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 样例 .reader-list 发丝线行：可选 mono 编号（9px 白 35%）+ 衬线标题
/// 15px + 副题 9px + 尾部动作槽；行高压 64、底部 1px 白 7% 线。
class SampleSerifRow extends StatelessWidget {
  const SampleSerifRow({
    required this.title,
    required this.subtitle,
    this.number,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final String? number;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: MobileEnvColors.line07)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              if (number != null) ...[
                SizedBox(
                  width: 22,
                  child: Text(
                    number!,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Color(0x59FFFFFF),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.serifFamily,
                        fontFamilyFallback: AppTypography.serifFamilyFallback,
                        fontSize: 15,
                        color: MobileEnvColors.ink,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          color: MobileEnvColors.inkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// 样例 .film-row：42×58 r10 海报 + 标题 12 / 副题 9 + 尾部更多钮位，
/// 发丝线分隔（影视 Films 档列表行）。
class SampleFilmRow extends StatelessWidget {
  const SampleFilmRow({
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String? imageUrl;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 70),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: MobileEnvColors.line07)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 42,
                  height: 58,
                  child: _SampleCoverBody(imageUrl: imageUrl),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: MobileEnvColors.ink,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          color: MobileEnvColors.inkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 样例 .album-grid：三列方形照片网格（r16 整体裁切、5px 缝），月份
/// 分组的时间线/全部图片视图使用。
class SamplePhotoGrid extends StatelessWidget {
  const SamplePhotoGrid({required this.tiles, super.key});

  final List<SamplePhotoTile> tiles;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 5,
          crossAxisSpacing: 5,
        ),
        itemCount: tiles.length,
        itemBuilder: (context, index) {
          final tile = tiles[index];
          return InkWell(
            onTap: tile.onTap,
            child: SizedBox.expand(
              child: _SampleCoverBody(imageUrl: tile.imageUrl),
            ),
          );
        },
      ),
    );
  }
}

/// 组件库共用封面占位体：网络图失败/缺图时给深灰占位。
class _SampleCoverBody extends StatelessWidget {
  const _SampleCoverBody({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return const ColoredBox(color: Color(0xFF222626));
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF222626)),
    );
  }
}

/// [SamplePhotoGrid] 的瓦片。
class SamplePhotoTile {
  const SamplePhotoTile({required this.imageUrl, this.onTap});

  final String? imageUrl;
  final VoidCallback? onTap;
}

/// 样例 .music-hero（NOW PLAYING 卡）：92 高玻璃卡 + 68 封面 + 眉标 +
/// 19px 标题 + 11px 副题 + 细进度线。
class SampleNowPlayingCard extends StatelessWidget {
  const SampleNowPlayingCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.progressText,
    this.progress = 0,
    this.onTap,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String progressText;
  final double progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xC2101615), Color(0x7D1B2421)],
          ),
          border: Border.all(color: MobileEnvColors.line15),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: SizedBox(
                width: 68,
                height: 68,
                child:
                    imageUrl != null && imageUrl!.isNotEmpty
                        ? Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, _, _) =>
                                  const ColoredBox(color: Color(0xFF222626)),
                        )
                        : const ColoredBox(color: Color(0xFF222626)),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    eyebrow.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 8,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w700,
                      color: MobileEnvColors.accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: MobileEnvColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0x85FFFFFF),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 2,
                          color: const Color(0x2EFFFFFF),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress.clamp(0.0, 1.0),
                            child: Container(color: MobileEnvColors.accent),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        progressText,
                        style: const TextStyle(
                          fontSize: 9,
                          color: MobileEnvColors.inkMuted,
                        ),
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

/// 样例 .photo-mosaic：1.45fr 1fr 1fr 三列 × 两行 120、gap 5、圆角 19；
/// 首格跨两行特写、第四格跨两列；tiles 恰为 4 张，多余由调用方截断。
class SamplePhotoMosaic extends StatelessWidget {
  const SamplePhotoMosaic({required this.tiles, super.key});

  /// 恰取 4 条：(url, overlay 可选如 +N, onTap)。
  final List<({String? url, Widget? overlay, VoidCallback? onTap})> tiles;

  @override
  Widget build(BuildContext context) {
    final list = tiles.take(4).toList();
    Widget tile(int index, {double? width, double? height}) {
      final data = list.length > index ? list[index] : null;
      return InkWell(
        onTap: data?.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (data?.url != null && data!.url!.isNotEmpty)
              Image.network(
                data.url!,
                fit: BoxFit.cover,
                errorBuilder:
                    (_, _, _) => const ColoredBox(color: Color(0xFF222626)),
              )
            else
              const ColoredBox(color: Color(0xFF222626)),
            if (data?.overlay != null) Positioned.fill(child: data!.overlay!),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(19),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 5.0;
          const rowHeight = 120.0;
          // 1.45fr : 2fr 用 flex 表达并交给布局引擎分配：手算宽度在
          // 浮点累加下会溢出数像素（Row overflowed 5px 的根因）。
          return SizedBox(
            height: rowHeight * 2 + gap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 145,
                  child: SizedBox(height: rowHeight * 2 + gap, child: tile(0)),
                ),
                const SizedBox(width: gap),
                Expanded(
                  flex: 200,
                  child: Column(
                    children: [
                      SizedBox(
                        height: rowHeight,
                        child: Row(
                          children: [
                            Expanded(child: tile(1)),
                            const SizedBox(width: gap),
                            Expanded(child: tile(2)),
                          ],
                        ),
                      ),
                      const SizedBox(height: gap),
                      SizedBox(height: rowHeight, child: tile(3)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 样例 .series-badge：左上角玻璃胶囊 mono 徽标（7px 语义档·字距 1）。
class SampleSeriesBadge extends StatelessWidget {
  const SampleSeriesBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x8C090D0C),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0x29FFFFFF)),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 7,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
          color: Color(0xCCFFFFFF),
        ),
      ),
    );
  }
}
