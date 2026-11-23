import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/desktop/widgets/desktop_glass.dart';

/// 浅色媒体页（非 Reader）底色。
const Color desktopAmbientLightBaseColor = Color(0xFFF4F6F2);

/// 深色媒体页（非 Reader）单层平铺暗纱（35%）。
const Color desktopAmbientDarkVeilColor = Color(0x5905080A);

/// Reader 深色中心暗光池色标。
const List<Color> desktopReaderDarkPoolColors = <Color>[
  Color(0x2E05080A),
  Color(0x9E05080A),
];

/// Reader 浅色白纸光池色标。
const List<Color> desktopReaderLightPoolColors = <Color>[
  Color(0x57FFFFFF),
  Color(0x14F4F6F2),
];

/// 媒体背景艺术层的构图预设。
///
/// v16 起非 Reader 媒体页统一采用全出血 `decodeWidth: 1280` 解码，
/// 保留枚举字段以兼容历史调用与外部预设选择。
enum EditorialArtPreset {
  /// 影视 / 照片等宽屏内容：1280px 解码。
  landscape(
    widthFactor: 1.0,
    alignment: Alignment(0.3, 0),
    blurSigma: 0.0,
    decodeWidth: 1280,
    opacityMultiplier: 1.0,
    horizontalStops: <double>[0.08, 0.96],
    verticalStops: <double>[0.55, 1.0],
  ),

  /// 音乐专辑等方形封面：1280px 解码。
  square(
    widthFactor: 1.0,
    alignment: Alignment(0.3, 0),
    blurSigma: 0.0,
    decodeWidth: 1280,
    opacityMultiplier: 1.0,
    horizontalStops: <double>[0.10, 0.96],
    verticalStops: <double>[0.52, 1.0],
  ),

  /// 阅读竖版书封预设（Reader 路由下隐藏艺术图，仅走 4×3 色网 + 光池）。
  portraitBook(
    widthFactor: 1.0,
    alignment: Alignment.center,
    blurSigma: 0.0,
    decodeWidth: 1280,
    opacityMultiplier: 1.0,
    horizontalStops: <double>[0.16, 0.98],
    verticalStops: <double>[0.45, 0.98],
  ),

  /// 首页等轻氛围模式：1280px 解码、0.55× 不透明度。
  ambientSubtle(
    widthFactor: 1.0,
    alignment: Alignment(0.3, 0),
    blurSigma: 0.0,
    decodeWidth: 1280,
    opacityMultiplier: 0.55,
    horizontalStops: <double>[0.12, 0.96],
    verticalStops: <double>[0.50, 1.0],
  );

  const EditorialArtPreset({
    required this.widthFactor,
    required this.alignment,
    required this.blurSigma,
    required this.decodeWidth,
    required this.opacityMultiplier,
    required this.horizontalStops,
    required this.verticalStops,
  });

  final double widthFactor;
  final Alignment alignment;
  final double blurSigma;
  final int decodeWidth;
  final double opacityMultiplier;
  final List<double> horizontalStops;
  final List<double> verticalStops;
}

/// 深浅色模式精细差异化参数表。
@immutable
class AmbientThemeProfile {
  const AmbientThemeProfile({
    required this.meshAlpha,
    required this.meshSat,
    required this.meshBright,
    required this.lightWash,
    required this.artAlpha,
    required this.veilOpacity,
    required this.linearFactor,
    required this.radialStops,
  });

  static const AmbientThemeProfile dark = AmbientThemeProfile(
    meshAlpha: 0.82,
    meshSat: 1.25,
    meshBright: 0.96,
    lightWash: 0.0,
    artAlpha: 0.56,
    veilOpacity: 1.0,
    linearFactor: 0.56,
    radialStops: <double>[0.18, 0.96],
  );

  static const AmbientThemeProfile light = AmbientThemeProfile(
    meshAlpha: 0.38,
    meshSat: 1.18,
    meshBright: 1.16,
    lightWash: 0.26,
    artAlpha: 0.28,
    veilOpacity: 0.0,
    linearFactor: 0.0,
    radialStops: <double>[0.14, 0.94],
  );

