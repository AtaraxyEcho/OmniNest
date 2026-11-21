import 'package:flutter/material.dart';

/// 桌面/Web 端动效令牌。
///
/// 逐条对应样例 `desktop.css` 的 `--ease` / `--spring` 与各处 `animation:`
/// 的时长。与 [MotionToken] 分开：后者是移动端与工作台口径（150/300/400ms、
/// easeOutCubic），改它会让手机侧已定稿的过渡整体漂移；桌面样例是更慢的
/// 收束（.5–1.6s）加一条过冲弹簧，只能新增不能覆盖。
abstract final class DesktopMotion {
  // ── 曲线 ────────────────────────────────────────────────────────────
  /// `--ease: cubic-bezier(.22,.8,.24,1)`，入场、位移、面板展开的通用曲线。
  static const Cubic ease = Cubic(0.22, 0.8, 0.24, 1);

  /// `--spring: cubic-bezier(.34,1.45,.5,1)`，悬停/按下/弹层入场。
  static const Cubic spring = Cubic(0.34, 1.45, 0.5, 1);

  /// 唱片、进度环等匀速循环。
  static const Cubic linear = Cubic(0, 0, 1, 1);

  /// CSS `ease-out`，ken-burns 与缓慢推镜。
  static const Cubic easeOut = Cubic(0.25, 0.1, 0.25, 1);

  /// CSS 关键字 `ease-out`，用于和样例原生 CSS 动画一致的缓慢推镜。
  static const Cubic cssEaseOut = Cubic(0, 0, 0.58, 1);

  // 样例里另有 6 条专用曲线，之前只用了上面的通用档近似。
  /// 抽屉 `dr-in` 的 `cubic-bezier(.22,.9,.24,1)`。
  static const Cubic drawerCurve = Cubic(0.22, 0.9, 0.24, 1);

  /// 轻微过冲 `cubic-bezier(.34,1.35,.5,1)`。
  static const Cubic springSoft = Cubic(0.34, 1.35, 0.5, 1);

  /// 翻页 leaf `cubic-bezier(.5,.05,.3,1)`。
  static const Cubic flipCurve = Cubic(0.5, 0.05, 0.3, 1);

  /// 入场 `cubic-bezier(.2,.8,.2,1)`。
  static const Cubic riseCurve = Cubic(0.2, 0.8, 0.2, 1);

  /// 退场 `cubic-bezier(.5,0,.75,.2)`。
  static const Cubic exitCurve = Cubic(0.5, 0, 0.75, 0.2);

  // ── 时长（样例实测）─────────────────────────────────────────────────
  /// `.tb-btn` 的背景/颜色过渡。
  static const Duration fast = Duration(milliseconds: 200);

  /// Photos 样例长按 300ms 后进入照片排序拖动。
  /// 海报卡滑出播放钮的入场时长（样例 `Movies.tsx` 的 hover 提示）。
  static const Duration cardSlide = Duration(milliseconds: 340);

  /// 唱臂播放态微摆周期（3.4s，±0.35°）。
  static const Duration tonearmSway = Duration(milliseconds: 3400);

  /// 封面氛围光晕呼吸周期（4.2s）。
  static const Duration deckAura = Duration(milliseconds: 4200);

  /// 队列三柱均衡器的循环周期。
  static const Duration equalizerPulse = Duration(milliseconds: 900);

  /// 地点地球仪自转一圈的周期。
  static const Duration globeTurn = Duration(milliseconds: 900);

  /// 灯箱信息栏展开时舞台让位的时长。
  static const Duration viewerStage = Duration(milliseconds: 450);

  static const Duration photoReorderHold = Duration(milliseconds: 300);

  /// Photos 样例在长按预备 90ms 后压入所选缩略图。
  static const Duration photoReorderPressPreview = Duration(milliseconds: 90);

  /// Photos 多选拖动卡片从原位置聚合成堆的时长。
  static const Duration photoReorderFan = Duration(milliseconds: 560);

  /// Photos 多选堆每张卡片进入时的错开间隔。
  static const Duration photoReorderFanStagger = Duration(milliseconds: 28);

  /// Photos 拖拽堆计数徽标淡出速度。
  static const Duration photoReorderFastFade = Duration(milliseconds: 150);

  /// Photos FLIP 顺序交换动效时长。
  static const Duration photoReorderFlip = Duration(milliseconds: 460);

  /// Photos 卡片 FLIP 的 `cubic-bezier(.22,.7,.2,1)`。
  static const Cubic photoReorderFlipCurve = Cubic(0.22, 0.7, 0.2, 1);

