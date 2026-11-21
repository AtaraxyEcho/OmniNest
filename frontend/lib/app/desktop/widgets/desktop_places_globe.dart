import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/features/photos/domain/photo.dart';

/// 地点（样例 `Globe.tsx` 的 `GlobePlace`）：名称、照片数、经纬度与封面图。
class DesktopGlobePlace {
  const DesktopGlobePlace({
    required this.name,
    required this.count,
    required this.latitude,
    required this.longitude,
    this.coverPhoto,
  });

  final String name;
  final int count;
  final double latitude;
  final double longitude;
  final PhotoItem? coverPhoto;
}

/// 可拖动点阵地球（对齐 `Globe.tsx:95-136` & `desktop.css:350-352`）：
/// 通透大气球体 + 30° 完整经纬网 + 主题自适应大陆点阵 + 全可见 Pin 脉冲环 +
/// 悬停/选中毛玻璃 `.pin-card` 缩略图卡片 + 底部拖拽提示胶囊。
class DesktopPlacesGlobe extends StatefulWidget {
  const DesktopPlacesGlobe({
    required this.places,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final List<DesktopGlobePlace> places;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  State<DesktopPlacesGlobe> createState() => _DesktopPlacesGlobeState();
}

class _DesktopPlacesGlobeState extends State<DesktopPlacesGlobe>
    with TickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: MotionToken.resolveForPlatform(DesktopMotion.globeTurn),
  );
  late final AnimationController _ping = AnimationController(
    vsync: this,
    duration: DesktopMotion.placePing,
  );

  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  double _lon = 12;
  double _lat = 18;
  bool _dragging = false;
  String? _hoveredPlace;

  @override
  void initState() {
    super.initState();
    _turn.addListener(() {
      final t = Curves.easeOutCubic.transform(_turn.value);
      setState(() {
        _lon = _from.dx + (_to.dx - _from.dx) * t;
        _lat = _from.dy + (_to.dy - _from.dy) * t;
      });
    });
    _faceSelected(animate: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPing();
  }

  @override
  void didUpdateWidget(DesktopPlacesGlobe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _faceSelected(animate: true);
    } else if (oldWidget.places.isEmpty && widget.places.isNotEmpty) {
      _faceSelected(animate: false);
    }
    _syncPing();
  }

