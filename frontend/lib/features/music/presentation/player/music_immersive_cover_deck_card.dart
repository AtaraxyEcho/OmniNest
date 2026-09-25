part of 'music_immersive_player.dart';

/// 单张封面卡：按样例档位参数放置、旋转、缩放、淡出与虚化。
class _DigitalCoverDeckCard extends StatelessWidget {
  const _DigitalCoverDeckCard({
    super.key,
    required this.palette,
    required this.track,
    required this.scale,
    required this.layout,
    required this.active,
    required this.slot,
    required this.ordinal,
    required this.total,
    this.nowPlayingLabel,
    required this.isPlaying,
    required this.hovered,
    required this.onHoverChanged,
    required this.expanded,
    this.dragging = false,
    this.dragOffset = Offset.zero,
    required this.onTap,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
  });

  final MusicImmersivePalette palette;
  final MusicTrack? track;
  final double scale;
  final PortalMusicLayout layout;
  final bool active;

  /// 档位：两侧布局 0..4，居中布局 -2..+2。
  final int slot;

  /// 该卡在卡组队列中的序号（1 起）与队列总长：卡面角标据此显示「NN / NN」。
  final int ordinal;
  final int total;

  /// 「正在播放」角标文案；为空时不渲染该角标。
  final String? nowPlayingLabel;

  /// 是否正在播放：频谱均衡器据此跳动。
  final bool isPlaying;

  /// 整卡悬停态：由卡组统一持有并回传，用于执行样例的悬停变换与描边/亮度。
  final bool hovered;
  final ValueChanged<bool> onHoverChanged;
  final bool expanded;
  final bool dragging;
  final Offset dragOffset;
  final VoidCallback onTap;
  final PointerDownEventListener? onPointerDown;
  final PointerMoveEventListener? onPointerMove;
  final PointerUpEventListener? onPointerUp;
  final PointerCancelEventListener? onPointerCancel;

