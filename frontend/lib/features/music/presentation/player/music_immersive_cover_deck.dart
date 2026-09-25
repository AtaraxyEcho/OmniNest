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
  /// 侧布局每档只露出窄边，在读卡的投影又会盖住大半，仅靠变换后的命中测试
  /// 几乎点不到，因此补一段透明命中区。命中条与对应的档位卡共享悬停键：
  /// 命中条悬停时直接点亮该卡（样例的悬停拉出反馈），点击仍由命中条选中。
  /// 命中条不与在读卡重叠。
  List<Widget> _buildCardHitStrips(Size stageSize) {
    switch (widget.layout) {
      case PortalMusicLayout.left:
      case PortalMusicLayout.right:
        return _buildSideLayoutHitStrips(stageSize);
      case PortalMusicLayout.center:
        // 居中布局：透视变换下的命中测试有偏差，侧卡的露出带同样用命中条
        // 兜底（悬停拉出 + 点击切换），否则只能靠拖拽换卡。
        return _buildCenterHitStrips(stageSize);
    }
  }

  /// 居中布局的命中条：按各侧卡露出带逐条布置（左右各两条，外层优先）。
  List<Widget> _buildCenterHitStrips(Size stageSize) {
    final scale = widget.scale;
    final centerX = stageSize.width / 2;
    final activeSize = resolveMusicDeckCard(widget.layout, 0).size * scale;
    final heroLeft = centerX - activeSize / 2;
    final heroRight = centerX + activeSize / 2;
    Widget strip({
      required Key key,
      required double left,
      required double width,
      required double top,
      required double height,
      required VoidCallback onTap,
      required ValueChanged<bool> onHover,
    }) {
      return Positioned(
        key: key,
        left: left,
        width: width,
        top: top,
        height: height,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => onHover(true),
          onExit: (_) => onHover(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: const SizedBox.expand(),
          ),
        ),
      );
    }

    final strips = <Widget>[];
    // 每侧都从在读卡外缘向外推进。内侧档卡面更大、其外缘反而更靠内，若按
    // 由外向内推进，内侧档会算出负宽度并被整条丢弃——表现为紧贴在读卡的两档
    // 既点不动也不响应悬停。卡面尺寸要乘档位缩放，否则条带比真实像素宽。
    for (final side in <int>[-1, 1]) {
      var edge = side < 0 ? heroLeft : heroRight;
      for (final slot in <int>[side, side * 2]) {
        final index = _resolveSlotIndex(slot);
        if (index == null) {
          continue;
        }
        final spec = resolveMusicDeckCard(widget.layout, slot);
        final cardSize = spec.size * scale * spec.scale;
        final cardCenterX = centerX + spec.offset.dx * scale;
        final outerEdge =
            side < 0 ? cardCenterX - cardSize / 2 : cardCenterX + cardSize / 2;
        final bandLeft = side < 0 ? outerEdge : edge;
        final bandRight = side < 0 ? edge : outerEdge;
        edge = outerEdge;
        final bandWidth = bandRight - bandLeft;
        if (bandWidth <= 0) {
          continue;
        }
        final cardTop =
            stageSize.height / 2 + spec.offset.dy * scale - cardSize / 2;
        strips.add(
          strip(
            key: ValueKey('deck-hit-strip-$slot'),
            left: bandLeft,
            width: bandWidth,
            top: cardTop,
            height: cardSize,
            onTap: () => widget.onSelected(index),
            onHover:
                (hovered) => _onCardHoverChanged(
                  _deckCardHoverKey(index, slot),
                  hovered,
                ),
          ),
        );
      }
    }
    return strips;
  }

  /// 两侧布局的命中条顺序：由内向外，与绘制顺序相反。
  /// 按绘制顺序生成时内侧宽条最后入栈，会把外侧各档全部盖住。
  static const _sideHitSlotOrder = <int>[1, 2, 3, 4];

  /// 两侧布局（居左/居右）的命中条：每档只占上一档右缘到本档右缘的露出带。
  List<Widget> _buildSideLayoutHitStrips(Size stageSize) {
    final scale = widget.scale;
    final inset = musicDeckStageInset(widget.layout) * scale;
    final activeSize = resolveMusicDeckCard(widget.layout, 0).size * scale;
    final top = (stageSize.height - activeSize) / 2;
    final strips = <Widget>[];
    var innerEdge = inset + activeSize;
    for (final slot in _sideHitSlotOrder) {
      final index = _resolveSlotIndex(slot);
      if (index == null) {
        continue;
      }
      final spec = resolveMusicDeckCard(widget.layout, slot);
      final outerEdge = inset + spec.offset.dx * scale + spec.size * scale;
      final width = outerEdge - innerEdge;
      if (width <= 0) {
        // 该档被内侧卡完全遮住，没有独立露出带；推进边界保持不变。
        continue;
      }
      final bandLeft = innerEdge;
      innerEdge = outerEdge;
      strips.add(
        Positioned(
          key: ValueKey('deck-hit-strip-$slot'),
          left: bandLeft,
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
