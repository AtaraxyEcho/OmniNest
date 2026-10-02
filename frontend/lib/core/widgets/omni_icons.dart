import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 圆形图元（对应原型 SVG 的 circle 元素）。
class OmniIconCircle {
  const OmniIconCircle(this.cx, this.cy, this.r);
  final double cx;
  final double cy;
  final double r;
}

/// 圆角矩形图元（对应原型 SVG 的 rect 元素）。
class OmniIconRect {
  const OmniIconRect(this.x, this.y, this.width, this.height, this.radius);
  final double x;
  final double y;
  final double width;
  final double height;
  final double radius;
}

/// 描边图标数据：24×24 视口内的 SVG 路径与图元集合。
class OmniIconsData {
  const OmniIconsData({
    this.paths = const <String>[],
    this.circles = const <OmniIconCircle>[],
    this.rects = const <OmniIconRect>[],
  });
  final List<String> paths;
  final List<OmniIconCircle> circles;
  final List<OmniIconRect> rects;
}

/// 与设计原型完全一致的 1.8px 圆头描边图标集。
///
/// 路径数据逐一移植自原型 Icon 组件的 SVG path/circle/rect；渲染时按
/// [size]/24 缩放，描边宽同步缩放，保证任意尺寸下笔画比例不变。
abstract final class OmniIcons {
  static const OmniIconsData home = OmniIconsData(
    paths: ['M3 10.5 12 3l9 7.5', 'M5.5 9v11h13V9M9 20v-6h6v6'],
  );
  static const OmniIconsData library = OmniIconsData(
    paths: ['M4 5h5v14H4zM10.5 5h5v14h-5zM17 6l3-1 3.4 13-3 1z'],
  );
  static const OmniIconsData book = OmniIconsData(
    paths: [
      'M4 5.5A3.5 3.5 0 0 1 7.5 2H12v18H7.5A3.5 3.5 0 0 0 4 23z',
      'M20 5.5A3.5 3.5 0 0 0 16.5 2H12v18h4.5a3.5 3.5 0 0 1 3.5 3z',
    ],
  );
  static const OmniIconsData folder = OmniIconsData(
    paths: ['M3 6h7l2 2h9v11H3z'],
  );
  static const OmniIconsData search = OmniIconsData(
    paths: ['m16.5 16.5 4.5 4.5'],
    circles: [OmniIconCircle(11, 11, 7)],
  );
  static const OmniIconsData bell = OmniIconsData(
    // 等效重画：顶弧 + 两侧下行 + 底缘，避免小半径连续 arc 的描边畸变。
    paths: [
      'M12 3a6 6 0 0 0-6 6v3l-1.8 3.2c-.4.7.1 1.8 1 1.8h13.6c.9 0 1.4-1.1 1-1.8L18 12V9a6 6 0 0 0-6-6z',
      'M10 20a2 2 0 0 0 4 0',
    ],
  );
  static const OmniIconsData clock = OmniIconsData(
    paths: ['M12 7v5l3 2'],
    circles: [OmniIconCircle(12, 12, 9)],
  );
  static const OmniIconsData sun = OmniIconsData(
    paths: [
      'M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4',
    ],
    circles: [OmniIconCircle(12, 12, 4)],
  );
  static const OmniIconsData moon = OmniIconsData(
    paths: ['M20 14.5A8.5 8.5 0 0 1 9.5 4 8.5 8.5 0 1 0 20 14.5z'],
  );
  static const OmniIconsData cloud = OmniIconsData(
    paths: ['M7 18h11a4 4 0 0 0 .5-8 7 7 0 0 0-13.4 2A3 3 0 0 0 7 18z'],
  );
  static const OmniIconsData rain = OmniIconsData(
    paths: [
      'M7 15h11a4 4 0 0 0 .5-8 7 7 0 0 0-13.4 2A3 3 0 0 0 7 15z',
      'M9 18l-1 3M13 18l-1 3M17 18l-1 3',
    ],
  );
  static const OmniIconsData snow = OmniIconsData(
    paths: [
      'M7 15h11a4 4 0 0 0 .5-8 7 7 0 0 0-13.4 2A3 3 0 0 0 7 15z',
      'M8 19.5h.01M12 19.5h.01M16 19.5h.01M10 21.5h.01M14 21.5h.01',
    ],
  );
  static const OmniIconsData storm = OmniIconsData(
    paths: [
      'M7 15h11a4 4 0 0 0 .5-8 7 7 0 0 0-13.4 2A3 3 0 0 0 7 15z',
      'm13 15-2 4h3l-2 4',
    ],
  );
  static const OmniIconsData haze = OmniIconsData(
    paths: [
      'M7 15h11a4 4 0 0 0 .5-8 7 7 0 0 0-13.4 2A3 3 0 0 0 7 15z',
      'M5 19h14M7 22h10',
    ],
  );
  static const OmniIconsData play = OmniIconsData(paths: ['m8 5 11 7-11 7z']);
  static const OmniIconsData pause = OmniIconsData(paths: ['M8 5v14M16 5v14']);
  static const OmniIconsData next = OmniIconsData(
    paths: ['m6 5 10 7-10 7zM18 5v14'],
  );
  static const OmniIconsData previous = OmniIconsData(
    paths: ['m18 5-10 7 10 7zM6 5v14'],
  );
  static const OmniIconsData chevron = OmniIconsData(paths: ['m9 5 7 7-7 7']);
  static const OmniIconsData more = OmniIconsData(
    circles: [
      OmniIconCircle(5, 12, 1),
      OmniIconCircle(12, 12, 1),
      OmniIconCircle(19, 12, 1),
    ],
  );
  static const OmniIconsData heart = OmniIconsData(
    paths: [
      'M20.8 5.7a5.5 5.5 0 0 0-7.8 0L12 6.8l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 22l8.8-8.5a5.5 5.5 0 0 0 0-7.8z',
    ],
  );
  static const OmniIconsData grid = OmniIconsData(
    paths: ['M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z'],
  );
  static const OmniIconsData list = OmniIconsData(
    paths: ['M9 6h12M9 12h12M9 18h12'],
    circles: [
      OmniIconCircle(4, 6, 1),
      OmniIconCircle(4, 12, 1),
      OmniIconCircle(4, 18, 1),
    ],
  );
  static const OmniIconsData plus = OmniIconsData(paths: ['M12 5v14M5 12h14']);
  static const OmniIconsData device = OmniIconsData(
    paths: ['M8 21h8M12 15v6'],
    rects: [OmniIconRect(4, 3, 16, 12, 2)],
  );
  static const OmniIconsData settings = OmniIconsData(
    paths: [
      'M19 12a7 7 0 0 0-.1-1l2-1.6-2-3.5-2.5 1A7 7 0 0 0 14.7 6L14.3 3h-4.1L9.8 6a7 7 0 0 0-1.7 1L5.5 6 3.5 9.5l2.2 1.6a7 7 0 0 0 0 2L3.5 14.6l2 3.5 2.6-1a7 7 0 0 0 1.7 1l.4 3h4.1l.4-3a7 7 0 0 0 1.7-1l2.5 1 2-3.5-2-1.6a7 7 0 0 0 .1-1z',
    ],
    circles: [OmniIconCircle(12, 12, 3)],
  );
  static const OmniIconsData image = OmniIconsData(
    paths: ['m3 17 5-5 4 4 3-3 6 6'],
    circles: [OmniIconCircle(8, 9, 2)],
    rects: [OmniIconRect(3, 4, 18, 16, 2)],
  );
  static const OmniIconsData film = OmniIconsData(
    paths: ['M7 4v16M17 4v16M3 9h4m10 0h4M3 15h4m10 0h4'],
    rects: [OmniIconRect(3, 4, 18, 16, 2)],
  );
  static const OmniIconsData music = OmniIconsData(
    paths: ['M9 18V5l10-2v13'],
    circles: [OmniIconCircle(6, 18, 3), OmniIconCircle(16, 16, 3)],
  );
  static const OmniIconsData arrow = OmniIconsData(paths: ['m15 18-6-6 6-6']);
  static const OmniIconsData share = OmniIconsData(
    paths: ['m8.6 10.5 6.8-4M8.6 13.5l6.8 4'],
    circles: [
      OmniIconCircle(18, 5, 3),
      OmniIconCircle(6, 12, 3),
      OmniIconCircle(18, 19, 3),
    ],
  );
  static const OmniIconsData download = OmniIconsData(
    paths: ['M12 3v12m-5-5 5 5 5-5M4 21h16'],
  );
  static const OmniIconsData close = OmniIconsData(
    paths: ['M5 5l14 14M19 5 5 19'],
  );
  static const OmniIconsData queue = OmniIconsData(
    paths: ['M4 6h10M4 12h10M4 18h7', 'm17 14 4 3-4 3z'],
  );
  static const OmniIconsData shuffle = OmniIconsData(
    paths: [
      'M3 7h3c5 0 7 10 12 10h3M18 14l3 3-3 3M3 17h3c2 0 3.5-1.6 5-4M18 4l3 3-3 3',
    ],
  );
  static const OmniIconsData repeat = OmniIconsData(
    paths: [
      'm17 2 3 3-3 3M20 5H7a4 4 0 0 0-4 4v1M7 22l-3-3 3-3M4 19h13a4 4 0 0 0 4-4v-1',
    ],
  );
  static const OmniIconsData sparkle = OmniIconsData(
    paths: [
      'm12 2 1.4 5.1L18 9l-4.6 1.9L12 16l-1.4-5.1L6 9l4.6-1.9z',
      'm19 15 .7 2.3L22 18l-2.3.7L19 21l-.7-2.3L16 18l2.3-.7z',
    ],
  );
  static const OmniIconsData check = OmniIconsData(paths: ['m5 12 4 4L19 6']);

