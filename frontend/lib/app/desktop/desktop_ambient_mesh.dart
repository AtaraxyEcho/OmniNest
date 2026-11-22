import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/desktop/widgets/desktop_glass.dart';

/// 右侧轻柔焦艺术面板的构图预设。
///
/// 按媒体比例与页面密度区分宽占比、对齐点、柔焦半径、解码宽度与羽化遮罩，
/// 避免横图、方封与竖版书封套用同一套裁切。
enum EditorialArtPreset {
  /// 影视 / 照片等宽屏内容：63% 宽、居中构图、sigma 5.0、960px 解码。
  landscape(
    widthFactor: 0.63,
    alignment: Alignment.center,
    blurSigma: 5.0,
    decodeWidth: 960,
    opacityMultiplier: 1.0,
    horizontalStops: <double>[0.08, 0.96],
    verticalStops: <double>[0.55, 1.0],
  ),

  /// 音乐专辑等方形封面：54% 宽、轻微右上偏移、sigma 6.0、960px 解码。
  square(
    widthFactor: 0.54,
    alignment: Alignment(0.15, -0.05),
    blurSigma: 6.0,
    decodeWidth: 960,
    opacityMultiplier: 1.0,
    horizontalStops: <double>[0.10, 0.96],
    verticalStops: <double>[0.52, 1.0],
  ),

  /// 阅读竖版书封：44% 宽、偏上构图、sigma 7.5、720px 解码、收紧羽化遮罩。
  portraitBook(
    widthFactor: 0.44,
    alignment: Alignment(0.12, -0.24),
    blurSigma: 7.5,
    decodeWidth: 720,
    opacityMultiplier: 1.0,
    horizontalStops: <double>[0.16, 0.98],
    verticalStops: <double>[0.45, 0.98],
  ),

  /// 首页等轻氛围模式：56% 宽、sigma 8.0、0.45× 不透明度、720px 解码。
  ambientSubtle(
    widthFactor: 0.56,
    alignment: Alignment.center,
    blurSigma: 8.0,
    decodeWidth: 720,
    opacityMultiplier: 0.45,
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
///
/// 浅色模式通过降低色网与艺术层透明度、提高明度并叠入 `lightWash`（混入 `skin.bg`），
/// 消除深色封面在亮底上呈现灰脏感的问题；深色模式保留更高饱和度与纵深暗纱。
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
    meshSat: 1.45,
    meshBright: 0.96,
    lightWash: 0.0,
    artAlpha: 0.56,
    veilOpacity: 0.72,
    linearFactor: 0.56,
    radialStops: <double>[0.18, 0.96],
  );

  static const AmbientThemeProfile light = AmbientThemeProfile(
    meshAlpha: 0.38,
    meshSat: 1.18,
    meshBright: 1.16,
    lightWash: 0.26,
    artAlpha: 0.26,
    veilOpacity: 0.58,
    linearFactor: 0.50,
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

/// 环境光 `4×3` 矢量色网 LRU 采样缓存（对照新版样例 `Wallpaper.tsx` `useMesh`）。
///
/// 流程：`16×12` 解码 → `PictureRecorder(FilterQuality.high)` 缩绘至 `4×3` →
/// 提取 12 节点 RGB 与平均 RGB，容量上限 32 条（LRU 淘汰），并发同键复用单次解码。
class DesktopAmbientMeshCache {
  DesktopAmbientMeshCache._();

  static final DesktopAmbientMeshCache instance = DesktopAmbientMeshCache._();

  static const int maxEntries = 32;
  static const int _decodeWidth = 16;
  static const int _decodeHeight = 12;
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
          width: _decodeWidth,
          height: _decodeHeight,
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
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete(info);
        } else {
          info.dispose();
        }
      },
      onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
    );
    stream.addListener(listener);
    final info = await completer.future;
    if (info == null) return null;

    ui.Picture? picture;
    ui.Image? tiny;
    try {
      final src = info.image;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        src,
        Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
        Rect.fromLTWH(0, 0, _gridCols.toDouble(), _gridRows.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      picture = recorder.endRecording();
      tiny = await picture.toImage(_gridCols, _gridRows);
      final bytes = await tiny.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return null;

      final data = bytes.buffer.asUint8List();
      final points = <Color>[];
      var sumR = 0;
      var sumG = 0;
      var sumB = 0;
      const count = _gridCols * _gridRows;
      for (var i = 0; i < count; i++) {
        final offset = i * 4;
        final r = data[offset];
        final g = data[offset + 1];
        final b = data[offset + 2];
        sumR += r;
        sumG += g;
        sumB += b;
        points.add(Color.fromARGB(255, r, g, b));
      }
      final average = Color.fromARGB(
        255,
        (sumR / count).round(),
        (sumG / count).round(),
        (sumB / count).round(),
      );
      return AmbientMeshGrid(points: points, average: average);
    } finally {
      tiny?.dispose();
      picture?.dispose();
      info.dispose();
    }
  }
}

