import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';

/// 建筑极简主义弹窗入口（工位公共实现）。
///
/// 统一承担规范要求的交互状态机：
/// - Esc 逐层退栈：复用路由栈天然 LIFO，每层弹窗独立路由；
/// - Tab 焦点陷阱：[WorkstationFocusTrap] 将键盘遍历锁定在弹窗内循环；
/// - 焦点记忆还原：关闭后焦点精确回到触发控件；
/// - 背景滚动锁定：遮罩吸收指针事件，背景不可滚动。
///
/// 遮罩 = 模糊 + 半透明着色（见 [WorkstationBlurScrim]）。
Future<T?> showWorkstationDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
  bool useRootNavigator = true,
  Color? barrierColor,
}) {
  final previousFocus = FocusManager.instance.primaryFocus;
  // 遮罩 = 模糊 + 半透明着色。barrierColor 置空，由路由子树内首个
  // 全屏 BackdropFilter 承担（showDialog 的 barrier 无法挂 ImageFilter）。
  return showDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: dismissible,
    barrierColor: Colors.transparent,
    builder:
        (dialogContext) => Stack(
          children: [
            // 模糊遮罩层对命中测试透明，否则会吞掉点击使屏障失效
            // （点击遮罩关闭将失灵）。
            WorkstationBlurScrim(color: barrierColor),
            Align(
              // 路由对 builder 产物下发的是紧满屏约束（原生 Dialog 自带
              // Center 松弛，自绘框架没有）——缺少这层松弛时
              // WorkstationDialogFrame 的 maxWidth 会被 tight 约束压满
              // 视口，表现为“弹窗铺满全屏”。
              alignment: Alignment.center,
              child: WorkstationFocusTrap(child: builder(dialogContext)),
            ),
          ],
        ),
  ).whenComplete(() {
    _restoreFocus(previousFocus);
  });
}

/// 模糊遮罩层：模糊 + 半透明着色，命中测试透明。
///
/// 只能作为 [Stack] 的直接子级使用（内部为 [Positioned.fill]）。
/// 透明命中测试是硬约束——遮罩一旦吃掉指针，路由屏障的
/// “点击遮罩关闭”就会失灵。
class WorkstationBlurScrim extends StatelessWidget {
  const WorkstationBlurScrim({this.color, super.key});

  /// 叠加在模糊之上的着色；缺省 black/45。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: ColoredBox(
              color: color ?? Colors.black.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    );
  }
}

/// [showGeneralDialog] 的模糊遮罩版本，供带自定义进出场过渡的浮层使用
/// （右缘抽屉、底部锚定面板、侧滑导航等）。
///
/// 与 [showWorkstationDialog] 的差异：内容面板由调用方的
/// [pageBuilder] 自行定位（Align/Positioned），过渡动画由
/// [transitionsBuilder] 原样保留；模糊遮罩独立于面板动画，
/// 以路由动画同步淡入淡出，行为对齐原生 barrier。
Future<T?> showWorkstationGeneralDialog<T>({
  required BuildContext context,
  required RoutePageBuilder pageBuilder,
  bool dismissible = true,
  String? barrierLabel,
  Color? barrierColor,
  Duration transitionDuration = const Duration(milliseconds: 220),
  RouteTransitionsBuilder? transitionsBuilder,
  bool useRootNavigator = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: dismissible,
    barrierLabel: barrierLabel,
    barrierColor: Colors.transparent,
    transitionDuration: transitionDuration,
    pageBuilder: pageBuilder,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final panel =
          transitionsBuilder?.call(
            context,
            animation,
            secondaryAnimation,
            child,
          ) ??
          FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
      return Stack(
        children: [
          IgnorePointer(
            child: FadeTransition(
              opacity: animation,
              child: WorkstationBlurScrim(color: barrierColor),
            ),
          ),
          panel,
        ],
      );
    },
  );
}

void _restoreFocus(FocusNode? node) {
  if (node == null) {
    return;
  }
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (node.context != null && node.canRequestFocus) {
      node.requestFocus();
    }
  });
}