  static AmbientThemeProfile of({required bool isDark}) =>
      isDark ? dark : light;

  final double meshAlpha;
  final double meshSat;
  final double meshBright;
  final double lightWash;
  final double artAlpha;
  final double veilOpacity;
  final double linearFactor;
  final List<double> radialStops;
}

/// 4×3 矢量色网采样结果（12 节点 RGB + 全局平均 RGB）。
class AmbientMeshGrid {
  const AmbientMeshGrid({required this.points, required this.average});

  /// 由单一兜底色调生成带有柔和明暗起伏的 4×3 色网（如无封面图书的纸色兜底）。
  factory AmbientMeshGrid.fromTone(Color tone) {
    final hsl = HSLColor.fromColor(tone);
    const offsets = <(double, double)>[
      (-0.04, 0.06),
      (-0.02, 0.03),
      (0.02, 0.02),
      (0.04, -0.02),
      (-0.03, 0.02),
      (0.0, 0.04),
      (0.02, 0.0),
      (0.03, -0.04),
      (-0.02, -0.03),
      (0.0, -0.02),
      (0.03, -0.05),
      (0.05, -0.07),
    ];
    final points = List<Color>.generate(offsets.length, (i) {
      final (dh, dl) = offsets[i];
      final h = (hsl.hue + dh * 360.0) % 360.0;
      final l = (hsl.lightness + dl).clamp(0.06, 0.92);
      final s = (hsl.saturation * (i.isEven ? 1.05 : 0.92)).clamp(0.0, 1.0);
      return hsl
          .withHue(h < 0 ? h + 360.0 : h)
          .withSaturation(s)
          .withLightness(l)
          .toColor();
    }, growable: false);
    return AmbientMeshGrid(points: points, average: tone);
  }

  /// 行优先 4 列 × 3 行（共 12 个采样点）。
  final List<Color> points;

  /// 12 点均值底色，用于铺底防止边缘漏黑。
  final Color average;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AmbientMeshGrid &&
        other.average == average &&
        listEquals(other.points, points);
  }

  @override
  int get hashCode => Object.hash(average, Object.hashAll(points));
}

/// 环境光 `4×3` 矢量色网 LRU 采样缓存。
///
/// 废除离屏光栅 GPU 回读：改用
/// `ResizeImage(provider, width: 4, height: 3, policy: ResizeImagePolicy.exact)`
/// 直接在解码阶段缩放到 4×3，并带 300ms 超时保护与监听器清理；
/// 容量上限 32 条（LRU 淘汰），并发同键复用单次解码。
class DesktopAmbientMeshCache {
  DesktopAmbientMeshCache._();

  static final DesktopAmbientMeshCache instance = DesktopAmbientMeshCache._();

  static const int maxEntries = 32;
  static const int _gridCols = 4;
  static const int _gridRows = 3;

  final LinkedHashMap<String, AmbientMeshGrid> _cache =
      LinkedHashMap<String, AmbientMeshGrid>();
  final Map<String, Future<AmbientMeshGrid?>> _inFlight =
      <String, Future<AmbientMeshGrid?>>{};

