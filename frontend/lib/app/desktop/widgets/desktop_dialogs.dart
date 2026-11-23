import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';

/// 当前桌面弹层的「关闭并返回值」入口。
///
/// 弹层挂在壳层最外层的全窗口 Overlay，而不是 Navigator 的 route；卡片里
/// 没有 Navigator 祖先，所以调用点统一用 [closeDesktopModal] 收口，不能用
/// `Navigator.pop`。弹层外部（例如直接把 DesktopDialog 摆在页面里）则回退到
/// Navigator，保持既有调用方式可用。
class DesktopModalResultScope extends InheritedWidget {
  const DesktopModalResultScope({
    required this.complete,
    required super.child,
    super.key,
  });

  final void Function([Object? value]) complete;

  static DesktopModalResultScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopModalResultScope>();

  @override
  bool updateShouldNotify(DesktopModalResultScope oldWidget) => false;
}

/// 关闭当前桌面弹层并回传值；不在弹层内时退回 Navigator。
void closeDesktopModal(BuildContext context, [Object? value]) {
  final scope = DesktopModalResultScope.maybeOf(context);
  if (scope != null) {
    scope.complete(value);
    return;
  }
  Navigator.of(context).maybePop(value);
}

/// 桌面弹层（样例 `.modal` / `.drawer`）：遮罩铺满**整个窗口**。
///
/// 壳层把 Navigator 放在侧栏 232 / 坞 348 之间的内容区，且 Overlay 默认
/// `Clip.hardEdge`；用 `showGeneralDialog` 时无论怎么画 scrim 都盖不住
/// 标题栏、侧栏、坞与播放条。样例用 `Portal` 把 scrim 挂到 `.window`
/// （`inset: 0`），这里等价地插到 `rootOverlay`（壳层 `Overlay.wrap` 创建的
/// 全窗口 Overlay），遮罩与卡片同处一层。
Future<T?> showDesktopDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return _insertDesktopModal<T>(
    context,
    align: Alignment.center,
    dismissible: barrierDismissible,
    // 样例 `desktop.css:143`：入场 `translateY(14px) scale(.94)`。
    risePixels: 14,
    builder: builder,
  );
}

/// 通用桌面确认弹窗（样例 `.modal` 确认形态）：blur(4) 全窗遮罩 + 20px 圆角卡。
///
/// 内部通过 `Theme.of(context).extension<DesktopSkin>()` 取色（未登录态由
/// `DesktopThemeScope` 挂载，不依赖登录后才存在的 `DesktopShellHost`），确保
/// 登录页/首启页触发关窗确认也能正常渲染新版桌面弹窗。
Future<bool> showDesktopConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
  bool barrierDismissible = true,
  Widget? lead,
  Widget? extraContent,
  double width = 440,
}) async {
  final skin =
      Theme.of(context).extension<DesktopSkin>() ?? DesktopSkin.of(context);
  final l10n = MaterialLocalizations.of(context);
  final resolvedConfirm = confirmLabel ?? l10n.okButtonLabel;
  final resolvedCancel = cancelLabel ?? l10n.cancelButtonLabel;
  final result = await showDesktopDialog<bool>(
    context,
    barrierDismissible: barrierDismissible,
    builder:
        (dialogContext) => DesktopDialog(
          title: title,
          lead: lead,
          width: width,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: DesktopType.body(skin.text2).copyWith(height: 1.55),
              ),
              if (extraContent != null) ...[
                const SizedBox(height: 14),
                extraContent,
              ],
            ],
          ),
          actions: [
            DesktopButton(
              label: resolvedCancel,
              variant: DesktopButtonVariant.ghost,
              onPressed: () => closeDesktopModal(dialogContext, false),
            ),
            DesktopButton(
              label: resolvedConfirm,
              variant:
                  destructive
                      ? DesktopButtonVariant.danger
                      : DesktopButtonVariant.primary,
              onPressed: () => closeDesktopModal(dialogContext, true),
            ),
          ],
        ),
  );
  return result == true;
}

/// 弹层卡片本体：标题行 + 内容 + 右侧动作。
class DesktopDialog extends StatelessWidget {
  const DesktopDialog({
    required this.title,
    this.eyebrow,
    this.lead,
    this.content,
    this.actions = const <Widget>[],
    // 样例 `.modal` 默认 `min(460px, 92%)`；`.wide` 档由调用方传 760。
    this.width = 460,
    super.key,
  });

  final String title;
  final String? eyebrow;