/// 标准确认弹窗：直角容器 + 焦点陷阱 + 焦点还原，默认聚焦取消。
Future<bool> showWorkstationConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final l10n = MaterialLocalizations.of(context);
  final result = await showWorkstationDialog<bool>(
    context: context,
    builder:
        (dialogContext) => _WorkstationConfirmBody(
          title: title,
          message: message,
          confirmLabel: confirmLabel ?? l10n.okButtonLabel,
          destructive: destructive,
          requirePhrase: null,
        ),
  );
  return result == true;
}

/// 高危破坏性二次确认：alertdialog 语义、顶部绯红警示线、
/// 点击遮罩不可关闭、强制键入实体确认短语、默认焦点落在取消。
Future<bool> showWorkstationDestructiveConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmPhrase,
  String? confirmLabel,
}) async {
  final l10n = MaterialLocalizations.of(context);
  final result = await showWorkstationDialog<bool>(
    context: context,
    dismissible: false,
    builder:
        (dialogContext) => _WorkstationConfirmBody(
          title: title,
          message: message,
          confirmLabel: confirmLabel ?? l10n.okButtonLabel,
          destructive: true,
          requirePhrase: confirmPhrase,
        ),
  );
  return result == true;
}

class _WorkstationConfirmBody extends StatefulWidget {
  const _WorkstationConfirmBody({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.destructive,
    this.requirePhrase,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  final String? requirePhrase;

  @override
  State<_WorkstationConfirmBody> createState() =>
      _WorkstationConfirmBodyState();
}

class _WorkstationConfirmBodyState extends State<_WorkstationConfirmBody> {
  final TextEditingController _phraseController = TextEditingController();

  @override
  void dispose() {
    _phraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final requirePhrase = widget.requirePhrase;
    final phraseMatch =
        requirePhrase == null ||
        _phraseController.text.trim() == requirePhrase.trim();
    return WorkstationDialogFrame(
      title: widget.title,
      headerLabel: requirePhrase,
      destructive: widget.destructive,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.message),
          if (requirePhrase != null) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _phraseController,
              decoration: workstationInputDecoration(
                context,
                hintText: requirePhrase,
                prefixIcon: Icons.vpn_key_outlined,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancelButtonLabel),
        ),
        FilledButton(
          onPressed: phraseMatch ? () => Navigator.of(context).pop(true) : null,
          style:
              widget.destructive
                  ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: Colors.white,
                  )
                  : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// 弹窗内键盘焦点陷阱。
///
/// Tab / Shift+Tab 在弹窗路由的 FocusScope 内首尾环绕；同时监听全局
/// 焦点变化，焦点经任何路径（含文本框默认行为）逃逸出弹窗时立即
/// 拉回，保证焦点绝不游走出弹窗。
class WorkstationFocusTrap extends StatefulWidget {
  const WorkstationFocusTrap({required this.child, super.key});

  final Widget child;

  @override
  State<WorkstationFocusTrap> createState() => _WorkstationFocusTrapState();
}

class _WorkstationFocusTrapState extends State<WorkstationFocusTrap> {
  final GlobalKey _hostKey = GlobalKey();
  bool _lastTraversalForward = true;
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleFocusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 焦点通知可能在路由退场（deactivate 未到 dispose）期间到达，届时
    // 任何祖先查询都会触发 “deactivated widget's ancestor” 断言；
    // 路由在弹窗生命周期内不变，缓存后监听器内不再做任何 look-up。
    _route = ModalRoute.of(context);
  }

  // deactivate ≠ dispose：路由退场动画期间 State 仍挂在树上且 mounted 为
  // true，但祖先查询已非法。停用即摘除监听，重新激活时再挂回。
  @override
  void deactivate() {
    FocusManager.instance.removeListener(_handleFocusChange);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    FocusManager.instance.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    final host = _hostKey.currentContext;
    if (host == null) {
      return;
    }
    // 嵌套弹窗：上方还有更高层路由时由最顶层陷阱接管，避免两个陷阱
    // 每帧互相抢焦点（如配置编辑弹窗内再开清除凭据确认）。
    final route = _route;
    if (route != null && !route.isCurrent) {
      return;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) {
      return;
    }
    if (primary.context != null &&
        primary.context!
                .findAncestorStateOfType<_WorkstationFocusTrapState>() ==
            this) {
      return;
    }
    // 焦点已逃逸出弹窗：按最近一次遍历方向拉回首/尾可聚焦节点。
    // requestFocus 延迟到帧后执行——在语义/布局脏标记未清的当帧同步
    // 移动焦点会触发 '!semantics.parentDataDirty' 断言。
    final nodes = _focusableNodes();
    if (nodes.isEmpty) {
      return;
    }
    final forward = _lastTraversalForward;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final current = _focusableNodes();
      if (current.isEmpty) {
        return;
      }
      (forward ? current.first : current.last).requestFocus();
    });
  }