  void _syncPing() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // 只有选中地标才需要脉冲；否则这个 2.4s 循环会让整颗地球常驻一个 ticker。
    if (widget.selected != null && widget.places.isNotEmpty && !reduce) {
      if (!_ping.isAnimating) {
        _ping.repeat();
      }
    } else {
      _ping.stop();
      _ping.value = 0;
    }
  }

  @override
  void dispose() {
    _ping.dispose();
    _turn.dispose();
    super.dispose();
  }

  void _faceSelected({required bool animate}) {
    final place =
        widget.places
            .where((entry) => entry.name == widget.selected)
            .firstOrNull ??
        widget.places.firstOrNull;
    if (place == null) {
      return;
    }
    final targetLat = (place.latitude * 0.6).clamp(-25.0, 55.0);
    if (!animate) {
      _lon = place.longitude;
      _lat = targetLat;
      return;
    }
    _from = Offset(_lon, _lat);
    final dLon = (place.longitude - _lon + 540) % 360 - 180;
    _to = Offset(_lon + dLon, targetLat);
    _turn.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 420.0;
        final maxH =
            constraints.maxHeight.isFinite ? constraints.maxHeight - 36 : 420.0;
        final size = math.min(maxW, maxH).clamp(240.0, 420.0);
        final radius = size / 2 - 6;

        final projectedPins = <({DesktopGlobePlace place, _Projected q})>[];
        for (final place in widget.places) {
          final q = _project(place.longitude, place.latitude, _lon, _lat);
          if (q.z > 0.08) {
            projectedPins.add((place: place, q: q));
          }
        }
        // 选中或悬停的 Pin 置顶渲染，确保 .pin-card 不被其他点遮挡。
        projectedPins.sort((a, b) {
          final aTop =
              a.place.name == _hoveredPlace
                  ? 2
                  : (a.place.name == widget.selected ? 1 : 0);
          final bTop =
              b.place.name == _hoveredPlace
                  ? 2
                  : (b.place.name == widget.selected ? 1 : 0);
          return aTop.compareTo(bTop);
        });

        return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MouseRegion(
              cursor:
                  _dragging
                      ? SystemMouseCursors.grabbing
                      : SystemMouseCursors.grab,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) {
                  _turn.stop();
                  if (!_dragging) {
                    setState(() => _dragging = true);
                  }
                },
                onPanUpdate: (details) {
                  _turn.stop();
                  final degPerPx = (110.0 / size) * 1.6;
                  setState(() {
                    _lon -= details.delta.dx * degPerPx;
                    _lat = (_lat + details.delta.dy * degPerPx).clamp(
                      -70.0,
                      70.0,
                    );
                  });
                },
                onPanEnd: (_) {
                  if (_dragging) {
                    setState(() => _dragging = false);
                  }
                },
                onPanCancel: () {
                  if (_dragging) {
                    setState(() => _dragging = false);
                  }
                },
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          key: const ValueKey('places-globe-canvas'),
                          child: CustomPaint(
                            painter: _GlobePainter(
                              lon: _lon,
                              lat: _lat,
                              ink: skin.text,
                            ),
                          ),
                        ),
                      ),
                      for (final item in projectedPins)
                        _GlobePin(
                          key: ValueKey('globe-pin-${item.place.name}'),
                          place: item.place,
                          position: Offset(
                            size / 2 + radius * item.q.x,
                            size / 2 + radius * item.q.y,
                          ),
                          pinOpacity: (item.q.z * 3.0).clamp(0.0, 1.0),
                          selected: item.place.name == widget.selected,
                          hovered: item.place.name == _hoveredPlace,
                          ping: _ping,
                          accent: skin.accent,
                          popColor: skin.pop,
                          line2Color: skin.line2,
                          textColor: skin.text,
                          text3Color: skin.text3,
                          shadow: skin.shadow,
                          countLabel: l10n.desktopPhotosPlaceCount(
                            item.place.count,
                          ),
                          onHoverChanged: (hovering) {
                            setState(() {
                              if (hovering) {
                                _hoveredPlace = item.place.name;
                              } else if (_hoveredPlace == item.place.name) {
                                _hoveredPlace = null;
                              }
                            });
                          },
                          onTap: () => widget.onSelect(item.place.name),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: skin.raise,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: skin.line),
              ),
              child: Text(
                isZh ? '拖拽旋转' : 'Drag to rotate',
                style: DesktopType.caption(skin.text3),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GlobePin extends StatelessWidget {
  const _GlobePin({
    required this.place,
    required this.position,
    required this.pinOpacity,
    required this.selected,
    required this.hovered,
    required this.ping,
    required this.accent,
    required this.popColor,
    required this.line2Color,
    required this.textColor,
    required this.text3Color,
    required this.shadow,
    required this.countLabel,
    required this.onHoverChanged,
    required this.onTap,
    super.key,
  });

  final DesktopGlobePlace place;
  final Offset position;
  final double pinOpacity;
  final bool selected;
  final bool hovered;
  final Animation<double> ping;
  final Color accent;
  final Color popColor;
  final Color line2Color;
  final Color textColor;
  final Color text3Color;
  final List<BoxShadow> shadow;
  final String countLabel;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final showCard = selected || hovered;
    final shortName = place.name.split(',').first.trim();
    final displayName = shortName.isEmpty ? place.name : shortName;

    return Positioned(
      left: position.dx - 9,
      top: position.dy - 9,
      width: 18,
      height: 18,
      child: Opacity(
        opacity: pinOpacity,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // `.pin b`: ping 2.4s ease-out infinite —— 只为选中的地标挂独立脉冲层，
            // 否则每个 pin 都常驻一个 ticker/RepaintBoundary，整颗地球每帧重绘。
            if (selected)
              Positioned(
                left: -6,
                top: -6,
                right: -6,
                bottom: -6,
                child: IgnorePointer(
                  child: RepaintBoundary(
                    key: const ValueKey('places-globe-ping'),
                    child: AnimatedBuilder(
                      animation: ping,
                      builder: (context, _) {
                        final t = Curves.easeOut.transform(ping.value);
                        return Opacity(
                          opacity: (0.9 * (1.0 - t)).clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 0.5 + 1.7 * t,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: accent, width: 1.5),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            // `.pin-card`: 悬停或选中时浮现毛玻璃缩略图卡片
            Positioned(
              bottom: 26,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: DesktopMotion.of(context, DesktopMotion.soft),
                  curve: DesktopMotion.ease,
                  opacity: showCard ? 1.0 : 0.0,
                  child: AnimatedSlide(
                    duration: DesktopMotion.of(context, DesktopMotion.soft),
                    curve: DesktopMotion.spring,
                    offset: showCard ? Offset.zero : const Offset(0, 0.18),
                    child: AnimatedScale(
                      duration: DesktopMotion.of(context, DesktopMotion.soft),
                      curve: DesktopMotion.spring,
                      scale: showCard ? 1.0 : 0.9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                            decoration: BoxDecoration(
                              color: popColor,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: line2Color),
                              boxShadow: shadow,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: DesktopImage(
                                    url: place.coverPhoto?.coverUrl,
                                    cacheWidth: 160,
                                    fallbackIcon: DesktopIcons.pin,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: DesktopType.rowTitle(
                                        textColor,
                                      ).copyWith(
                                        fontSize: 13,
                                      ), // ignore: font_size_whitelist
                                    ),
                                    Text(
                                      countLabel,
                                      maxLines: 1,
                                      style: DesktopType.caption(text3Color),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // `.pin i`: 中心圆点 + 悬停/选中 1.6x 弹簧放大
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => onHoverChanged(true),
              onExit: (_) => onHoverChanged(false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Center(
                  child: AnimatedScale(
                    duration: DesktopMotion.of(context, DesktopMotion.soft),
                    curve: DesktopMotion.spring,
                    scale: showCard ? 1.6 : 1.0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.30),
                            blurRadius: 0,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Projected {
  const _Projected(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

const double _rad = math.pi / 180;

/// 正交投影：返回 -1..1 的屏幕偏移与是否朝向观察者。
_Projected _project(
  double lon,
  double lat,
  double centerLon,
  double centerLat,
) {
  final dLon = (lon - centerLon) * _rad;
  final phi = lat * _rad;
  final c0 = centerLat * _rad;
  final x = math.cos(phi) * math.sin(dLon);
  final y =
      math.cos(c0) * math.sin(phi) -
      math.sin(c0) * math.cos(phi) * math.cos(dLon);
  final z =
      math.sin(c0) * math.sin(phi) +
      math.cos(c0) * math.cos(phi) * math.cos(dLon);
  return _Projected(x, -y, z);
}

/// 粗粒度大陆轮廓（[lon, lat] 环），照抄样例 `LAND`：只用来生成点，
/// 不描边、不标注。
const List<List<List<double>>> _land = [
  [
    [-168, 66],
    [-140, 70],
    [-110, 72],
    [-82, 70],
    [-62, 60],
    [-56, 50],
    [-66, 44],
    [-76, 36],
    [-81, 25],
    [-97, 22],
    [-88, 15],
    [-78, 8],
    [-92, 14],
    [-106, 22],
    [-118, 33],
    [-125, 42],
    [-125, 50],
    [-140, 59],
    [-158, 58],
    [-168, 66],
  ],
  [
    [-73, 12],
    [-60, 10],
    [-50, 0],
    [-35, -6],
    [-39, -20],
    [-50, -30],
    [-58, -38],
    [-66, -47],
    [-72, -54],
    [-75, -42],
    [-71, -20],
    [-81, -5],
    [-78, 3],
    [-73, 12],
  ],
  [
    [-52, 60],
    [-44, 60],
    [-22, 70],
    [-20, 80],
    [-45, 83],
    [-62, 80],
    [-70, 76],
    [-52, 60],
  ],
  [
    [-10, 36],
    [-9, 43],
    [-1, 48],
    [-5, 50],
    [5, 54],
    [8, 58],
    [5, 62],
    [14, 68],
    [25, 71],
    [32, 70],
    [40, 66],
    [30, 60],
    [30, 50],
    [38, 46],
    [28, 41],
    [24, 37],
    [16, 38],
    [12, 44],
    [3, 43],
    [-6, 36],
    [-10, 36],
  ],
  [
    [-17, 21],
    [-10, 31],
    [-6, 36],
    [10, 37],
    [20, 32],
    [32, 31],
    [43, 12],
    [51, 11],
    [40, -3],
    [40, -15],
    [33, -26],
    [20, -35],
    [14, -23],
    [12, -6],
    [9, 4],
    [-8, 4],
    [-17, 14],
    [-17, 21],
  ],
  [
    [28, 41],
    [40, 40],
    [50, 38],
    [60, 42],
    [70, 55],
    [60, 68],
    [80, 74],
    [110, 77],
    [140, 72],
    [170, 68],
    [160, 58],
    [141, 52],
    [135, 43],
    [122, 40],
    [121, 30],
    [108, 21],
    [100, 13],
    [104, 1],
    [98, 8],
    [92, 22],
    [80, 14],
    [73, 20],
    [66, 25],
    [57, 25],
    [48, 30],
    [36, 36],
    [28, 41],
  ],
  [
    [44, 12],
    [52, 16],
    [58, 23],
    [50, 27],
    [40, 28],
    [34, 28],
    [44, 12],
  ],
  [
    [114, -22],
    [122, -17],
    [131, -12],
    [142, -11],
    [153, -26],
    [150, -37],
    [140, -38],
    [130, -32],
    [115, -34],
    [114, -22],
  ],
  [
    [130, 31],
    [135, 33.2],
    [140, 35],
    [142, 40],
    [145, 44],
    [141.5, 45.8],
    [139.5, 40],
    [136, 37.5],
    [131, 34.5],
    [130, 31],
  ],
  [
    [-24, 63.5],
    [-14, 64.5],
    [-14, 66.3],
    [-22, 66.4],
    [-24, 63.5],
  ],
  [
    [-10, 51.5],
    [-6, 50],
    [2, 51],
    [-2, 56],
    [-5, 58.5],
    [-9, 54],
    [-10, 51.5],
  ],
  [
    [95, 5],
    [105, -6],
    [120, -9],
    [140, -3],
    [150, -8],
    [130, 1],
    [115, 4],
    [95, 5],
  ],
];

bool _inside(double lon, double lat, List<List<double>> ring) {
  var contains = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i][0], yi = ring[i][1];
    final xj = ring[j][0], yj = ring[j][1];
    if ((yi > lat) != (yj > lat) &&
        lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
      contains = !contains;
    }
  }
  return contains;
}

List<_Projected>? _landCache;

/// 点阵大陆：纬度步长 2°，经度步长按余弦补偿，两极附近不至于稀疏。
List<_Projected> _landDots() {
  final cached = _landCache;
  if (cached != null) {
    return cached;
  }
  final dots = <_Projected>[];
  for (var lat = -80.0; lat <= 84; lat += 2) {
    final step = 2 / math.max(0.25, math.cos(lat * _rad));
    for (var lon = -180.0; lon < 180; lon += step) {
      if (_land.any((ring) => _inside(lon, lat, ring))) {
        dots.add(_Projected(lon, lat, 0));
      }
    }
  }
  return _landCache = dots;
}

class _GlobePainter extends CustomPainter {
  const _GlobePainter({
    required this.lon,
    required this.lat,
    required this.ink,
  });

  final double lon;
  final double lat;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    if (radius <= 0) {
      return;
    }

    // 1. 通透大气球体：径向渐变 + 1px 轮廓（对齐 Globe.tsx:97-100）
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 1.0,
          colors: [
            Color.fromRGBO(120, 170, 190, 0.16),
            Color.fromRGBO(120, 170, 190, 0.03),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color.fromRGBO(128, 150, 160, 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // 2. 完整 30° 经纬网（对齐 Globe.tsx:102-105）
    final grid =
        Paint()
          ..color = const Color.fromRGBO(128, 150, 160, 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7;

    void drawCurve(List<(double, double)> pts) {
      final path = Path();
      var pen = false;
      for (final (lo, la) in pts) {
        final q = _project(lo, la, lon, lat);
        if (q.z <= 0) {
          pen = false;
          continue;
        }
        final x = center.dx + q.x * radius;
        final y = center.dy + q.y * radius;
        if (pen) {
          path.lineTo(x, y);
        } else {
          path.moveTo(x, y);
          pen = true;
        }
      }
      canvas.drawPath(path, grid);
    }

    for (var ringLat = -60.0; ringLat <= 60.0; ringLat += 30.0) {
      drawCurve([for (var i = 0; i <= 72; i++) (-180.0 + i * 5.0, ringLat)]);
    }
    for (var ringLon = -180.0; ringLon < 180.0; ringLon += 30.0) {
      drawCurve([for (var i = 0; i <= 36; i++) (ringLon, -90.0 + i * 5.0)]);
    }

    // 3. 主题自适应大陆点阵（对齐 Globe.tsx:107-111）
    final dot = Paint()..style = PaintingStyle.fill;
    for (final land in _landDots()) {
      final q = _project(land.x, land.y, lon, lat);
      if (q.z <= 0.02) {
        continue;
      }
      dot.color = ink.withValues(alpha: (0.18 + 0.5 * q.z).clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(center.dx + q.x * radius, center.dy + q.y * radius),
        0.55 + 0.6 * q.z,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_GlobePainter oldDelegate) =>
      oldDelegate.lon != lon ||
      oldDelegate.lat != lat ||
      oldDelegate.ink != ink;
}