/// 4×3 矢量色网绘制器（对照 `Wallpaper.tsx:78-80`）：
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
/// 支持预采样 `preloadedGrid` 与浅色模式 `lightWash` 混柔消除发灰。
class DesktopAmbientMeshSurface extends StatefulWidget {
  const DesktopAmbientMeshSurface({
    required this.source,
    this.imageProvider,
    this.cacheKey,
    this.preloadedGrid,
    this.opacity = 1.0,
    this.saturation = 1.55,
    this.brightness = 1.05,
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

/// 右侧静态轻柔焦艺术面板。
///
/// - 彻底废除 60s `_pan` 动画，消除稳态持续 GPU 唤醒与边缘缓慢晃动；
/// - 静态渲染 `ImageFiltered(ImageFilter.blur(tileMode: TileMode.clamp))` +
///   双层 `ShaderMask(BlendMode.dstIn)`，全部封装在单帧 `RepaintBoundary` 内部
///   （稳态 0 次逐帧 blur 与 `saveLayer`）；
/// - 依据 [EditorialArtPreset] 与 [AmbientThemeProfile] 精细适配深浅色与媒体比例。
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

  /// 兼容旧调用签名；静态轻柔焦面板不再运行 60s pan 动画。
  final bool animate;

  static ColorFilter _artColorFilter({required bool isDark}) {
    final c = isDark ? 1.05 : 1.02;
    final t = 128.0 * (1.0 - c);
    final base = desktopColorMatrix(saturation: isDark ? 1.15 : 1.08);
    final matrix = List<double>.from(base);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        matrix[row * 5 + col] *= c;
      }
      matrix[row * 5 + 4] += t;
    }
    return ColorFilter.matrix(matrix);
  }

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

    final blurredArt = ImageFiltered(
      imageFilter: ui.ImageFilter.blur(
        sigmaX: preset.blurSigma,
        sigmaY: preset.blurSigma,
        tileMode: ui.TileMode.clamp,
      ),
      child: ColorFiltered(
        colorFilter: _artColorFilter(isDark: isDark),
        child: Image(
          image: ResizeImage(baseProvider, width: preset.decodeWidth),
          fit: BoxFit.cover,
          alignment: preset.alignment,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          opacity: AlwaysStoppedAnimation<double>(alpha),
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );

    final masked = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback:
          (rect) => LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: const <Color>[Colors.white, Colors.transparent],
            stops: preset.horizontalStops,
          ).createShader(rect),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback:
            (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const <Color>[Colors.white, Colors.transparent],
              stops: preset.verticalStops,
            ).createShader(rect),
        child: ClipRect(child: blurredArt),
      ),
    );

    return RepaintBoundary(
      child: Align(
        alignment: Alignment.centerRight,
        child: FractionallySizedBox(
          widthFactor: preset.widthFactor,
          heightFactor: 1.0,
          child: masked,
        ),
      ),
    );
  }
}

/// 环境光场景资源解析：并行采样 4×3 色网并预解码艺术面板（默认 220ms 软超时）。
///
/// 与 `DesktopAmbientMeshCache` 同处 mesh 库：这类 I/O 辅助一旦堆在
/// `desktop_ambient.dart` 会把绘制状态机挤出 900 行棘轮；超时或解码失败
/// 一律静默降级，由绘制层的 errorBuilder 与纸色兜底。
Future<AmbientMeshGrid?> resolveAmbientSceneAssets({
  required BuildContext context,
  required String source,
  required bool showArt,
  required EditorialArtPreset artPreset,
  AmbientMeshGrid? cachedGrid,
  Duration softTimeout = const Duration(milliseconds: 220),
}) async {
  AmbientMeshGrid? resolvedGrid = cachedGrid;
  final tasks = <Future<void>>[];

  if (resolvedGrid == null) {
    tasks.add(
      DesktopAmbientMeshCache.instance.sample(source).then((grid) {
        resolvedGrid = grid;
      }),
    );
  }

  if (showArt && context.mounted) {
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
