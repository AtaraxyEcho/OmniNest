/// 应用背景播放模式。
enum AppBackdropPlaybackMode { paused, continuous }

/// 应用背景可读性处理模式。
enum AppBackdropReadabilityMode { none, minimal, content, work, immersive }

/// 应用背景使用场景。
enum AppBackdropScene {
  hidden,
  portal,
  content,
  work,
  musicDeck,
  musicImmersive,
}

/// 全局环境模式：同一壁纸身份在移动壳层下的四档存在强度。
///
/// 环境连续性不等于全页面持续播放动态壁纸：各空间按任务选择档位，
/// 由宿主统一折算为壁纸不透明度、环境模糊与静态化策略。
enum AppEnvironmentMode {
  /// 首页与沉浸式音乐：壁纸完整存在，动态素材允许连续播放。
  immersive,

  /// 媒体库/照片/影视浏览：保留环境身份，降低动态与对比，内容为主。
  ambient,

  /// 阅读专注：壁纸静态化并大幅弱化，提高表面可读性。
  focus,

  /// 文件与系统工具：环境退到极弱存在感，接近实底表面。
  utility,
}

/// 环境模式对应的壁纸呈现参数（仅移动壳层消费）。
///
/// 两极性不是"同一张照片压暗/洗白"的程度差，而是**面不同**：样例第 4 层
/// 规定浅态只有沉浸档仍是摄影面（照片满显 + 墨色压暗渐变 + 浅色内容），
/// 其余三档照片 `opacity: 0`，环境层直接是纸面画布 `#e9eee7`。
class AppEnvironmentPresentation {
  const AppEnvironmentPresentation({
    required this.wallpaperOpacity,
    required this.blurSigma,
    required this.lightWallpaperOpacity,
    this.lightPhotoSaturate,
    this.lightPhotoContrast,
    this.lightPhotoBrightness,
  });

  /// 壁纸不透明度。
  final double wallpaperOpacity;

  /// 浅极性下的壁纸不透明度；0 表示该档换成画布面，照片不再参与。
  final double lightWallpaperOpacity;

  /// 非视频壁纸叠加的环境模糊 sigma；视频由宿主以遮罩降存在感。
  final double blurSigma;

  /// 浅态摄影面的照片处理，取样例 `filter: saturate() contrast() brightness()`；
  /// null 表示该档不做处理。
  final double? lightPhotoSaturate;
  final double? lightPhotoContrast;
  final double? lightPhotoBrightness;

  /// 浅态照片是否需要调色（只有摄影档要）。
  bool get hasLightPhotoFilter => lightPhotoSaturate != null;

  /// 按极性取实际不透明度（本文件不引 Flutter 类型，用布尔位表示浅极性）。
  double opacityFor({required bool light}) {
    return light ? lightWallpaperOpacity : wallpaperOpacity;
  }

  static const AppEnvironmentPresentation _immersive =
      AppEnvironmentPresentation(
        wallpaperOpacity: 1,
        lightWallpaperOpacity: 1,
        blurSigma: 0,
        lightPhotoSaturate: 0.82,
        lightPhotoContrast: 1.02,
        lightPhotoBrightness: 0.84,
      );
  static const AppEnvironmentPresentation _ambient = AppEnvironmentPresentation(
    wallpaperOpacity: 0.48,
    lightWallpaperOpacity: 0,
    blurSigma: 12,
  );
  static const AppEnvironmentPresentation _focus = AppEnvironmentPresentation(
    wallpaperOpacity: 0.28,
    lightWallpaperOpacity: 0,
    blurSigma: 28,
  );
  static const AppEnvironmentPresentation _utility = AppEnvironmentPresentation(
    wallpaperOpacity: 0.14,
    lightWallpaperOpacity: 0,
    blurSigma: 34,
  );

  static AppEnvironmentPresentation of(AppEnvironmentMode mode) {
    return switch (mode) {
      AppEnvironmentMode.immersive => _immersive,
      AppEnvironmentMode.ambient => _ambient,
      AppEnvironmentMode.focus => _focus,
      AppEnvironmentMode.utility => _utility,
    };
  }
}

/// 前景模块提交给应用背景宿主的场景策略。
class AppBackdropPolicy {
  const AppBackdropPolicy({
    required this.scene,
    required this.visible,
    required this.playbackMode,
    required this.readabilityMode,
    required this.motionAllowed,
    this.environmentMode = AppEnvironmentMode.immersive,
  });