  /// 按 QWeather 图标编码映射描边天气图标（与 portal 天气图标同区间语义）。
  /// 字符串编码便捷入口（后端字段多为字符串；解析失败回退云）。
  static OmniIconsData weatherByCode(String? code) {
    return weatherFor(int.tryParse(code ?? '') ?? -1);
  }

  static OmniIconsData weatherFor(int iconCode) {
    if (iconCode == 100) return sun;
    if (iconCode == 101 || iconCode == 102) return cloud;
    if (iconCode == 103 || iconCode == 104) return OmniIcons.haze;
    if (iconCode >= 150 && iconCode <= 153) return moon;
    if (iconCode >= 300 && iconCode < 400) return rain;
    if (iconCode >= 400 && iconCode < 500) return snow;
    if (iconCode >= 500 && iconCode < 600) return haze;
    if (iconCode >= 600 && iconCode < 700) return snow;
    return cloud;
  }
}

/// 渲染一枚描边图标；尺寸语义与 Icon 对齐（默认 22）。
class OmniIcon extends StatelessWidget {
  const OmniIcon({
    required this.icon,
    super.key,
    this.size = 22,
    this.color,
    this.strokeWidth = 1.8,
  });

  final OmniIconsData icon;
  final double size;
  final Color? color;

  /// 24×24 视口下的描边宽；渲染时随尺寸等比缩放。
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _OmniIconPainter(
          icon: icon,
          color:
              color ?? IconTheme.of(context).color ?? const Color(0xFFFFFFFF),
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _OmniIconPainter extends CustomPainter {
  _OmniIconPainter({
    required this.icon,
    required this.color,
    required this.strokeWidth,
  });

  final OmniIconsData icon;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.scale(scale, scale);
    for (final rect in icon.rects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.x, rect.y, rect.width, rect.height),
          Radius.circular(rect.radius),
        ),
        paint,
      );
    }
    for (final circle in icon.circles) {
      canvas.drawCircle(Offset(circle.cx, circle.cy), circle.r, paint);
    }
    for (final data in icon.paths) {
      canvas.drawPath(_parsePath(data), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OmniIconPainter oldDelegate) {
    return oldDelegate.icon != icon ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }

  static final RegExp _commandPattern = RegExp(r'[MmLlHhVvAaZz]');
  static final RegExp _numberPattern = RegExp(r'-?\d*\.?\d+');

  /// 解析原型使用的 SVG path 命令子集（M/L/H/V/A/Z 及相对形式）。
  ///
  /// 隐式重复坐标按 SVG 语义处理：M 后续坐标对为隐式 LineTo；首个相对
  /// m 出现在空路径上时按绝对坐标处理（SVG 规范）。当前点由解析器自行
  /// 跟踪（Path 无稳定 API 读取当前点）。
  static Path _parsePath(String data) {
    final path = Path();
    var current = Offset.zero;
    var started = false;
    final matches = _commandPattern.allMatches(data).toList();
    for (var index = 0; index < matches.length; index++) {
      final command = matches[index].group(0)!;
      final argStart = matches[index].end;
      final argEnd =
          index + 1 < matches.length ? matches[index + 1].start : data.length;
      final numbers =
          _numberPattern
              .allMatches(data.substring(argStart, argEnd))
              .map((match) => double.parse(match.group(0)!))
              .toList();
      switch (command) {
        case 'M':
        case 'm':
          for (var i = 0; i + 1 < numbers.length; i += 2) {
            final delta = Offset(numbers[i], numbers[i + 1]);
            final next = command == 'M' || !started ? delta : current + delta;
            if (i == 0) {
              path.moveTo(next.dx, next.dy);
              started = true;
            } else {
              path.lineTo(next.dx, next.dy);
            }
            current = next;
          }
        case 'L':
        case 'l':
          for (var i = 0; i + 1 < numbers.length; i += 2) {
            final next =
                command == 'L'
                    ? Offset(numbers[i], numbers[i + 1])
                    : current + Offset(numbers[i], numbers[i + 1]);
            path.lineTo(next.dx, next.dy);
            current = next;
          }
        case 'H':
        case 'h':
          for (final value in numbers) {
            current = Offset(
              command == 'H' ? value : current.dx + value,
              current.dy,
            );
            path.lineTo(current.dx, current.dy);
          }
        case 'V':
        case 'v':
          for (final value in numbers) {
            current = Offset(
              current.dx,
              command == 'V' ? value : current.dy + value,
            );
            path.lineTo(current.dx, current.dy);
          }
        case 'A':
        case 'a':
          for (var i = 0; i + 6 < numbers.length; i += 7) {
            final end = Offset(
              command == 'A' ? numbers[i + 5] : current.dx + numbers[i + 5],
              command == 'A' ? numbers[i + 6] : current.dy + numbers[i + 6],
            );
            path.arcToPoint(
              end,
              radius: Radius.elliptical(numbers[i], numbers[i + 1]),
              rotation: numbers[i + 2] * math.pi / 180,
              largeArc: numbers[i + 3] == 1,
              clockwise: numbers[i + 4] == 1,
            );
            current = end;
          }
        case 'Z':
        case 'z':
          path.close();
      }
    }
    return path;
  }
}
