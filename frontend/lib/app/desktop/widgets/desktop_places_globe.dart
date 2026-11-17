import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';

/// 地点（样例 `Globe.tsx` 的 `GlobePlace`）：名称、照片数与经纬度。
class DesktopGlobePlace {
  const DesktopGlobePlace({
    required this.name,
    required this.count,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final int count;
  final double latitude;
  final double longitude;
}

/// 可拖动点阵地球（样例 `Globe.tsx`）：粗粒度大陆轮廓只画点，不画边界、
/// 不标地名；选中地点时地球缓动转向它。
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
  // 不能用 DesktopMotion.of(context)：字段初始化跑在 initState 之前，
  // 那时读 MediaQuery 会直接断言。转向时长取令牌常量即可。
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: DesktopMotion.pageFlip,
  );
  // 样例 `.pin b` 的 `ping 2.4s ease-out infinite`：只有一条描边圆环在动，
  // 单独一个控制器 + RepaintBoundary，不牵连地球 Canvas 的重绘。
  late final AnimationController _ping = AnimationController(
    vsync: this,
    duration: DesktopMotion.placePing,
  );
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  double _lon = 12;
  double _lat = 18;

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
    }
    _syncPing();
  }

  void _syncPing() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.selected != null && !reduce) {
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
            .firstOrNull;
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
    var dLon = (place.longitude - _lon + 540) % 360 - 180;
    _to = Offset(_lon + dLon, targetLat);
    _turn.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth.clamp(260.0, 440.0);
        final radius = size / 2 - 4;
        Offset? pingAt;
        final selectedPlace =
            widget.places
                .where((entry) => entry.name == widget.selected)
                .firstOrNull;
        if (selectedPlace != null) {
          final point = _project(
            selectedPlace.longitude,
            selectedPlace.latitude,
            _lon,
            _lat,
          );
          if (point.z > 0.05) {
            pingAt = Offset(
              size / 2 + radius * point.x,
              size / 2 + radius * point.y,
            );
          }
        }
        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) {
              _turn.stop();
              setState(() {
                _lon -= details.delta.dx * 0.4;
                _lat = (_lat + details.delta.dy * 0.4).clamp(-80.0, 80.0);
              });
            },
            onTapUp: (details) {
              final hit = _hitTest(details.localPosition, size);
              if (hit != null) {
                widget.onSelect(hit);
              }
            },
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                children: [
                  // 脉冲环每帧变，地球 Canvas 不该跟着重画：拆成独立层。
                  Positioned.fill(
                    child: RepaintBoundary(
                      key: const ValueKey('places-globe-canvas'),
                      child: CustomPaint(
                        painter: _GlobePainter(
                          lon: _lon,
                          lat: _lat,
                          places: widget.places,
                          selected: widget.selected,
                          accent: skin.accent,
                        ),
                      ),
                    ),
                  ),
                  if (pingAt != null)
                    Positioned(
                      left: pingAt.dx - 15,
                      top: pingAt.dy - 15,
                      width: 30,
                      height: 30,
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          key: const ValueKey('places-globe-ping'),
                          child: AnimatedBuilder(
                            animation: _ping,
                            builder: (context, _) {
                              final t = _ping.value;
                              // `.pin b`：`ping 2.4s ease-out`，
                              // 0% scale(.5)/opacity .9 → 100% 2.2/0。
                              return Opacity(
                                opacity: 0.9 * (1 - t),
                                child: Transform.scale(
                                  scale: 0.5 + 1.7 * t,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: skin.accent,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? _hitTest(Offset local, double size) {
    DesktopGlobePlace? best;
    var bestDistance = 22.0;
    for (final place in widget.places) {
      final point = _project(place.longitude, place.latitude, _lon, _lat);
      if (point.z <= 0.05) {
        continue;
      }
      final screen = Offset(size / 2 * (1 + point.x), size / 2 * (1 + point.y));
      final distance = (screen - local).distance;
      if (distance < bestDistance) {
        best = place;
        bestDistance = distance;
      }
    }
    return best?.name;
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
    required this.places,
    required this.selected,
    required this.accent,
  });

  final double lon;
  final double lat;
  final List<DesktopGlobePlace> places;
  final String? selected;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    // 球体底盘：深色径向，边缘收暗，像一颗被照亮的球。
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.35),
          radius: 1.1,
          colors: [Color(0xFF13222B), Color(0xFF070B14)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    final dot = Paint()..style = PaintingStyle.fill;
    for (final land in _landDots()) {
      final point = _project(land.x, land.y, lon, lat);
      if (point.z <= 0.02) {
        continue;
      }
      dot.color = const Color(
        0xFF8CC5B2,
      ).withValues(alpha: 0.12 + point.z * 0.34);
      canvas.drawCircle(
        Offset(center.dx + radius * point.x, center.dy + radius * point.y),
        0.9 + point.z * 0.7,
        dot,
      );
    }

    for (final place in places) {
      final point = _project(place.longitude, place.latitude, lon, lat);
      if (point.z <= 0.05) {
        continue;
      }
      final position = Offset(
        center.dx + radius * point.x,
        center.dy + radius * point.y,
      );
      final active = place.name == selected;
      if (active) {
        canvas.drawCircle(
          position,
          11,
          Paint()..color = accent.withValues(alpha: 0.24),
        );
      }
      canvas.drawCircle(position, active ? 5.5 : 4, Paint()..color = accent);
      canvas.drawCircle(position, 2, Paint()..color = const Color(0xFF0B1014));
    }

    // 经纬网：只画正面两条经线与赤道，给球体一点方向感。
    final grid =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.06)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    for (final ringLat in const [-45.0, 0.0, 45.0]) {
      final path = Path();
      // 围绕当前中心经度扫一圈采样，只连朝向观察者的段。
      for (var step = 0; step <= 120; step++) {
        final sampleLon = lon - 90 + step * 1.5;
        final point = _project(sampleLon, ringLat, lon, lat);
        if (point.z <= 0.02) {
          continue;
        }
        final position = Offset(
          center.dx + radius * point.x,
          center.dy + radius * point.y,
        );
        if (step == 0) {
          path.moveTo(position.dx, position.dy);
        } else {
          path.lineTo(position.dx, position.dy);
        }
      }
      canvas.drawPath(path, grid);
    }
  }

  @override
  bool shouldRepaint(_GlobePainter oldDelegate) =>
      oldDelegate.lon != lon ||
      oldDelegate.lat != lat ||
      oldDelegate.selected != selected ||
      oldDelegate.places != places ||
      oldDelegate.accent != accent;
}