  const AppBackdropPolicy.hidden()
    : scene = AppBackdropScene.hidden,
      visible = false,
      playbackMode = AppBackdropPlaybackMode.paused,
      readabilityMode = AppBackdropReadabilityMode.content,
      motionAllowed = false,
      environmentMode = AppEnvironmentMode.utility;

  final AppBackdropScene scene;
  final bool visible;
  final AppBackdropPlaybackMode playbackMode;
  final AppBackdropReadabilityMode readabilityMode;
  final bool motionAllowed;

  /// 移动壳层下的环境档位；桌面端不消费该字段，行为保持原语义。
  final AppEnvironmentMode environmentMode;

  /// Portal 使用低遮挡、连续播放的背景库策略。
  static const portal = AppBackdropPolicy(
    scene: AppBackdropScene.portal,
    visible: true,
    playbackMode: AppBackdropPlaybackMode.continuous,
    readabilityMode: AppBackdropReadabilityMode.minimal,
    motionAllowed: true,
  );

  /// Portal 移动端依靠局部表面保证可读性，不叠加全屏遮罩。
  static const portalMobile = AppBackdropPolicy(
    scene: AppBackdropScene.portal,
    visible: true,
    playbackMode: AppBackdropPlaybackMode.continuous,
    readabilityMode: AppBackdropReadabilityMode.none,
    motionAllowed: true,
  );

  /// 普通内容浏览使用高可读性和连续背景策略。
  static const content = AppBackdropPolicy(
    scene: AppBackdropScene.content,
    visible: true,
    playbackMode: AppBackdropPlaybackMode.continuous,
    readabilityMode: AppBackdropReadabilityMode.content,
    motionAllowed: true,
  );

  /// 媒体库页面显示静态背景快照，不播放动态内容。
  static const staticContent = AppBackdropPolicy(
    scene: AppBackdropScene.content,
    visible: true,
    playbackMode: AppBackdropPlaybackMode.paused,
    readabilityMode: AppBackdropReadabilityMode.content,
    motionAllowed: false,
    environmentMode: AppEnvironmentMode.focus,
  );

  /// 工具和管理页面隐藏背景并使用主题纯色。
  static const work = AppBackdropPolicy(
    scene: AppBackdropScene.work,
    visible: false,
    playbackMode: AppBackdropPlaybackMode.paused,
    readabilityMode: AppBackdropReadabilityMode.work,
    motionAllowed: false,
    environmentMode: AppEnvironmentMode.utility,
  );

  /// Music 内容浏览使用局部可读性保护和连续播放策略。
  static const musicDeck = AppBackdropPolicy(
    scene: AppBackdropScene.musicDeck,
    visible: true,
    playbackMode: AppBackdropPlaybackMode.continuous,
    readabilityMode: AppBackdropReadabilityMode.minimal,
    motionAllowed: true,
  );

  /// Music 沉浸播放使用最少遮挡和连续播放策略。
  static const musicImmersive = AppBackdropPolicy(
    scene: AppBackdropScene.musicImmersive,
    visible: true,
    playbackMode: AppBackdropPlaybackMode.continuous,
    readabilityMode: AppBackdropReadabilityMode.immersive,
    motionAllowed: true,
  );

  /// 移动端媒体空间（Library/照片/影视）环境档：静态化、降存在感。
  static const ambientMedia = AppBackdropPolicy(
    scene: AppBackdropScene.content,
    visible: true,
    playbackMode: AppBackdropPlaybackMode.paused,
    readabilityMode: AppBackdropReadabilityMode.content,
    motionAllowed: false,
    environmentMode: AppEnvironmentMode.ambient,
  );

  /// 移动端阅读空间环境档：极弱静态壁纸 + 高可读表面。
  static const focusReading = AppBackdropPolicy(
    scene: AppBackdropScene.content,
    visible: true,
    playbackMode: AppBackdropPlaybackMode.paused,
    readabilityMode: AppBackdropReadabilityMode.content,
    motionAllowed: false,
    environmentMode: AppEnvironmentMode.focus,
  );

  /// 移动端工具空间（Files/系统页）环境档：接近实底、保留环境身份。
  static const utilitySurface = AppBackdropPolicy(
    scene: AppBackdropScene.work,
    visible: true,
    playbackMode: AppBackdropPlaybackMode.paused,
    readabilityMode: AppBackdropReadabilityMode.work,
    motionAllowed: false,
    environmentMode: AppEnvironmentMode.utility,
  );
}

/// 当前生效的应用背景场景及其所有者。
class AppBackdropSceneState {
  const AppBackdropSceneState({
    this.owner,
    this.policy = const AppBackdropPolicy.hidden(),
  });

  final String? owner;
  final AppBackdropPolicy policy;
}