  /// Photos 拖动结束后影像回到目标位置的时长。
  static const Duration photoReorderSettle = Duration(milliseconds: 420);

  /// Photos 拖放收束的 `cubic-bezier(.22,.7,.2,1)`。
  static const Cubic photoReorderSettleCurve = Cubic(0.22, 0.7, 0.2, 1);

  /// Photos 多选堆落位时各张卡片展开/淡出的时长。
  static const Duration photoReorderDrop = Duration(milliseconds: 300);

  /// Photos 拖放后选中照片落位反馈的时长。
  static const Duration photoReorderLanded = Duration(milliseconds: 500);

  /// Photos 长按时缩略图压入预览的时长。
  static const Duration photoReorderPressScale = Duration(milliseconds: 280);

  /// Photos 拖动源缩略图淡出速度。
  static const Duration photoReorderSourceFade = Duration(milliseconds: 350);

  /// Photos 缩略图悬停放大时长。
  static const Duration photoTileImageHover = Duration(milliseconds: 550);

  /// Photos 拖拽反馈跟随指针的每帧收敛比例，取自样例 `reorder.tsx` 的
  /// `cx += (px - cx) * 0.22`，让卡片保留极短的惯性而不抢过指针。
  static const double photoReorderPointerSmoothing = 0.22;

  /// `.ph.pressing` 的按压曲线。
  static const Cubic photoReorderPressCurve = Cubic(0.3, 0.7, 0.2, 1);

  /// Photos 连续换位的迟滞，防止指针停在边界时反复交换。
  static const Duration photoReorderSwapCooldown = Duration(milliseconds: 260);

  /// Photos 拖拽结束后忽略合成点击，避免拖放尾事件打开图片。
  static const Duration photoReorderClickGuard = Duration(milliseconds: 250);

  /// `--spring` 的悬停缩放。
  static const Duration springHover = Duration(milliseconds: 250);

  /// `.sidebar` 的宽度收展。
  static const Duration sidebar = Duration(milliseconds: 500);

  /// `.dock` 的宽度收展。
  static const Duration dock = Duration(milliseconds: 550);

  /// `.route` 的入场（opacity + 12px 位移 + 0.992 缩放收束）。
  static const Duration route = Duration(milliseconds: 420);

  /// 路由退场淡出时长。
  static const Duration routeExit = Duration(milliseconds: 200);

  /// 骨架切换到真实内容的淡入时长（样例 `.sk-done` 350ms）。
  static const Duration skeletonReveal = Duration(milliseconds: 350);

  /// 首页最近照片条的弹性扩张：样例 `.ps { transition: flex-grow .6s }`。
  static const Duration photoStrip = Duration(milliseconds: 600);

  /// `rise` 的默认时长。
  static const Duration rise = Duration(milliseconds: 700);

  /// `.modal` / `.palette` 的入场。
  static const Duration modal = Duration(milliseconds: 450);

  /// `.pop` 的入场。
  static const Duration pop = Duration(milliseconds: 280);

  /// `.toast` 的入场。
  static const Duration toast = Duration(milliseconds: 500);

  /// 标签、描边这类轻微的状态渐变。
  static const Duration soft = Duration(milliseconds: 300);

  /// 渐变/背景色的缓慢补间（样例 `.np-grad`、`.focus::before` 的 1s）。
  static const Duration colorFade = Duration(milliseconds: 1000);

  /// `.tilt` 的悬停抬升与透视回正。
  static const Duration lift = Duration(milliseconds: 350);

  /// 面板内容切换、滚动复位。
  static const Duration fade = Duration(milliseconds: 400);

  /// 区块级淡入/位移。
  static const Duration pane = Duration(milliseconds: 500);

  /// 阅读器 `.sw-track` 的横向滑动 `.36s`（`reader.css:56`）。
  static const Duration readerSlide = Duration(milliseconds: 360);

  /// `.route-load::before` 的扫描周期 `routebar 1.1s`（`polish.css:206`）。
  static const Duration routeBar = Duration(milliseconds: 1100);

  /// Photos 幻灯片下每张照片的 Ken Burns 缓推。
  static const Duration viewerKenBurns = Duration(seconds: 4);

  /// Photos 幻灯片下顶栏和胶片条的显隐过渡。
  static const Duration viewerChrome = Duration(milliseconds: 600);

  /// Photos `PhotoViewer` 外层 `.viewer` 的入场淡入。
  static const Duration photoViewerEnter = Duration(milliseconds: 320);