  @override
  Widget build(BuildContext context) {
    final spec = resolveMusicDeckCard(
      layout,
      slot,
    ).zoomed(expanded ? _DigitalImmersiveCoverDeckState._expandedZoom : 1);
    final size = spec.size * scale;
    // 悬停态：样例逐档写死了 `data-hover-transform`，故直接取登记值。
    final offset = hovered ? spec.resolvedHoverOffset : spec.offset;
    final depth = hovered ? spec.resolvedHoverDepth : spec.depth;
    final uniformScale = hovered ? spec.resolvedHoverScale : spec.scale;
    final blur = hovered ? spec.resolvedHoverBlur : spec.blur;
    return Align(
      alignment: musicDeckStageAlignment(layout),
      child: Padding(
        padding: EdgeInsets.only(left: musicDeckStageInset(layout) * scale),
        child: AnimatedContainer(
          duration: MusicImmersiveMotion.duration(
            context,
            const Duration(milliseconds: 260),
          ),
          curve: Curves.easeOutCubic,
          width: size,
          height: size,
          // 透视由舞台统一施加，逐卡施加会让每张贴自己的消失点。
          transform: _deckCardTransform(
            spec,
            scale: scale,
            offset: offset,
            depth: depth,
            uniformScale: uniformScale,
          ),
          transformAlignment: Alignment.center,
          child: Opacity(
            opacity: spec.opacity,
            child:
                blur > 0
                    ? ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: blur * scale,
                        sigmaY: blur * scale,
                      ),
                      child: _buildCard(context, spec: spec, size: size),
                    )
                    : _buildCard(context, spec: spec, size: size),
          ),
        ),
      ),
    );
  }

  /// 样例 `transform` 的等价矩阵：位移 → 旋转 → 缩放。
  Matrix4 _deckCardTransform(
    MusicDeckCardSpec spec, {
    required double scale,
    required Offset offset,
    required double depth,
    required double uniformScale,
  }) {
    final matrix = Matrix4.identity();
    matrix.translateByDouble(
      offset.dx * scale,
      offset.dy * scale,
      depth * scale,
      1.0,
    );
    if (spec.rotateY != 0) {
      matrix.rotateY(spec.rotateY);
    }
    if (spec.rotateX != 0) {
      matrix.rotateX(spec.rotateX);
    }
    if (spec.rotateZ != 0) {
      matrix.rotateZ(spec.rotateZ);
    }
    matrix.scaleByDouble(uniformScale, uniformScale, uniformScale, 1.0);
    return matrix;
  }

  Widget _buildCard(
    BuildContext context, {
    required MusicDeckCardSpec spec,
    required double size,
  }) {
    return _DeckCardPressFeedback(
      cursor:
          onPointerDown == null
              ? SystemMouseCursors.click
              : dragging
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.grab,
      onTap: onTap,
      onHoverChanged: onHoverChanged,
      onPointerDown: onPointerDown,
      onPointerMove: onPointerMove,
      onPointerUp: onPointerUp,
      onPointerCancel: onPointerCancel,
      child: RepaintBoundary(
        // 拖拽反馈挂在最内层：拖拽只平移在读卡，不影响档位变换。
        child: AnimatedContainer(
          key: ValueKey('${track?.id ?? 'empty'}-drag-surface-$slot'),
          duration:
              dragging
                  ? Duration.zero
                  : MusicImmersiveMotion.duration(
                    context,
                    const Duration(milliseconds: 180),
                  ),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(
            dragOffset.dx * 0.62,
            dragOffset.dy * 0.28,
            0,
          ),
          transformAlignment: Alignment.center,
          child: _buildCardSurface(
            context,
            spec: spec,
            size: size,
            hovered: hovered,
          ),
        ),
      ),
    );
  }

  Widget _buildCardSurface(
    BuildContext context, {
    required MusicDeckCardSpec spec,
    required double size,
    required bool hovered,
  }) {
    final borderRadius = BorderRadius.circular(spec.radius * scale);
    final chrome = resolveMusicDeckCardChrome(
      layout,
      active: active,
      slot: slot,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: <BoxShadow>[
          // 档位投影：样例 `X Y blur spread rgba(0,0,0,A)`。
          BoxShadow(
            color: Colors.black.withValues(alpha: spec.shadowAlpha),
            blurRadius: spec.shadowBlur * scale,
            spreadRadius: spec.shadowSpread * scale,
            offset: spec.shadowOffset * scale,
          ),
          if (spec.glowAlpha > 0)
            BoxShadow(
              color: Colors.white.withValues(alpha: spec.glowAlpha),
              blurRadius: spec.glowBlur * scale,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: ColoredBox(
          // 卡面底色与描边、阴影彼此独立：居中布局的底色是半透明的。
          color: kMusicDeckCardSurfaceColor.withValues(
            alpha: spec.surfaceAlpha,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 封面悬停放大；只做亮度/对比度压暗，不做黑白处理。
              AnimatedScale(
                scale: hovered ? spec.hoverCoverScale : 1,
                duration: MusicImmersiveMotion.duration(
                  context,
                  const Duration(milliseconds: 700),
                ),
                curve: Curves.easeOutCubic,
                child: ColorFiltered(
                  colorFilter: _coverFilter(spec, hovered: hovered),
                  child: _MusicImmersiveArtwork(
                    imageUrl: track?.coverUrl,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    cacheWidth: 560,
                    cacheHeight: 560,
                    fallback: Container(
                      width: size,
                      height: size,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(
                              palette.surfaceStrong.withValues(alpha: 1),
                              palette.accent.withValues(alpha: 1),
                              0.28,
                            )!,
                            palette.surfaceStrong.withValues(alpha: 1),
                            Color.lerp(
                              palette.surfaceStrong.withValues(alpha: 1),
                              palette.accentAlt.withValues(alpha: 1),
                              0.24,
                            )!,
                          ],
                        ),
                      ),
                      child: Icon(
                        Icons.music_note_rounded,
                        color: palette.text.withValues(alpha: 0.86),
                        size: size * 0.26,
                      ),
                    ),
                  ),
                ),
              ),
              // 遮罩渐变：两侧是底部向顶部的单向压暗，居中是「底部黑 + 顶部白高光」。
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: _overlayGradient(spec)),
                  ),
                ),
              ),
              // 顶部高光细线（样例居中在读卡 `via-white/50` 的 1px）。
              if (spec.sheenAlpha > 0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: kMusicDeckCardBorderWidth * scale,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            Colors.transparent,
                            Colors.white.withValues(alpha: spec.sheenAlpha),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // CSS 边框与内阴影描边环是两层，不透明度并不相同，故分别绘制。
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      border: Border.all(
                        // 悬停态描边：样例居左 `0.75`、居右 `0.5`。
                        color: Colors.white.withValues(
                          alpha:
                              hovered
                                  ? spec.resolvedHoverBorderAlpha
                                  : spec.borderAlpha,
                        ),
                        width: kMusicDeckCardBorderWidth * scale,
                      ),
                    ),
                  ),
                ),
              ),
              if (spec.ringAlpha > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: borderRadius,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: spec.ringAlpha),
                          width: kMusicDeckCardRingWidth * scale,
                        ),
                      ),
                    ),
                  ),
                ),
              // 角标与信息带：样例的卡面层级结构。
              _buildChrome(chrome),
            ],
          ),
        ),
      ),
    );
  }

  /// 封面的档位压暗：样例 `contrast-[c] brightness-[b]` 的等价颜色矩阵。
  ColorFilter _coverFilter(MusicDeckCardSpec spec, {required bool hovered}) {
    // 悬停叠加样例的整卡 brightness(1.1)（居左）与封面 brightness-95（居右）。
    final brightness =
        spec.coverBrightness *
        (hovered ? spec.hoverBrightness * spec.hoverCoverBrightness : 1);
    final gain = spec.coverContrast * brightness;
    final offset = (0.5 - 0.5 * spec.coverContrast) * brightness * 255;
    // 不做黑白处理：r/g/b 各自独立增益，保留颜色。
    List<double> row(int channel) => <double>[
      channel == 0 ? gain : 0,
      channel == 1 ? gain : 0,
      channel == 2 ? gain : 0,
      0,
      offset,
    ];
    return ColorFilter.matrix(<double>[
      ...row(0),
      ...row(1),
      ...row(2),
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  /// 遮罩渐变：两侧是底部向顶部的单向压暗，居中是「底部黑 + 顶部白高光」。
  LinearGradient _overlayGradient(MusicDeckCardSpec spec) {
    final base = spec.overlayBlack ? Colors.black : kMusicDeckCardOverlayColor;
    return LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: <Color>[
        base.withValues(alpha: spec.overlayBottomAlpha),
        base.withValues(alpha: spec.overlayViaAlpha),
        spec.overlayTopAlpha > 0
            ? Colors.white.withValues(alpha: spec.overlayTopAlpha)
            : base.withValues(alpha: 0),
      ],
    );
  }

  /// 角标与信息带：样例每档卡片承载的装饰层级各不相同。
  Widget _buildChrome(MusicDeckCardChrome chrome) {
    final showHeroBadge = chrome.heroBadge && nowPlayingLabel != null;
    final hasChrome =
        showHeroBadge ||
        chrome.equalizer ||
        chrome.indexTag ||
        chrome.counterChip ||
        chrome.formatTag ||
        chrome.metaBand;
    if (!hasChrome) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          padding: EdgeInsets.all(chrome.padding * scale),
          child: Stack(
            children: [
              if (chrome.counterChip)
                Align(
                  alignment: chrome.counterAlignment,
                  child: _chip(_deckOrdinalLabel(), pulsingDot: active),
                ),
              if (chrome.metaBand)
                Positioned(left: 0, right: 0, bottom: 0, child: _metaBand()),
              if (showHeroBadge)
                Positioned(top: 0, left: 0, child: _heroBadge()),
              if (chrome.equalizer)
                Positioned(
                  top: 0,
                  right: 0,
                  child: _DeckEqualizerMeter(active: isPlaying, scale: scale),
                ),
              if (chrome.indexTag)
                Positioned(top: 0, right: 0, child: _indexTag()),
              if (chrome.formatTag && !chrome.indexTag)
                Positioned(top: 0, right: 0, child: _formatTag()),
            ],
          ),
        ),
      ),
    );
  }

  /// 序号／规格玻璃胶囊：样例 `bg-surface-container-lowest/90 border-white/30`。
  ///
  /// [pulsingDot] 为居中在读卡的白色呼吸点（样例 `animate-pulse` 圆点）。
  Widget _chip(
    String label, {
    double fontSize = kMusicDeckCardChipFontSize,
    bool pulsingDot = false,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kMusicDeckCardSurfaceColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6 * scale),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: kMusicDeckCardBorderWidth * scale,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 8 * scale,
          vertical: 2 * scale,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pulsingDot) ...[
              _PulsingDot(size: 6 * scale),
              SizedBox(width: 5 * scale),
            ],
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize * scale,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5 * scale,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 右上规格胶囊（仅居中在读卡）：样例只标格式（如「DSD256」），不带序号。
  Widget _formatTag() {
    final format = track?.format.trim().toUpperCase() ?? '';
    if (format.isEmpty) {
      return const SizedBox.shrink();
    }
    return _chip(format);
  }

  /// 居中布局的序号「NN / NN」。
  String _deckOrdinalLabel() {
    return '${ordinal.toString().padLeft(2, '0')}'
        ' / ${total.toString().padLeft(2, '0')}';
  }

  /// 左上「正在播放」呼吸胶囊（样例 `bg-surface-container-lowest/85` + 白点）。
  Widget _heroBadge() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kMusicDeckCardSurfaceColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: kMusicDeckCardBorderWidth * scale,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12 * scale,
          vertical: 4 * scale,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8 * scale,
              height: 8 * scale,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 6 * scale),
            Text(
              nowPlayingLabel!.toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: kMusicDeckCardChipFontSize * scale,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6 * scale,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 右上序号胶囊「NN · 规格」：样例非在读卡用它替代在读卡的品徽。
  Widget _indexTag() {
    final format = track?.format.trim().toUpperCase() ?? '';
    final label =
        format.isEmpty
            ? ordinal.toString().padLeft(2, '0')
            : '${ordinal.toString().padLeft(2, '0')} · $format';
    return _chip(label);
  }

  /// 底部信息带：规格胶囊 + 曲名 + 艺术家（样例 `bottom-4 left-4 right-4`）。
  Widget _metaBand() {
    final format = track?.format.trim().toUpperCase() ?? '';
    final title = track?.title.trim() ?? '';
    final artist = track?.artistName.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (format.isNotEmpty) ...[_chip(format), SizedBox(height: 6 * scale)],
        if (title.isNotEmpty)
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: kMusicDeckCardTitleFontSize * scale,
              height: kMusicDeckCardTitleHeightRatio,
              fontWeight: FontWeight.w600,
              letterSpacing:
                  kMusicDeckCardTitleLetterSpacing *
                  kMusicDeckCardTitleFontSize *
                  scale,
              shadows: <Shadow>[
                Shadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 12 * scale,
                ),
              ],
            ),
          ),
        if (artist.isNotEmpty) ...[
          SizedBox(height: kMusicDeckCardArtistGap * scale),
          Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: kMusicLyricTranslationColor,
              fontSize: kMusicDeckCardArtistFontSize * scale,
              height: kMusicDeckCardArtistHeightRatio,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }
}