  /// 标题左侧的图标舱（样例 `.d-id .fi`）。
  final Widget? lead;
  final Widget? content;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final skin =
        Theme.of(context).extension<DesktopSkin>() ?? DesktopSkin.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: MediaQuery.sizeOf(context).height - 96,
        ),
        child: Material(
          type: MaterialType.transparency,
          // 样例 `ui.tsx:186`：`role=dialog aria-modal=true`。
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: title,
            child: Container(
              decoration: BoxDecoration(
                color: skin.panelSolid,
                borderRadius: BorderRadius.circular(
                  DesktopMetrics.radiusDialog,
                ),
                border: Border.all(color: skin.line2),
                boxShadow: skin.shadow,
              ),
              clipBehavior: Clip.antiAlias,
              // 样例 `desktop.css:144-145` 的三段内距：头 22/24/4、主体
              // 14/24/24（有动作时底部让给动作区）、动作区上边距 20。
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (lead != null) ...[
                            lead!,
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (eyebrow != null) ...[
                                  Text(
                                    eyebrow!.toUpperCase(),
                                    style: DesktopType.eyebrow(skin.text3),
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                Text(
                                  title,
                                  style: DesktopType.displaySm(skin.text),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          DesktopIconButton(
                            icon: DesktopIcons.close,
                            tooltip:
                                MaterialLocalizations.of(
                                  context,
                                ).closeButtonTooltip,
                            onPressed: () => closeDesktopModal(context),
                          ),
                        ],
                      ),
                    ),
                    if (content != null)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          14,
                          24,
                          actions.isEmpty ? 24 : 0,
                        ),
                        child: content!,
                      ),
                    if (actions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 10,
                          runSpacing: 10,
                          children: actions,
                        ),
                      ),
                    if (content == null && actions.isEmpty)
                      const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 当前打开的弹层数：抽屉上再叠弹窗时，第二层用浅遮罩且不再模糊
/// （样例 `desktop.css:140` 的 `.window:has(.drawer-scrim) .scrim`）。
int _openModalCount = 0;

/// 右侧抽屉（样例 `ui.tsx:239` 的 `Drawer` + `Portal`）：全窗口 scrim，
/// 面板从右侧滑入、向左滑出（`dr-in .42s` / `dr-out .3s`），左侧两角 22 圆角。
/// 调用方只给内容，宽度由 [width] 控制；内容建议套 [DesktopDrawerFrame]。
Future<T?> showDesktopDrawer<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = 440,
  bool barrierDismissible = true,
}) {
  return _insertDesktopModal<T>(
    context,
    align: Alignment.centerRight,
    dismissible: barrierDismissible,
    slideWidth: width,
    builder:
        (drawerContext) => Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: width,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: DesktopSkin.of(context).panelSolid,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(22),
                ),
                border: Border(
                  left: BorderSide(color: DesktopSkin.of(context).line2),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 70,
                    spreadRadius: -20,
                    offset: Offset(-30, 0),
                  ),
                ],
              ),
              child: builder(drawerContext),
            ),
          ),
        ),
  );
}

/// 通用抽屉三段（样例 `ui.tsx:252-256`，间距取 `polish.css:8-10`）：
/// 头部 `22/24/14`、主体 `18/24/24`、底部 `14/24/18`，两处发丝分隔线。
///
/// 底部动作固定不随内容滚动——抽屉里最常见的错误就是把「保存」放进滚动区，
/// 内容一长就找不到了。
class DesktopDrawerFrame extends StatelessWidget {
  const DesktopDrawerFrame({
    required this.title,
    required this.child,
    this.eyebrow,
    this.subtitle,
    this.trailing,
    this.footer,
    super.key,
  });

  final String title;

  /// 主体内容；[child] 自己不需要滚动，框架已包一层。
  final Widget child;

  /// 标题上方的 11px 眉标（`BOOK DETAILS` 之类）。
  final String? eyebrow;

  /// 标题下方的辅助行，例如 `@username`。
  final String? subtitle;

  /// 头部右侧、关闭钮之前的附加动作。
  final Widget? trailing;

  /// 底部固定动作区，按行尾右对齐。
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final head = Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: DesktopType.eyebrow(skin.text3),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.displaySm(skin.text),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.caption(skin.text3),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
          DesktopIconButton(
            icon: DesktopIcons.close,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => closeDesktopModal(context),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        Divider(height: 1, color: skin.line),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            child: child,
          ),
        ),
        if (footer != null) ...[
          Divider(height: 1, color: skin.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
            // Align 给 footer 一个有界最大宽度：footer 常用 Row + Spacer
            // 把取消/保存推到右端，套在无界 Row 里会触发
            // "non-zero flex but unbounded width" 断言。
            child: Align(alignment: Alignment.centerRight, child: footer!),
          ),
        ],
      ],
    );
  }
}