  /// Video 与 Reader 全局查看器外层的柔和缩放淡入。
  static const Duration immersiveViewerEnter = Duration(milliseconds: 320);

  /// Files 触控长按后开始移动文件的识别延迟（桌面鼠标仍立即拖动）。
  static const Duration longPressDrag = Duration(milliseconds: 500);

  /// Places 地图选中点的 `ping 2.4s ease-out infinite`（`desktop.css:351`）。
  /// 属内容节奏而不是交互反馈；只在有选中地点且未开启减动效时跑。
  static const Duration placePing = Duration(milliseconds: 2400);

  /// 抽屉 `dr-in .42s`（`polish.css:6`），比面板 pane 略快。
  static const Duration drawer = Duration(milliseconds: 420);

  /// `.scrim` 的入场 `fade .25s`（`desktop.css:137`）。
  static const Duration scrim = Duration(milliseconds: 250);

  /// `.drawer-scrim` 的入场 `dr-fade .32s`（`polish.css:4`）。
  static const Duration drawerScrim = Duration(milliseconds: 320);

  /// 抽屉退场 `dr-out .3s`（`polish.css:13`）：样例同时用 300ms 定时器收尾，
  /// 动画与移除严格同长，不会出现半透明残影。
  static const Duration drawerOut = Duration(milliseconds: 300);

  /// 影院文案逐条入场、封面圆角收束。
  static const Duration slow = Duration(milliseconds: 800);

  /// 登录画幅文案入场（样例 `.art-copy h1 { animation: rise 1s }`）。
  static const Duration authCopy = Duration(seconds: 1);

  /// 登录壁纸缓慢推镜（样例 `.auth-art .img { animation: kenburns 30s }`）。
  static const Duration authKenBurns = Duration(seconds: 30);

  /// 徽标出现时的弹入（样例 `pop .5s`）。
  static const Duration badge = Duration(milliseconds: 500);

  /// `.eq` 的循环节拍。
  static const Duration beat = Duration(seconds: 1);

  /// `.seg i` 的滑块位移。
  static const Duration segment = Duration(milliseconds: 450);

  /// `.mp`、`.mini-prog b` 的进度生长。
  static const Duration progress = Duration(milliseconds: 1200);

  /// `.amb-img` 的淡入淡出。
  static const Duration ambientFade = Duration(milliseconds: 1600);

  /// `.np` 的入场与退场。
  static const Duration nowPlayingIn = Duration(milliseconds: 500);
  static const Duration nowPlayingOut = Duration(milliseconds: 320);

  /// 歌词换句时滚到视口中央的跟随时长。
  static const Duration lyricsFollow = Duration(milliseconds: 480);

  /// 当前行歌词 1.06× 放大的收束时长。
  static const Duration lyricLineScale = Duration(milliseconds: 320);

  /// 书页翻页。
  static const Duration pageFlip = Duration(milliseconds: 820);

  /// 环境漂移、封面缓推、唱片旋转这类无限循环的周期。
  static const Duration driftCycle = Duration(seconds: 26);
  static const Duration floatCycle = Duration(seconds: 34);
  static const Duration kenBurns = Duration(seconds: 14);

  /// 三团环境光各自的漂移周期（样例 `.blob` 26s、`.b2` 34s、`.b3` 40s）。
  /// 周期不同才会自己错开相位，不需要额外偏移。
  static const Duration blobCycleFast = driftCycle;
  static const Duration blobCycleMid = floatCycle;
  static const Duration blobCycleSlow = Duration(seconds: 40);

  /// 环境光整层的强度淡变（样例 `.ambient { transition: opacity .6s }`）。
  static const Duration ambientLayer = Duration(milliseconds: 600);

  /// 环境光换封面：旧层 `.out` 淡出、新层 `.in` 淡入（样例 1.6s）。
  static const Duration ambientCoverSwap = Duration(milliseconds: 1600);

  /// 环境光封面首帧解码后的淡入（样例 `.mush { transition: opacity 1.2s }`）。
  static const Duration ambientCoverFade = Duration(milliseconds: 1200);

  /// `.pb-art.spin` / `.f-art.spin`：播放条 9s、大封面 14s。
  static const Duration vinylSpin = Duration(seconds: 9);
  static const Duration vinylSpinFull = Duration(seconds: 14);

  /// 唱臂落下 / 抬起（样例 `.tonearm` 的 1.5s）。
  static const Duration tonearm = Duration(milliseconds: 1500);

  /// 交错入场的单步间隔（样例 `--stagger: calc(var(--i) * 55ms)`）。
  static const Duration staggerStep = Duration(milliseconds: 55);

