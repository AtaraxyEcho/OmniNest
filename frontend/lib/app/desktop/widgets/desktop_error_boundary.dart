import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/desktop/widgets/desktop_error_view.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';

/// 样例 `DesktopApp.tsx:34` 的 `Boundary`：子树的渲染错误就地变成 `.route-err`。
///
/// Flutter 没有 React 那样的局部 `componentDidCatch`：子树 build 抛错后框架用
/// `ErrorWidget` 顶替失败节点，而 `ErrorWidget` 的内容由**全局**的
/// `ErrorWidget.builder` 决定。这里的做法是在本子树构建前临时接管那个全局
/// 构造器、本帧结束后还原——接管的闭包里带上「重试」回调与本帧的文案，
/// 因此错误块仍然能定位到这一层。
///
/// 限制（有意接受）：只覆盖**构建期**错误；子控件在后续帧的 `setState` 里抛错
/// 时构造器已还原，仍会落到框架默认灰块。要覆盖那种情况只能全局常驻接管，
/// 会影响移动端与测试，不划算。
class DesktopErrorBoundary extends StatefulWidget {
  const DesktopErrorBoundary({
    required this.child,
    this.path,
    this.message,
    super.key,
  });

  final Widget child;

  /// 当前路由路径；切页时仅在上一页确实触发过错误时复位错误态，绝不销毁正常子树。
  final String? path;

  /// 覆盖默认文案（`desktopRouteError`）。
  final String? message;

  @override
  State<DesktopErrorBoundary> createState() => _DesktopErrorBoundaryState();
}

class _DesktopErrorBoundaryState extends State<DesktopErrorBoundary> {
  /// 重试就是重挂子树：换 key 让失败节点的状态一起丢掉。
  int _epoch = 0;

  /// 标记当前子树是否触发过构建期错误。
  bool _hasError = false;

  void _retry() {
    setState(() {
      _hasError = false;
      _epoch++;
    });
  }

  @override
  void didUpdateWidget(covariant DesktopErrorBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 路由切换时绝不销毁正常 child（避免销毁整棵 Router）；仅在上一页确实
    // 触发过构建期错误时才重置错误态。
    if (oldWidget.path != widget.path && _hasError) {
      _hasError = false;
      _epoch++;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 文案在正常上下文里取好再闭包进去：错误块构造时可能已经处在失败节点的
    // 位置，那里再 `dependOnInheritedWidgetOfExactType` 会挂到将废弃的 element 上。
    final l10n = AppLocalizations.of(context);
    final message = widget.message ?? l10n.desktopRouteError;
    final retryLabel = l10n.desktopRouteRetry;

    final previous = ErrorWidget.builder;
    ErrorWidget.builder = (details) {
      _hasError = true;
      return DesktopErrorView(
        message: message,
        retryLabel: retryLabel,
        onRetry: _retry,
        minHeightFactor: 0,
      );
    };
    final installed = ErrorWidget.builder;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 只还原自己装的那一版：外层边界或并行子树可能已经换过。
      if (ErrorWidget.builder == installed) {
        ErrorWidget.builder = previous;
      }
    });

    return KeyedSubtree(key: ValueKey<int>(_epoch), child: widget.child);
  }
}

/// 样例 `.route-load::before`：窗口顶部 2px 的强调色扫描条。
///
/// `height:2; width:40%; background:accent; radius:2;
/// animation: routebar 1.1s ease-in-out infinite`（从 `translateX(-100%)`
/// 扫到 `260%`）。减弱动效时按样例停帧成整条静态条。
class DesktopRouteProgressBar extends StatefulWidget {
  const DesktopRouteProgressBar({super.key});

  @override
  State<DesktopRouteProgressBar> createState() =>
      _DesktopRouteProgressBarState();
}

class _DesktopRouteProgressBarState extends State<DesktopRouteProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DesktopMotion.routeBar,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
      return;
    }
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      return SizedBox(height: 2, child: ColoredBox(color: skin.accent));
    }
    return LayoutBuilder(
      builder:
          (context, constraints) => SizedBox(
            height: 2,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                // `ease-in-out` 的近似：正弦缓动与 CSS 默认观感接近，
                // 且比 Curves.easeInOut 在两端更慢，扫过时不会突兀。
                final t = Curves.easeInOut.transform(_controller.value);
                final width = constraints.maxWidth * 0.4;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: -width + t * (constraints.maxWidth + width) * 1.3,
                      top: 0,
                      width: width,
                      height: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: skin.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
    );
  }
}

/// 路由切换期间的整页兜底：失败给 `.route-err`，仅真实异步加载挂起时给 2px 扫描条。
///
/// 样例把这两件事分别放在 `Boundary`（错误）与 `Suspense fallback`（加载）里，
/// 壳层只有这一个内容插槽，合在一处省得把 `path` 与动画状态各传两遍。
class DesktopRouteContainer extends StatelessWidget {
  const DesktopRouteContainer({
    required this.path,
    required this.child,
    this.loading = false,
    super.key,
  });

  final String path;
  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DesktopErrorBoundary(path: path, child: child),
        if (loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DesktopRouteProgressBar(),
          ),
      ],
    );
  }
}