  /// 同步命中查询（命中时刷新 LRU 顺序）。
  AmbientMeshGrid? peek(String key) {
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
    }
    return hit;
  }

  /// 异步采样图片生成 4×3 色网并写入 LRU 缓存。
  Future<AmbientMeshGrid?> sample(
    String source, {
    ImageProvider<Object>? imageProvider,
    String? cacheKey,
  }) {
    final key = cacheKey ?? source;
    final cached = peek(key);
    if (cached != null) {
      return Future<AmbientMeshGrid?>.value(cached);
    }
    return _inFlight.putIfAbsent(key, () async {
      try {
        final ImageProvider<Object> baseProvider;
        final provided = imageProvider;
        if (provided != null) {
          baseProvider = provided;
        } else if (source.startsWith('assets/')) {
          baseProvider = AssetImage(source);
        } else {
          baseProvider = NetworkImage(source);
        }
        final resized = ResizeImage(
          baseProvider,
          width: _gridCols,
          height: _gridRows,
          policy: ResizeImagePolicy.exact,
        );
        final grid = await _decodeAndSample(resized);
        if (grid != null) {
          _put(key, grid);
        }
        return grid;
      } on Object {
        return null;
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  void _put(String key, AmbientMeshGrid grid) {
    _cache.remove(key);
    while (_cache.length >= maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = grid;
  }

  /// 供单测注入确定性 4×3 色网，避免依赖网络。
  @visibleForTesting
  void putForTest(String key, AmbientMeshGrid grid) {
    _put(key, grid);
  }

  /// 供单测清理缓存。
  @visibleForTesting
  void clearForTest() {
    _cache.clear();
    _inFlight.clear();
  }

  static Future<AmbientMeshGrid?> _decodeAndSample(
    ImageProvider<Object> provider,
  ) async {
    final completer = Completer<ImageInfo?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;

    // 不加额外计时器：任何 widget 测试只要挂载照片查看器/幻灯片，未解码完的
    // 300ms 计时器就会在用例结束时以 pending timer 报红；HTTP 客户端本身有
    // 超时与错误回调，采样失败会走 onError 这条唯一出口。
    void finish(ImageInfo? info) {
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete(info);
      } else {
        info?.dispose();
      }
    }

    listener = ImageStreamListener(
      (ImageInfo info, bool _) => finish(info),
      onError: (Object error, StackTrace? stack) => finish(null),
    );
    stream.addListener(listener);

    final info = await completer.future;
    if (info == null) return null;

    try {
      final src = info.image;
      // 只对网络解码设超时：图像已解码成 4×3 后 toByteData 是引擎侧同步取回，
      // 再加 Future.timeout 只会在测试的假时钟里留下悬空计时器。
      final bytes = await src.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return null;

      final width = src.width;
      final height = src.height;
      if (width <= 0 || height <= 0) return null;

      final data = bytes.buffer.asUint8List();
      final points = <Color>[];
      var sumR = 0;
      var sumG = 0;
      var sumB = 0;
      const count = _gridCols * _gridRows;

      for (var row = 0; row < _gridRows; row++) {
        final py =
            height == _gridRows
                ? row
                : (((row + 0.5) * height) / _gridRows).floor().clamp(
                  0,
                  height - 1,
                );
        for (var col = 0; col < _gridCols; col++) {
          final px =
              width == _gridCols
                  ? col
                  : (((col + 0.5) * width) / _gridCols).floor().clamp(
                    0,
                    width - 1,
                  );
          final offset = (py * width + px) * 4;
          if (offset + 2 >= data.length) {
            return null;
          }
          final r = data[offset];
          final g = data[offset + 1];
          final b = data[offset + 2];
          sumR += r;
          sumG += g;
          sumB += b;
          points.add(Color.fromARGB(255, r, g, b));
        }
      }

      final average = Color.fromARGB(
        255,
        (sumR / count).round(),
        (sumG / count).round(),
        (sumB / count).round(),
      );
      return AmbientMeshGrid(points: points, average: average);
    } finally {
      info.dispose();
    }
  }
}

/// 4×3 矢量色网绘制器：
/// 底色铺 12 点均值 RGB，叠 12 个 `48%×58%` 椭圆径向渐变，任意分辨率 0 马赛克。
class AmbientColourMeshPainter extends CustomPainter {
  const AmbientColourMeshPainter({required this.grid, this.opacity = 1.0});

  final AmbientMeshGrid grid;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || opacity <= 0) return;
    final alpha = opacity.clamp(0.0, 1.0);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = grid.average.withValues(alpha: alpha),
    );

    final rx = size.width * 0.48;
    final ry = size.height * 0.58;
    if (rx <= 0 || ry <= 0) return;

    final unitRect = Rect.fromCircle(center: Offset.zero, radius: 1.0);
    final count = grid.points.length < 12 ? grid.points.length : 12;
    for (var i = 0; i < count; i++) {
      final col = i % 4;
      final row = i ~/ 4;
      final cx = size.width * (col * 0.333);
      final cy = size.height * (row * 0.50);
      final color = grid.points[i];

      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(rx, ry);
      canvas.drawCircle(
        Offset.zero,
        1.0,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0.0),
            ],
            stops: const <double>[0.0, 1.0],
          ).createShader(unitRect),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(AmbientColourMeshPainter oldDelegate) =>
      oldDelegate.grid != grid || oldDelegate.opacity != opacity;
}

