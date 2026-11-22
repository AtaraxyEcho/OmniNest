import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/desktop/widgets/desktop_glass.dart';

/// 4×3 矢量色网采样结果（12 节点 RGB + 全局平均 RGB）。
class AmbientMeshGrid {
  const AmbientMeshGrid({required this.points, required this.average});

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
/// 并套用 `saturate(1.55) brightness(1.05)`（对照 `desktop.css:503`）。
class DesktopAmbientMeshSurface extends StatefulWidget {
  const DesktopAmbientMeshSurface({
    required this.source,
    this.imageProvider,
    this.cacheKey,
    this.opacity = 1.0,
    this.saturation = 1.55,
    this.brightness = 1.05,
    this.fallbackColor = Colors.transparent,
    super.key,
  });

  final String source;
  final ImageProvider<Object>? imageProvider;
  final String? cacheKey;
  final double opacity;
  final double saturation;
  final double brightness;
  final Color fallbackColor;

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
    if (oldWidget.source != widget.source ||
        oldWidget.cacheKey != widget.cacheKey) {
      _load();
    }
  }

  void _load() {
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
    final grid = _grid;
    if (grid == null) {
      return ColoredBox(color: widget.fallbackColor);
    }
    return ColorFiltered(
      colorFilter: desktopColorGrade(
        saturation: widget.saturation,
        brightness: widget.brightness,
      ),
      child: CustomPaint(
        painter: AmbientColourMeshPainter(grid: grid, opacity: widget.opacity),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// 右侧 64% 高清艺术面板（对照 `desktop.css:507-512` `.amb-art`）：
/// - 宽度 64% 靠右铺满，`ResizeImage(provider, width: 1280)` 高清解码不糊；
/// - 双层嵌套 `ShaderMask(BlendMode.dstIn)` 实现水平 `8%→96%` 与垂直 `55%→100%` 遮罩交集；
/// - `saturate(1.15) contrast(1.05)` 调色；
/// - 独立 60s `artpan` 缓推拉（`scale(1.02) → scale(1.10) translateX(-2%)`）。
class EditorialArtPanel extends StatefulWidget {
  const EditorialArtPanel({
    required this.source,
    required this.isDark,
    required this.intensityFactor,
    required this.animate,
    super.key,
  });

  final String source;
  final bool isDark;
  final double intensityFactor;
  final bool animate;

  @override
  State<EditorialArtPanel> createState() => _EditorialArtPanelState();
}

class _EditorialArtPanelState extends State<EditorialArtPanel>
    with SingleTickerProviderStateMixin {
  static const Duration _artPanDuration = Duration(seconds: 60);

  late final AnimationController _pan = AnimationController(
    vsync: this,
    duration: _artPanDuration,
  );

  @override
  void initState() {
    super.initState();
    _syncPan();
  }

  @override
  void didUpdateWidget(EditorialArtPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPan();
  }

  void _syncPan() {
    if (widget.animate) {
      if (!_pan.isAnimating) {
        _pan.repeat(reverse: true);
      }
    } else {
      if (_pan.isAnimating) {
        _pan.stop();
      }
      _pan.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pan.dispose();
    super.dispose();
  }

  static ColorFilter _artColorFilter() {
    const c = 1.05;
    const t = 128.0 * (1.0 - c);
    final base = desktopColorMatrix(saturation: 1.15);
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
    final alpha = ((widget.isDark ? 0.50 : 0.32) * widget.intensityFactor)
        .clamp(0.0, 1.0);
    if (alpha <= 0.001 || widget.source.isEmpty) {
      return const SizedBox.shrink();
    }
    final ImageProvider<Object> baseProvider =
        widget.source.startsWith('assets/')
            ? AssetImage(widget.source)
            : NetworkImage(widget.source);

    final artImage = ColorFiltered(
      colorFilter: _artColorFilter(),
      child: Image(
        image: ResizeImage(baseProvider, width: 1280),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        opacity: AlwaysStoppedAnimation<double>(alpha),
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );

    // 双层嵌套 ShaderMask(BlendMode.dstIn)：水平 8%→96% 与垂直 55%→100% 遮罩交集。
    final masked = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback:
          (rect) => const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: <Color>[Colors.white, Colors.transparent],
            stops: <double>[0.08, 0.96],
          ).createShader(rect),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback:
            (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Colors.white, Colors.transparent],
              stops: <double>[0.55, 1.0],
            ).createShader(rect),
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _pan,
            child: artImage,
            builder: (context, child) {
              final t = Curves.easeInOut.transform(_pan.value.clamp(0.0, 1.0));
              final scale = 1.02 + 0.08 * t;
              return FractionalTranslation(
                translation: Offset(-0.02 * t, 0),
                child: Transform.scale(scale: scale, child: child),
              );
            },
          ),
        ),
      ),
    );

    return Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: 0.64,
        heightFactor: 1.0,
        child: masked,
      ),
    );
  }
}