Future<T?> _insertDesktopModal<T>(
  BuildContext context, {
  required Alignment align,
  required bool dismissible,
  required WidgetBuilder builder,
  double risePixels = 0,
  double slideWidth = 0,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final completer = Completer<T?>();
  final surfaceKey = GlobalKey<_DesktopModalSurfaceState>();
  late final OverlayEntry entry;
  var removed = false;

  void remove([Object? value]) {
    if (removed) return;
    removed = true;
    if (entry.mounted) entry.remove();
    if (!completer.isCompleted) {
      completer.complete(value is T ? value : null);
    }
  }

  /// 抽屉先播退场再拆；其余弹层（以及抽屉状态还没挂上时）直接拆。
  void close([Object? value]) {
    if (removed) return;
    final surface = surfaceKey.currentState;
    if (surface == null) {
      remove(value);
      return;
    }
    surface.playExit(() => remove(value));
  }

  entry = OverlayEntry(
    builder:
        (overlayContext) => DesktopModalResultScope(
          complete: close,
          child: _DesktopModalSurface(
            key: surfaceKey,
            align: align,
            dismissible: dismissible,
            onDismiss: () => close(null),
            risePixels: risePixels,
            slideWidth: slideWidth,
            builder: builder,
          ),
        ),
  );
  overlay.insert(entry);
  return completer.future;
}

/// scrim 与内容同层铺满整个窗口；卡片/面板各自做入场位移，遮罩不跟着动，
/// 否则窗口边缘会露出一条没有模糊/压暗的区域。
///
/// 焦点行为对齐样例 `ui.tsx:164-175` 的 `useDialogFocus`：打开时把焦点送进
/// 弹层（优先第一个 input/textarea/select），关闭时还给触发它的元素；弹层
/// 自带 `FocusScopeNode`（默认 `TraversalEdgeBehavior.closedLoop`），Tab 在
/// 首尾之间循环，不会漏到背后的页面上。
class _DesktopModalSurface extends StatefulWidget {
  const _DesktopModalSurface({
    required this.align,
    required this.dismissible,
    required this.onDismiss,
    required this.builder,
    this.risePixels = 0,
    this.slideWidth = 0,
    super.key,
  });

  final Alignment align;
  final bool dismissible;
  final VoidCallback onDismiss;
  final WidgetBuilder builder;
  final double risePixels;
  final double slideWidth;

  @override
  State<_DesktopModalSurface> createState() => _DesktopModalSurfaceState();
}

class _DesktopModalSurfaceState extends State<_DesktopModalSurface>
    with SingleTickerProviderStateMixin {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'desktop modal');
  FocusNode? _previousFocus;

  /// 退场进度 0→1：抽屉靠它滑出窗口，其余弹层直接跳过。
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: DesktopMotion.drawerOut,
  );
  VoidCallback? _pendingExit;
  bool _closing = false;

  /// 打开时是否已有别的弹层：有则本层用浅遮罩、不做背景模糊。
  bool _nested = false;

  /// 抽屉退场：关闭前先释放弹层焦点，播完（或被销毁）再交给外层拆 Overlay。
  void playExit(VoidCallback onDone) {
    if (_closing) {
      return;
    }
    _closing = true;
    if (_scope.hasFocus) {
      _scope.unfocus();
    }
    _pendingExit = onDone;
    if (widget.slideWidth <= 0) {
      _finishExit();
      return;
    }
    final run = DesktopMotion.of(context, DesktopMotion.drawerOut);
    setState(() {
      _exit.duration = run;
    });
    if (run == Duration.zero) {
      _finishExit();
      return;
    }
    _exit.forward().then((_) => _finishExit());
  }

  void _finishExit() {
    if (_scope.hasFocus) {
      _scope.unfocus();
    }
    final done = _pendingExit;
    _pendingExit = null;
    done?.call();
  }

  @override
  void initState() {
    super.initState();
    _nested = _openModalCount > 0;
    _openModalCount++;
    // `FocusScope(autofocus: true)` 先把焦点收进弹层，避免入场动画那一帧
    // 按键漏到背后；真正的首个输入框要等子树建完（post frame）才找得到。
    _previousFocus = FocusManager.instance.primaryFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final target = _firstEditableFocusNode();
      if (target != null) {
        target.requestFocus();
      } else {
        _scope.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    final previous = _previousFocus;
    _previousFocus = null;
    if (previous != null) {
      // 弹层拆除时子树已经卸载，等这一帧结束再把焦点还给触发元素。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (previous.context != null && previous.canRequestFocus) {
          previous.requestFocus();
        }
      });
    }
    // 退场动画被打断（外层提前拆）也要把拆 Overlay 的收尾跑掉，否则 entry
    // 永远留在树上。
    final pending = _pendingExit;
    _pendingExit = null;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => pending());
    }
    if (_scope.hasFocus) {
      _scope.unfocus();
    }
    _exit.dispose();
    _scope.dispose();
    if (_openModalCount > 0) {
      _openModalCount--;
    }
    super.dispose();
  }

  /// 样例 `el.querySelector("input, textarea, select")`：第一个可编辑控件，
  /// 没有则退回弹层自身（`?? el`）。
  FocusNode? _firstEditableFocusNode() {
    FocusNode? found;
    void visit(Element element) {
      if (found != null) {
        return;
      }
      final child = element.widget;
      if (child is EditableText) {
        if (child.focusNode.canRequestFocus) {
          found = child.focusNode;
        }
        return;
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  Widget _scrim() {
    if (_nested) {
      // 叠在抽屉/弹窗上：只压暗，不再叠一层模糊（否则背景糊成一片）。
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.dismissible ? widget.onDismiss : null,
        child: const ColoredBox(color: DesktopPalette.scrimNested),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.dismissible ? widget.onDismiss : null,
      child: BackdropFilter.grouped(
        // 桌面弹层挂在 rootOverlay 上，不在工作区的 BackdropGroup 子树里，
        // grouped 会回退成普通 backdrop（取样结果不变）；放在可能被包进
        // 组的场景（如页内抽屉）时才能共享取样。
        filterConfig: ImageFilterConfig(ImageFilter.blur(sigmaX: 4, sigmaY: 4)),
        child: const ColoredBox(color: DesktopPalette.scrim),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final panel = Align(
      alignment: widget.align,
      child: widget.builder(context),
    );
    final drawer = widget.slideWidth > 0;
    final animated =
        drawer
            ? TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 1, end: 0),
              duration: DesktopMotion.of(context, DesktopMotion.drawer),
              curve: DesktopMotion.drawerCurve,
              builder:
                  (context, dx, child) => Transform.translate(
                    offset: Offset(widget.slideWidth * dx, 0),
                    child: child,
                  ),
              child: panel,
            )
            : TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 1, end: 0),
              duration: DesktopMotion.of(context, DesktopMotion.modal),
              curve: DesktopMotion.spring,
              builder:
                  (context, dy, child) => Transform.translate(
                    offset: Offset(0, widget.risePixels * dy),
                    // 样例 `.modal` 入场：scale(.94) → 1。
                    child: Transform.scale(scale: 1 - 0.06 * dy, child: child),
                  ),
              child: panel,
            );
    // 抽屉退场：同一条 dr 曲线反向滑出，遮罩同步淡掉；退场期间吞掉指针，
    // 避免连点关闭把两次拆 Overlay 撞在一起。
    final withExit =
        drawer
            ? AnimatedBuilder(
              animation: _exit,
              builder: (context, child) {
                final t = DesktopMotion.drawerCurve.transform(_exit.value);
                return IgnorePointer(
                  ignoring: _closing,
                  child: Transform.translate(
                    offset: Offset(widget.slideWidth * t, 0),
                    child: child,
                  ),
                );
              },
              child: animated,
            )
            : animated;
    // 遮罩入场：`.scrim` 用 `fade .25s`，抽屉的 `.drawer-scrim` 用 `dr-fade .32s`
    // （`desktop.css:137` / `polish.css:4`）。两层 Opacity 相乘，退场淡出照旧。
    final scrimIn = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: DesktopMotion.of(
        context,
        drawer ? DesktopMotion.drawerScrim : DesktopMotion.scrim,
      ),
      curve: DesktopMotion.ease,
      builder:
          (context, t, child) =>
              Opacity(opacity: t, alwaysIncludeSemantics: true, child: child),
      child: _scrim(),
    );
    final scrim =
        drawer
            ? AnimatedBuilder(
              animation: _exit,
              builder:
                  (context, child) => Opacity(
                    opacity: 1 - _exit.value,
                    alwaysIncludeSemantics: true,
                    child: IgnorePointer(ignoring: _closing, child: child),
                  ),
              child: scrimIn,
            )
            : scrimIn;
    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: scrim),
        Positioned.fill(child: withExit),
      ],
    );
    // 样例 Modal / Drawer 都在 window 上监听 Escape（不看遮罩可否点击）；
    // 弹层不再走 route，必须自己接管，否则键盘关不掉。CallbackShortcuts
    // 要在 FocusScope 之外，焦点停在弹层自身时也能收到 Escape。
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
      },
      child: FocusScope(node: _scope, autofocus: true, child: stack),
    );
  }
}
