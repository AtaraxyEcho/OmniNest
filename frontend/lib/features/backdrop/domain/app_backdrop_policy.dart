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

/// 前景模块提交给应用背景宿主的场景策略。
class AppBackdropPolicy {
  const AppBackdropPolicy({
    required this.scene,
    required this.visible,
    required this.playbackMode,
    required this.readabilityMode,
    required this.motionAllowed,
  });

  const AppBackdropPolicy.hidden()
    : scene = AppBackdropScene.hidden,
      visible = false,
      playbackMode = AppBackdropPlaybackMode.paused,
      readabilityMode = AppBackdropReadabilityMode.content,
      motionAllowed = false;

  final AppBackdropScene scene;
  final bool visible;
  final AppBackdropPlaybackMode playbackMode;
  final AppBackdropReadabilityMode readabilityMode;
  final bool motionAllowed;

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
  );

  /// 工具和管理页面隐藏背景并使用主题纯色。
  static const work = AppBackdropPolicy(
    scene: AppBackdropScene.work,
    visible: false,
    playbackMode: AppBackdropPlaybackMode.paused,
    readabilityMode: AppBackdropReadabilityMode.work,
    motionAllowed: false,
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
