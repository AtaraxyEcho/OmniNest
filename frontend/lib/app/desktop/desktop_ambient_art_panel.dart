part of 'desktop_ambient_mesh.dart';

/// 自适应画幅媒体艺术背景层（`ResizeImagePolicy.fit` 防上采样模糊）：
///
/// - 横图（`viewRatio / imgRatio <= 1.35` 或尚未解码完成）：全出血 `BoxFit.cover`
///   （深色 `Alignment(0.3, 0)` + `sat: 1.10, bright: 0.92`，浅色 `Alignment.center`）；
/// - 方图/竖图（`viewRatio / imgRatio > 1.35`）：右侧 62% 区域完整展示（`BoxFit.contain`），
///   并对艺术图左边缘施加 18% 宽度的 `ShaderMask(BlendMode.dstIn)` 平滑羽化遮罩，
///   在浅色 `#F4F6F2` 底色与深色 4×3 色网上均无矩形硬边；
/// - 封装在独立 `RepaintBoundary` 内，稳态 0 次逐帧重绘。
class EditorialArtPanel extends StatefulWidget {
  const EditorialArtPanel({
    required this.source,
    required this.isDark,
    required this.intensityFactor,
    this.preset = EditorialArtPreset.landscape,
    this.profile,
    this.imageProvider,
    this.animate = false,
    this.onImageError,
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

  /// 图片加载失败时的通知回调（如用于清理过期 hint）。
  final VoidCallback? onImageError;

  @override
  State<EditorialArtPanel> createState() => _EditorialArtPanelState();
}

class _EditorialArtPanelState extends State<EditorialArtPanel> {
  static const double _compactAspectThreshold = 1.35;
  static const double _compactWidthFactor = 0.62;
  static const double _leftFeatherStop = 0.18;

  ImageStream? _imageStream;
  ImageStreamListener? _streamListener;
  ImageProvider<Object>? _effectiveProvider;
  double? _imgRatio;
  bool _resolvingSync = false;
  bool _errorNotified = false;

  ImageProvider<Object> _buildEffectiveProvider() {
    final ImageProvider<Object> baseProvider =
        widget.imageProvider ??
        (widget.source.startsWith('assets/')
            ? AssetImage(widget.source)
            : NetworkImage(widget.source));
    return ResizeImage(
      baseProvider,
      width: widget.preset.decodeWidth,
      policy: ResizeImagePolicy.fit,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeImageStream();
  }

  @override
  void didUpdateWidget(EditorialArtPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.imageProvider != widget.imageProvider ||
        oldWidget.preset.decodeWidth != widget.preset.decodeWidth) {
      _imgRatio = null;
      _errorNotified = false;
      _subscribeImageStream();
    }
  }

  void _subscribeImageStream() {
    _detachStream();
    if (widget.source.isEmpty) {
      _effectiveProvider = null;
      return;
    }
    final provider = _buildEffectiveProvider();
    _effectiveProvider = provider;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      _handleImage,
      onError: _handleImageError,
    );
    _imageStream = stream;
    _streamListener = listener;
    _resolvingSync = true;
    try {
      stream.addListener(listener);
    } finally {
      _resolvingSync = false;
    }
  }

  void _detachStream() {
    final stream = _imageStream;
    final listener = _streamListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _streamListener = null;
  }

  void _handleImage(ImageInfo info, bool synchronousCall) {
    final width = info.image.width;
    final height = info.image.height;
    info.dispose();
    if (width <= 0 || height <= 0) {
      return;
    }
    final ratio = width / height;
    if (_imgRatio != null && (_imgRatio! - ratio).abs() < 0.005) {
      return;
    }
    if (synchronousCall || _resolvingSync) {
      _imgRatio = ratio;
    } else if (mounted) {
      setState(() => _imgRatio = ratio);
    }
  }

  void _handleImageError(Object error, StackTrace? stackTrace) {
    _notifyImageError();
  }

  void _notifyImageError() {
    if (_errorNotified) {
      return;
    }
    _errorNotified = true;
    final callback = widget.onImageError;
    if (callback == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      callback();
    });
  }

  @override
  void dispose() {
    _detachStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.source.isEmpty) {
      return const SizedBox.shrink();
    }
    final effectiveProfile =
        widget.profile ?? AmbientThemeProfile.of(isDark: widget.isDark);
    // 浅色非 Reader 直接以 opacity = 1.0 绘制，取消多重白雾打折；
    // 深色侧由外层 ambient 图层组统一施加 intensityFactor，避免二次打折。
    final alpha =
        widget.isDark
            ? (effectiveProfile.artAlpha * widget.preset.opacityMultiplier)
                .clamp(0.0, 1.0)
            : 1.0;
    if (alpha <= 0.001) {
      return const SizedBox.shrink();
    }
    final effectiveProvider = _effectiveProvider ?? _buildEffectiveProvider();

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewRatio =
              (constraints.maxWidth > 0 && constraints.maxHeight > 0)
                  ? constraints.maxWidth / constraints.maxHeight
                  : 16.0 / 9.0;
          final imgRatio = _imgRatio;
          final isCompactAspect =
              imgRatio != null &&
              imgRatio > 0 &&
              (viewRatio / imgRatio) > _compactAspectThreshold;

          Widget art = Image(
            image: effectiveProvider,
            fit: isCompactAspect ? BoxFit.contain : BoxFit.cover,
            alignment:
                isCompactAspect
                    ? Alignment.centerRight
                    : (widget.isDark
                        ? const Alignment(0.3, 0)
                        : Alignment.center),
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            opacity: AlwaysStoppedAnimation<double>(alpha),
            errorBuilder: (_, _, _) {
              _notifyImageError();
              return const SizedBox.shrink();
            },
          );

          if (widget.isDark) {
            art = ColorFiltered(
              colorFilter: desktopColorGrade(
                saturation: 1.10,
                brightness: 0.92,
              ),
              child: art,
            );
          }

          if (!isCompactAspect) {
            return SizedBox.expand(child: art);
          }

          return Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: _compactWidthFactor,
              heightFactor: 1.0,
              child: Align(
                alignment: Alignment.centerRight,
                child: AspectRatio(
                  aspectRatio: imgRatio,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (Rect bounds) {
                      return const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: <Color>[Colors.transparent, Colors.black],
                        stops: <double>[0.0, _leftFeatherStop],
                      ).createShader(bounds);
                    },
                    child: art,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
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
  ImageProvider<Object>? imageProvider,
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
      DesktopAmbientMeshCache.instance
          .sample(source, imageProvider: imageProvider)
          .then((grid) {
            if (isCancelled?.call() ?? false) return;
            resolvedGrid = grid;
          }),
    );
  }

  if (showArt && context.mounted && !(isCancelled?.call() ?? false)) {
    final ImageProvider<Object> baseProvider =
        imageProvider ??
        (source.startsWith('assets/')
            ? AssetImage(source)
            : NetworkImage(source));
    final resized = ResizeImage(
      baseProvider,
      width: artPreset.decodeWidth,
      policy: ResizeImagePolicy.fit,
    );
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