  /// 菜单项 `.mi` 的逐项错开比区块快得多（`desktop.css:131`）。
  static const Duration menuStaggerStep = Duration(milliseconds: 14);

  /// 图片占位微光 `.img:not(.ok) shimmer 1.8s`（`polish.css:204`）。
  static const Duration imageShimmer = Duration(milliseconds: 1800);

  /// 图片解码后淡入 `.img.ok{transition:opacity .6s}`（`desktop.css:53`）。
  static const Duration imageFade = Duration(milliseconds: 600);

  /// 骨架扫光 `sksweep 1.6s cubic-bezier(.4,0,.2,1)`（`polish.css:213`）。
  static const Duration skeletonSweep = Duration(milliseconds: 1600);
  static const Cubic skeletonCurve = Cubic(0.4, 0, 0.2, 1);

  /// 减弱动效时归零，其余情况返回原时长。
  static Duration of(BuildContext context, Duration duration) {
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false
        ? Duration.zero
        : duration;
  }

  /// 第 [index] 个元素的交错延迟（索引封顶至 8，最大延迟 440ms，避免长列表尾部久等）。
  static Duration stagger(BuildContext context, int index) {
    return of(context, staggerStep * index.clamp(0, 8));
  }

  /// 菜单项第 [index] 个的延迟，与区块 stagger 分开取值。
  static Duration menuStagger(BuildContext context, int index) {
    return of(context, menuStaggerStep * index);
  }
}

/// 样例 `rise`：淡入 + 上移 14px，是页面上几乎所有块级元素的入场。
///
/// `both` 语义：延迟期间保持起始态（不可见），播完保持终态。滚动进入视口
/// 才播的懒加载实现会与之冲突——样例里也是进页面即播，故这里同样一次性。
class DesktopRise extends StatefulWidget {
  const DesktopRise({
    required this.child,
    this.delay = Duration.zero,
    this.duration,
    this.offset = 14,
    this.offsetX = 0,
    super.key,
  });

  final Widget child;
  final Duration delay;
  final Duration? duration;

  /// 起始下移量（CSS `translateY(14px)`；12px 是 `.route` 的位移）。
  final double offset;

  /// 起始右移量；菜单项用 `-4`（样例 `@keyframes mi` 的 translateX(-4px)）。
  final double offsetX;

  @override
  State<DesktopRise> createState() => _DesktopRiseState();
}

class _DesktopRiseState extends State<DesktopRise>
    with SingleTickerProviderStateMixin {
  // 延迟并入控制器时长，而不是起一个 Future.delayed：定时器在测试里会
  // 以「pending timer」判定失败，且组件销毁前不会被回收。
  late final Duration _run = widget.duration ?? DesktopMotion.rise;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + _run,
  );
  bool _started = false;

  // 减弱动效要读 MediaQuery，而它在 initState 阶段还不可依赖：
  // 放到 didChangeDependencies，只启动一次。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    _start();
  }

  void _start() {
    if (!mounted) {
      return;
    }
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
      return;
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 把控制器进度换算成「延迟之后的 0→1」，等价于 CSS `animation-delay`。
  double get _progress {
    if (_run.inMicroseconds <= 0) {
      return 1;
    }
    final elapsed =
        _controller.value * (widget.delay + _run).inMicroseconds -
        widget.delay.inMicroseconds;
    return (elapsed / _run.inMicroseconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = DesktopMotion.ease.transform(_progress).clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset((1 - t) * widget.offsetX, (1 - t) * widget.offset),
            child: child,
          ),
        );
      },
      // 淡入期间的 `Opacity` 会把子树的 display list 直接录进自己的
      // saveLayer；没有边界时，卡片内部任何一帧变化都会连带整块内容重录。
      //
      // 不在这里做「动画结束后换成裸 child」的短路：那会在渡入完成的那一帧
      // 把渲染树拓扑从 Opacity→Transform→边界 改成裸边界，`desktop_files_view_test`
      // 的悬停断言实测会被这一次拓扑切换打断（行内动作停在 opacity 0），
      // 而 Opacity(1) 与恒等 Transform 本身不产生层也无像素差，收益为零。
      child: RepaintBoundary(child: widget.child),
    );
  }
}

/// 交错入场的第 [index] 个：等价于 `animation-delay: calc(var(--i) * 55ms)`。
class DesktopStagger extends StatelessWidget {
  const DesktopStagger({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DesktopRise(
      delay: DesktopMotion.stagger(context, index),
      child: child,
    );
  }
}