/// 复用型 `4×3` 矢量色网表面组件：自动走 `DesktopAmbientMeshCache` 采样，
/// 支持预采样 `preloadedGrid` 与浅色模式 `lightWash` 混柔。
class DesktopAmbientMeshSurface extends StatefulWidget {
  const DesktopAmbientMeshSurface({
    required this.source,
    this.imageProvider,
    this.cacheKey,
    this.preloadedGrid,
    this.opacity = 1.0,
    this.saturation = 1.25,
    this.brightness = 1.0,
    this.fallbackColor = Colors.transparent,
    this.washColor,
    this.washOpacity = 0.0,
    super.key,
  });

  final String source;
  final ImageProvider<Object>? imageProvider;
  final String? cacheKey;
  final AmbientMeshGrid? preloadedGrid;
  final double opacity;
  final double saturation;
  final double brightness;
  final Color fallbackColor;
  final Color? washColor;
  final double washOpacity;

  @override
  State<DesktopAmbientMeshSurface> createState() =>
      _DesktopAmbientMeshSurfaceState();
}

class _DesktopAmbientMeshSurfaceState extends State<DesktopAmbientMeshSurface> {
  AmbientMeshGrid? _grid;
  String _activeKey = '';

  String get _effectiveKey => widget.cacheKey ?? widget.source;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DesktopAmbientMeshSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preloadedGrid != widget.preloadedGrid ||
        oldWidget.source != widget.source ||
        oldWidget.cacheKey != widget.cacheKey) {
      _load();
    }
  }

  void _load() {
    final preloaded = widget.preloadedGrid;
    if (preloaded != null) {
      _activeKey = _effectiveKey;
      _grid = preloaded;
      return;
    }
    final key = _effectiveKey;
    _activeKey = key;
    if (widget.source.isEmpty) {
      _grid = null;
      return;
    }
    final cached = DesktopAmbientMeshCache.instance.peek(key);
    if (cached != null) {
      _grid = cached;
      return;
    }
    unawaited(
      DesktopAmbientMeshCache.instance
          .sample(
            widget.source,
            imageProvider: widget.imageProvider,
            cacheKey: key,
          )
          .then((grid) {
            if (!mounted || _activeKey != key || grid == null) return;
            setState(() => _grid = grid);
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grid = widget.preloadedGrid ?? _grid;
    if (grid == null) {
      return ColoredBox(color: widget.fallbackColor);
    }
    final mesh = ColorFiltered(
      colorFilter: desktopColorGrade(
        saturation: widget.saturation,
        brightness: widget.brightness,
      ),
      child: CustomPaint(
        painter: AmbientColourMeshPainter(grid: grid, opacity: widget.opacity),
        child: const SizedBox.expand(),
      ),
    );
    final wash = widget.washColor;
    final washAlpha = widget.washOpacity.clamp(0.0, 1.0);
    if (wash == null || washAlpha <= 0.001) {
      return mesh;
    }
    return Stack(
      fit: StackFit.expand,
      children: [mesh, ColoredBox(color: wash.withValues(alpha: washAlpha))],
    );
  }
}

/// 全出血媒体艺术背景层（v16 无模糊、无 `ShaderMask`、`decodeWidth: 1280`）。
///
/// - 浅色媒体页（非 Reader）：居中 `BoxFit.cover` 原图（无模糊、无滤镜、无遮罩）；
/// - 深色媒体页（非 Reader）：`Alignment(0.3, 0)` + `sat: 1.10, bright: 0.92`；
/// - 封装在独立 `RepaintBoundary` 内，稳态 0 次逐帧重绘。
class EditorialArtPanel extends StatelessWidget {
  const EditorialArtPanel({
    required this.source,
    required this.isDark,
    required this.intensityFactor,
    this.preset = EditorialArtPreset.landscape,
    this.profile,
    this.imageProvider,
    this.animate = false,
    super.key,
  });

  final String source;
  final bool isDark;
  final double intensityFactor;
  final EditorialArtPreset preset;
  final AmbientThemeProfile? profile;
  final ImageProvider<Object>? imageProvider;

  /// 兼容旧调用签名；全出血静态艺术层不运行平移动画。
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final effectiveProfile = profile ?? AmbientThemeProfile.of(isDark: isDark);
    final alpha = (effectiveProfile.artAlpha *
            preset.opacityMultiplier *
            intensityFactor)
        .clamp(0.0, 1.0);
    if (alpha <= 0.001 || source.isEmpty) {
      return const SizedBox.shrink();
    }
    final ImageProvider<Object> baseProvider =
        imageProvider ??
        (source.startsWith('assets/')
            ? AssetImage(source)
            : NetworkImage(source));

    Widget art = Image(
      image: ResizeImage(baseProvider, width: preset.decodeWidth),
      fit: BoxFit.cover,
      alignment: isDark ? const Alignment(0.3, 0) : Alignment.center,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      opacity: AlwaysStoppedAnimation<double>(alpha),
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );

    if (isDark) {
      art = ColorFiltered(
        colorFilter: desktopColorGrade(saturation: 1.10, brightness: 0.92),
        child: art,
      );
    }

    return RepaintBoundary(child: SizedBox.expand(child: art));
  }
}

/// 环境光场景资源解析：按路由与极性按需采样 4×3 色网并预解码艺术图（默认 220ms 软超时）。
///
/// 浅色非 Reader 路由传入 `skipMeshSampling: true`，完全跳过 4×3 色网采样；
/// 任何解码超时或异常一律静默降级，由绘制层的 errorBuilder 与纸色兜底。
Future<AmbientMeshGrid?> resolveAmbientSceneAssets({
  required BuildContext context,
  required String source,
  required bool showArt,
  required EditorialArtPreset artPreset,
  AmbientMeshGrid? cachedGrid,
  bool skipMeshSampling = false,
  bool Function()? isCancelled,
  Duration softTimeout = const Duration(milliseconds: 220),
}) async {
  if (isCancelled?.call() ?? false) {
    return cachedGrid;
  }
  AmbientMeshGrid? resolvedGrid = cachedGrid;
  final tasks = <Future<void>>[];

  if (!skipMeshSampling && resolvedGrid == null) {
    tasks.add(
      DesktopAmbientMeshCache.instance.sample(source).then((grid) {
        if (isCancelled?.call() ?? false) return;
        resolvedGrid = grid;
      }),
    );
  }

  if (showArt && context.mounted && !(isCancelled?.call() ?? false)) {
    final ImageProvider<Object> baseProvider =
        source.startsWith('assets/')
            ? AssetImage(source)
            : NetworkImage(source);
    final resized = ResizeImage(baseProvider, width: artPreset.decodeWidth);
    tasks.add(
      precacheImage(
        resized,
        context,
        onError: (Object error, StackTrace? stackTrace) {
          // 预解码失败静默降级，由 Image errorBuilder 兜底。
        },
      ).catchError((Object _) {}),
    );
  }

  if (tasks.isNotEmpty) {
    try {
      await Future.wait<void>(tasks).timeout(softTimeout);
    } on TimeoutException {
      // 超过软超时即先行切换，避免慢网阻塞页面转场。
    } on Object {
      // 忽略偶发解码异常。
    }
  }
  return resolvedGrid;
}
