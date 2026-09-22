part of 'music_immersive_player.dart';

/// 桌面沉浸播放器的封面卡组：居左等距 3D 纵叠、居右 2D 阶梯错层、
/// 居中对称扇形，全部按样例逐档复刻。
class MusicImmersiveCoverDeck extends StatefulWidget {
  const MusicImmersiveCoverDeck({
    super.key,
    required this.palette,
    required this.tracks,
    required this.selectedIndex,
    required this.currentTrack,
    required this.expanded,
    required this.scale,
    required this.layout,
    required this.isPlaying,
    required this.stageSize,
    required this.onSelected,
    required this.onStep,
    this.nowPlayingLabel,
  });

  final MusicImmersivePalette palette;
  final List<MusicTrack> tracks;
  final int selectedIndex;
  final MusicTrack? currentTrack;
  final bool expanded;
  final double scale;

  /// 卡面「正在播放」角标文案；由舞台注入，为空时不渲染。
  final String? nowPlayingLabel;

  /// 卡组形态，与歌词位置设置同一枚举。
  final PortalMusicLayout layout;

  /// 是否正在播放：卡面频谱均衡器据此决定是否跳动（样例只在播放时动）。
  final bool isPlaying;

  /// 舞台尺寸，由舞台按卡组矩形传入，供透视原点与命中条定位使用。
  final Size stageSize;
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onStep;

  @override
  State<MusicImmersiveCoverDeck> createState() =>
      _DigitalImmersiveCoverDeckState();
}

class _DigitalImmersiveCoverDeckState extends State<MusicImmersiveCoverDeck> {
  /// 两侧布局的绘制顺序：最远一档先画，在读卡最后画。
  static const _deckPaintOrder = <int>[4, 3, 2, 1];

  /// 居中布局的绘制顺序：外侧两档先画，内侧两档后画。
  static const _centerPaintOrder = <int>[-2, 2, -1, 1];

  /// 展开态的卡面与档位间距放大系数（双击/右键切换）。
  static const _expandedZoom = 1.08;

  Offset _activeCardDragOffset = Offset.zero;
  int? _dragPointer;
  Offset? _dragOrigin;
  bool _dragActive = false;
  bool _thresholdFeedbackSent = false;

  /// 当前悬停的卡片键：悬停是整卡级别，由卡组统一持有。
  String? _hoveredCardKey;

  /// 待提交的悬停键：指针事件派发期间先记下，帧外再提交。
  String? _pendingHoverKey;

  List<int> get _paintOrder =>
      widget.layout == PortalMusicLayout.center
          ? _centerPaintOrder
          : _deckPaintOrder;