  List<FocusNode> _focusableNodes() {
    final host = _hostKey.currentContext;
    if (host == null) {
      return const <FocusNode>[];
    }
    final scope = FocusScope.of(host);
    return scope.descendants
        .where(
          (node) =>
              node.canRequestFocus &&
              node.context != null &&
              node.context!.widget is! ModalBarrier,
        )
        .toList(growable: false);
  }

  void _traverse(bool forward) {
    _lastTraversalForward = forward;
    final nodes = _focusableNodes();
    if (nodes.isEmpty) {
      return;
    }
    final primary = FocusManager.instance.primaryFocus;
    final cursor = nodes.indexOf(primary ?? nodes.first);
    FocusNode target;
    if (forward) {
      target =
          cursor < 0 || cursor >= nodes.length - 1
              ? nodes.first
              : nodes[cursor + 1];
    } else {
      target = cursor <= 0 ? nodes.last : nodes[cursor - 1];
    }
    target.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        NextFocusIntent: CallbackAction<NextFocusIntent>(
          onInvoke: (_) {
            _traverse(true);
            return null;
          },
        ),
        PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
          onInvoke: (_) {
            _traverse(false);
            return null;
          },
        ),
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.tab): NextFocusIntent(),
          SingleActivator(LogicalKeyboardKey.tab, shift: true):
              PreviousFocusIntent(),
        },
        child: FocusTraversalGroup(
          child: Builder(key: _hostKey, builder: (context) => widget.child),
        ),
      ),
    );
  }
}

/// 直角弹窗容器：1px 强边框、零阴影、固定 Header/Body/Footer 三段。
///
/// [destructive] 为 true 时呈现高危确认形态：顶部绯红警示线，
/// 需搭配 `showWorkstationDialog(dismissible: false)` 与默认聚焦取消按钮。
class WorkstationDialogFrame extends StatelessWidget {
  const WorkstationDialogFrame({
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
    this.headerLabel,
    this.width = 480,
    this.destructive = false,
    super.key,
  });

  final String title;

  /// 右上角等宽小标签（如节点类型、危险操作的实体名）。
  final String? headerLabel;

  final Widget body;

  /// 底部固定操作区按钮，右对齐排列。
  final List<Widget> actions;

  final double width;

  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: Material(
        color: scheme.surfaceContainer,
        child: Container(
          width: width,
          // 上限跟随请求宽度：宽详情弹窗（如 620）在小屏由父级约束自然收窄。
          constraints: BoxConstraints(maxWidth: width),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outline, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (destructive) Container(height: 2, color: scheme.error),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: destructive ? scheme.error : scheme.onSurface,
                        ),
                      ),
                    ),
                    if (headerLabel != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        headerLabel!,
                        style: TextStyle(
                          fontFamily: AppTypography.monoFamily,
                          fontFamilyFallback: AppTypography.monoFamilyFallback,
                          fontSize: AppTypography.labelSmall,
                          letterSpacing: 1.2,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    _WorkstationDialogCloseButton(),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: body,
                ),
              ),
              if (actions.isNotEmpty) ...[
                Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(spacing: 8, runSpacing: 4, children: actions),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 等宽小节标签（表单分组、弹窗内分区标题）。
class WorkstationDialogSectionLabel extends StatelessWidget {
  const WorkstationDialogSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      label,
      style: TextStyle(
        fontFamily: AppTypography.monoFamily,
        fontFamilyFallback: AppTypography.monoFamilyFallback,
        fontSize: AppTypography.labelSmall,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// 弹窗右上角关闭钮：28px 直角 hairline，点击 maybePop 关闭当前弹窗。
class _WorkstationDialogCloseButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = MaterialLocalizations.of(context);
    return Tooltip(
      message: l10n.closeButtonTooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: () => Navigator.of(context).maybePop(),
        customBorder: const RoundedRectangleBorder(),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outline, width: 1),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