  /// 悬停变化回调：同一时刻只可能有一张卡处于悬停态。
  ///
  /// 回调发生在指针事件派发期间，同步 setState 会改动 MouseRegion 标注并触发
  /// `MouseTracker` 的 `!_debugDuringDeviceUpdate` 断言，因此推迟到微任务提交。
  void _onCardHoverChanged(String cardKey, bool hovered) {
    final next = hovered ? cardKey : null;
    if (_pendingHoverKey == next) {
      return;
    }
    _pendingHoverKey = next;
    scheduleMicrotask(() {
      if (!mounted) {
        return;
      }
      final target = _pendingHoverKey;
      _pendingHoverKey = null;
      if (_hoveredCardKey == target) {
        return;
      }
      setState(() => _hoveredCardKey = target);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 卡组是纯装饰交互（点击/拖拽/悬停变换）：排除出语义树，悬停与拖拽的
    // 逐帧变换不再制造语义更新（Windows 辅助功能桥在大幅语义更新下报
    // "Nodes left pending by the update"）。选曲对读屏用户仍可经队列
    // 抽屉与上一首/下一首按键到达，卡片本身无键盘焦点路径。
    return ExcludeSemantics(
      child: Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent) {
            return;
          }
          if (event.scrollDelta.dy > 6) {
            widget.onStep(1);
          } else if (event.scrollDelta.dy < -6) {
            widget.onStep(-1);
          }
        },
        child: Builder(
          builder: (context) {
            final perspective =
                musicDeckPerspective(widget.layout) * widget.scale;
            final stageSize = widget.stageSize;
            final stage = Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children:
                  widget.tracks.isEmpty
                      ? [_buildPlaceholderCard()]
                      : [
                        for (final slot in _paintOrder)
                          _buildStaticDeckCard(slot),
                        _buildActiveDeckCard(),
                        ..._buildCardHitStrips(stageSize),
                      ],
            );
            if (perspective <= 0) {
              // 居右布局是纯 2D 阶梯，样例没有透视。
              return stage;
            }
            // 样例的透视与透视原点挂在舞台容器上，所有卡共享同一消失点。
            return Transform(
              transform: Matrix4.identity()..setEntry(3, 2, -1 / perspective),
              origin: Offset(stageSize.width * 0.25, stageSize.height * 0.42),
              child: stage,
            );
          },
        ),
      ),
    );
  }

  /// 后排卡片的显式命中条：只覆盖在读卡右缘到该档右缘之间的露出带。
  ///
  /// 两侧布局每档只露出窄边，在读卡的投影又会盖住大半，仅靠变换后的命中测试
  /// 几乎点不到，因此补一段透明命中区。命中条与对应的档位卡共享悬停键：
  /// 命中条悬停时直接点亮该卡（样例的悬停拉出反馈），点击仍由命中条选中。
  /// 命中条不与在读卡重叠。
  List<Widget> _buildCardHitStrips(Size stageSize) {
    if (widget.layout != PortalMusicLayout.left &&
        widget.layout != PortalMusicLayout.right) {
      // 居中布局两侧位移很大（±125/±230），后卡本来就大面积露出。
      return const <Widget>[];
    }
    final scale = widget.scale;
    final inset = musicDeckStageInset(widget.layout) * scale;
    final activeSize = resolveMusicDeckCard(widget.layout, 0).size * scale;
    final left = inset + activeSize;
    final top = (stageSize.height - activeSize) / 2;
    final strips = <Widget>[];
    for (final slot in _paintOrder) {
      final index = _resolveSlotIndex(slot);
      if (index == null) {
        continue;
      }
      final spec = resolveMusicDeckCard(widget.layout, slot);
      final width = inset + spec.offset.dx * scale + spec.size * scale - left;
      if (width <= 0) {
        continue;
      }
      strips.add(
        Positioned(
          key: ValueKey('deck-hit-strip-$slot'),
          left: left,
          width: width,
          top: top,
          height: activeSize,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter:
                (_) =>
                    _onCardHoverChanged(_deckCardHoverKey(index, slot), true),
            onExit:
                (_) =>
                    _onCardHoverChanged(_deckCardHoverKey(index, slot), false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelected(index),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
    }
    return strips;
  }

  /// 档位卡的悬停键：卡片自身与命中条共用同一键。
  String _deckCardHoverKey(int index, int slot) {
    return '${widget.tracks[index].id}-$slot';
  }

  Widget _buildPlaceholderCard() {
    return _DigitalCoverDeckCard(
      palette: widget.palette,
      track: widget.currentTrack,
      scale: widget.scale,
      layout: widget.layout,
      active: true,
      slot: 0,
      ordinal: 1,
      total: 1,
      nowPlayingLabel: widget.nowPlayingLabel,
      isPlaying: widget.isPlaying,
      hovered: _hoveredCardKey == 'placeholder',
      onHoverChanged: (hovered) => _onCardHoverChanged('placeholder', hovered),
      expanded: widget.expanded,
      dragging: _dragActive,
      dragOffset: _activeCardDragOffset,
      onTap: () {},
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
    );
  }

  Widget _buildStaticDeckCard(int slot) {
    final index = _resolveSlotIndex(slot);
    if (index == null) {
      return const SizedBox.shrink();
    }
    return _DigitalCoverDeckCard(
      key: ValueKey(_deckCardHoverKey(index, slot)),
      palette: widget.palette,
      track: widget.tracks[index],
      scale: widget.scale,
      layout: widget.layout,
      active: false,
      slot: slot,
      ordinal: index + 1,
      total: widget.tracks.length,
      nowPlayingLabel: widget.nowPlayingLabel,
      isPlaying: widget.isPlaying,
      hovered: _hoveredCardKey == _deckCardHoverKey(index, slot),
      onHoverChanged:
          (hovered) =>
              _onCardHoverChanged(_deckCardHoverKey(index, slot), hovered),
      expanded: widget.expanded,
      onTap: () => widget.onSelected(index),
    );
  }

  Widget _buildActiveDeckCard() {
    final index = widget.selectedIndex;
    if (index < 0 || index >= widget.tracks.length) {
      return const SizedBox.shrink();
    }
    return _DigitalCoverDeckCard(
      key: ValueKey('${widget.tracks[index].id}-active'),
      palette: widget.palette,
      track: widget.tracks[index],
      scale: widget.scale,
      layout: widget.layout,
      active: true,
      slot: 0,
      ordinal: index + 1,
      total: widget.tracks.length,
      nowPlayingLabel: widget.nowPlayingLabel,
      isPlaying: widget.isPlaying,
      hovered: _hoveredCardKey == '${widget.tracks[index].id}-active',
      onHoverChanged:
          (hovered) =>
              _onCardHoverChanged('${widget.tracks[index].id}-active', hovered),
      expanded: widget.expanded,
      dragging: _dragActive,
      dragOffset: _activeCardDragOffset,
      onTap: () => widget.onSelected(index),
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
    );
  }

  /// 该档位对应的队列下标；队列不足以撑起该档位时返回 null。
  int? _resolveSlotIndex(int slot) {
    final count = widget.tracks.length;
    if (count < 2 || slot == 0) {
      return null;
    }
    if (widget.layout == PortalMusicLayout.center) {
      if (slot.abs() > kMusicCenterDeckHalfSlots || slot.abs() * 2 >= count) {
        return null;
      }
    } else if (slot > kMusicSideDeckSlots || slot >= count) {
      return null;
    }
    return (widget.selectedIndex + slot) % count;
  }

  void _handlePointerDown(PointerDownEvent event) {
    final secondaryMouseDown =
        event.kind == PointerDeviceKind.mouse &&
        event.buttons == kSecondaryMouseButton;
    if (secondaryMouseDown || _dragPointer != null) {
      return;
    }
    _dragPointer = event.pointer;
    _dragOrigin = event.position;
    setState(() {
      _dragActive = true;
      _activeCardDragOffset = Offset.zero;
      _thresholdFeedbackSent = false;
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _dragPointer) {
      return;
    }
    _updateCardDrag(event.position);
  }

  void _updateCardDrag(Offset position) {
    final origin = _dragOrigin;
    if (origin == null) {
      return;
    }
    final maxOffset = (150 * widget.scale).clamp(110.0, 190.0).toDouble();
    final delta = position - origin;
    final nextOffset = Offset(
      delta.dx.clamp(-maxOffset, maxOffset).toDouble(),
      delta.dy.clamp(-maxOffset, maxOffset).toDouble(),
    );
    if (!_thresholdFeedbackSent &&
        _dominantDrag(nextOffset).abs() >= _dragThreshold) {
      _thresholdFeedbackSent = true;
      unawaited(HapticFeedback.selectionClick());
    }
    setState(() => _activeCardDragOffset = nextOffset);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _dragPointer) {
      return;
    }
    final delta = _resolveDragDelta(_activeCardDragOffset);
    final target =
        (widget.selectedIndex + delta)
            .clamp(0, math.max(0, widget.tracks.length - 1))
            .toInt();
    _resetDrag();
    if (delta == 0 || target == widget.selectedIndex) {
      return;
    }
    unawaited(HapticFeedback.mediumImpact());
    widget.onSelected(target);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _dragPointer) {
      return;
    }
    _resetDrag();
  }

  void _resetDrag() {
    if (!mounted) {
      return;
    }
    _clearPointerTracking();
    setState(() {
      _dragActive = false;
      _activeCardDragOffset = Offset.zero;
      _thresholdFeedbackSent = false;
    });
  }

  void _clearPointerTracking() {
    _dragPointer = null;
    _dragOrigin = null;
  }

  double _dominantDrag(Offset offset) {
    return offset.dx.abs() >= offset.dy.abs() ? offset.dx : offset.dy;
  }

  int _resolveDragDelta(Offset offset) {
    final drag = _dominantDrag(offset);
    if (drag.abs() < _dragThreshold) {
      return 0;
    }
    return drag.isNegative ? 1 : -1;
  }

  double get _dragThreshold => (46 * widget.scale).clamp(36.0, 62.0).toDouble();
}

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

/// 卡面右上的频谱均衡器条（样例五根白色竖条，高低错落且**播放时各自跳动**）。
class _DeckEqualizerMeter extends StatefulWidget {
  const _DeckEqualizerMeter({required this.active, required this.scale});

  /// 是否正在播放：样例的频谱只在播放时跳动，暂停后停在基准高度。
  final bool active;
  final double scale;

  /// 样例五根竖条的高度（`h-3 / h-5 / h-2 / h-4 / h-2.5` → px）。
  static const List<double> baseHeights = <double>[12, 20, 8, 16, 10];

  /// 样例五根竖条各自的跳动周期（`animate-[bounce_1.2s_infinite]` 等，秒）。
  static const List<double> periodSeconds = <double>[1.2, 0.8, 1.5, 1.0, 0.9];

  @override
  State<_DeckEqualizerMeter> createState() => _DeckEqualizerMeterState();
}

class _DeckEqualizerMeterState extends State<_DeckEqualizerMeter>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;
  bool _motionDisabled = false;

  @override
  void initState() {
    super.initState();
    _controllers = <AnimationController>[
      for (final period in _DeckEqualizerMeter.periodSeconds)
        AnimationController(
          vsync: this,
          duration: Duration(milliseconds: (period * 1000).round()),
          value: 0.5,
        ),
    ];
    _animations = <Animation<double>>[
      for (final controller in _controllers)
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
    ];
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionDisabled = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant _DeckEqualizerMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _sync();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 播放时每根竖条各自错峰跳动；暂停或系统禁用动画时停在基准高度。
  void _sync() {
    if (!widget.active || _motionDisabled) {
      for (final controller in _controllers) {
        controller.stop();
      }
      return;
    }
    for (final controller in _controllers) {
      if (!controller.isAnimating) {
        controller.repeat(reverse: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kMusicDeckCardSurfaceColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: kMusicDeckCardBorderWidth * scale,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12 * scale,
          vertical: 6 * scale,
        ),
        // 纯装饰动效：竖条每帧改高度，若进入语义树，Windows 辅助功能桥会
        // 每帧重建 AXTree（error: 154），因此整体排除出语义树。
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < _controllers.length; i++) ...[
                AnimatedBuilder(
                  animation: _animations[i],
                  builder: (context, _) {
                    // bounce 的摆幅取基准高度的 60%，与样例的视觉幅度接近。
                    final swing = 1 + 0.6 * _animations[i].value;
                    return Container(
                      width: 2 * scale,
                      height:
                          _DeckEqualizerMeter.baseHeights[i] * swing * scale,
                      decoration: const BoxDecoration(color: Colors.white),
                    );
                  },
                ),
                SizedBox(width: 4 * scale),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 白色呼吸圆点（样例 `animate-pulse`）：角标播放态指示，尊重减少动态效果。
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.size});

  final double size;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0.6;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 纯装饰的逐帧透明度动画：排除出语义树，避免辅助功能桥逐帧重建。
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Opacity(
            // pulse 的呼吸区间：满亮到 0.4，与 Tailwind pulse 的幅度一致。
            opacity: 0.4 + 0.6 * _controller.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DeckCardPressFeedback extends StatefulWidget {
  const _DeckCardPressFeedback({
    required this.cursor,
    required this.onTap,
    required this.onHoverChanged,
    required this.child,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
  });

  final MouseCursor cursor;
  final VoidCallback onTap;
  final ValueChanged<bool> onHoverChanged;
  final Widget child;
  final PointerDownEventListener? onPointerDown;
  final PointerMoveEventListener? onPointerMove;
  final PointerUpEventListener? onPointerUp;
  final PointerCancelEventListener? onPointerCancel;

  @override
  State<_DeckCardPressFeedback> createState() => _DeckCardPressFeedbackState();
}

class _DeckCardPressFeedbackState extends State<_DeckCardPressFeedback> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => widget.onHoverChanged(true),
      onExit: (_) => widget.onHoverChanged(false),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.kind != PointerDeviceKind.mouse ||
              event.buttons != kSecondaryMouseButton) {
            setState(() => _pressed = true);
          }
          widget.onPointerDown?.call(event);
        },
        onPointerMove: widget.onPointerMove,
        onPointerUp: (event) {
          if (_pressed) {
            setState(() => _pressed = false);
          }
          widget.onPointerUp?.call(event);
        },
        onPointerCancel: (event) {
          if (_pressed) {
            setState(() => _pressed = false);
          }
          widget.onPointerCancel?.call(event);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.965 : 1,
            duration: MusicImmersiveMotion.duration(
              context,
              Duration(milliseconds: _pressed ? 90 : 180),
            ),
            curve: Curves.easeOutCubic,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
