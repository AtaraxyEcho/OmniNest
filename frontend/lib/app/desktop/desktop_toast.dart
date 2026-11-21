import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';

/// 标记当前子树已挂载桌面新版 Toast 容器。
///
/// 共享业务页与管理后台的 `showOmniFeedback` 经 [maybeOf] 检测后，在桌面端
/// 自动桥接至 [showDesktopToast]，避免弹出旧版顶部 toastification 提示条。
class DesktopToastScope extends InheritedWidget {
  const DesktopToastScope({required super.child, super.key});

  static DesktopToastScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DesktopToastScope>();
  }

  @override
  bool updateShouldNotify(DesktopToastScope oldWidget) => false;
}

/// 提示的语义档（样例 `.toast.success/.error/.info/.warn` 的 `--tc`）。
enum DesktopToastKind { success, info, warn, error }

extension on DesktopToastKind {
  Color color(DesktopSkin skin) => switch (this) {
    DesktopToastKind.success => skin.ok,
    DesktopToastKind.info => skin.info,
    DesktopToastKind.warn => skin.warn,
    DesktopToastKind.error => skin.bad,
  };

  IconData icon() => switch (this) {
    DesktopToastKind.success => DesktopIcons.check,
    DesktopToastKind.info => DesktopIcons.info,
    DesktopToastKind.warn => DesktopIcons.info,
    DesktopToastKind.error => DesktopIcons.trash,
  };
}

@immutable
class DesktopToastMessage {
  const DesktopToastMessage({
    required this.id,
    required this.message,
    required this.kind,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.duration,
  });

  final int id;
  final String message;
  final DesktopToastKind kind;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration? duration;

  /// 普通提示 4.2s；带动作或警告/错误态停留 6s（样例 `--life: 6s` / `4.2s`）。
  Duration get life {
    if (duration != null) {
      return duration!;
    }
    if (actionLabel != null ||
        kind == DesktopToastKind.error ||
        kind == DesktopToastKind.warn) {
      return const Duration(milliseconds: 6000);
    }
    return const Duration(milliseconds: 4200);
  }
}

/// 桌面提示栈。样例里每个动作（清空队列、全部已读、加入想看…）都经它回话，
/// 而壳层此前完全没有反馈通道：点了就是"静默成功"。
class DesktopToastController extends Notifier<List<DesktopToastMessage>> {
  int _sequence = 0;

  @override
  List<DesktopToastMessage> build() => const <DesktopToastMessage>[];

  int show(
    String message, {
    DesktopToastKind? kind,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final id = ++_sequence;
    // 样例按图标推断语义：删除类是错误、info 是提示，其余才是成功。
    var resolved = kind ?? DesktopToastKind.success;
    if (kind == null) {
      if (icon == DesktopIcons.trash) {
        resolved = DesktopToastKind.error;
      } else if (icon == DesktopIcons.info) {
        resolved = DesktopToastKind.info;
      }
    }
    final next = [
      ...state,
      DesktopToastMessage(
        id: id,
        message: message,
        kind: resolved,
        icon: icon,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      ),
    ];
    // 屏幕最多 4 条，超出时丢最旧的，避免连续操作铺满播放条上方。
    state = next.length > 4 ? next.sublist(next.length - 4) : next;
    return id;
  }

  void dismiss(int id) {
    state = state.where((toast) => toast.id != id).toList(growable: false);
  }
}

final desktopToastProvider =
    NotifierProvider<DesktopToastController, List<DesktopToastMessage>>(
      DesktopToastController.new,
    );

/// 在任意桌面组件里弹一条提示。
void showDesktopToast(
  BuildContext context,
  String message, {
  DesktopToastKind? kind,
  IconData? icon,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  ProviderScope.containerOf(context, listen: false)
      .read(desktopToastProvider.notifier)
      .show(
        message,
        kind: kind,
        icon: icon,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      );
}

/// 提示栈本体（样例 `.toasts`）：播放条上方居中，宽 min(420, 100%-32)。
class DesktopToasts extends ConsumerWidget {
  const DesktopToasts({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toasts = ref.watch(desktopToastProvider);
    if (toasts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 0,
      right: 0,
      bottom:
          DesktopMetrics.playerBarBottom + DesktopMetrics.playerBarHeight + 10,
      child: Semantics(
        liveRegion: true,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final toast in toasts)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _ToastItem(
                        key: ValueKey<int>(toast.id),
                        toast: toast,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastItem extends StatefulWidget {
  const _ToastItem({required this.toast, super.key});

  final DesktopToastMessage toast;

  @override
  State<_ToastItem> createState() => _ToastItemState();
}

class _ToastItemState extends State<_ToastItem> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: DesktopMotion.toast,
    value: 1,
  );
  late final AnimationController _life = AnimationController(
    vsync: this,
    duration: widget.toast.life,
  );
  late final AnimationController _leave = AnimationController(
    vsync: this,
    duration: DesktopMotion.soft,
  );
  Timer? _timer;
  bool _hovered = false;
  bool _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timer != null || _leaving) {
      return;
    }
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _enter.value = 1;
      _life.value = 1;
    } else {
      _enter.forward(from: 0);
      _life.forward(from: 0);
    }
    _schedule(widget.toast.life);
  }

  void _schedule(Duration after) {
    _timer?.cancel();
    _timer = Timer(after, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _enter.dispose();
    _life.dispose();
    _leave.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_leaving || !mounted) {
      return;
    }
    setState(() => _leaving = true);
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      // 样例 `reader.css:63`：reduce 下全局 animation-duration 收成 .01ms，
      // 退场近乎瞬时；这里不能还硬播 300ms。
      _leave.value = 1;
    } else {
      await _leave.forward();
    }
    if (!mounted) {
      return;
    }
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(desktopToastProvider.notifier).dismiss(widget.toast.id);
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered || _leaving) {
      return;
    }
    _hovered = hovered;
    if (hovered) {
      _timer?.cancel();
      _life.stop();
      setState(() {});
    } else {
      final fraction = (1 - _life.value).clamp(0.0, 1.0);
      final remaining = Duration(
        milliseconds: (widget.toast.life.inMilliseconds * fraction).round(),
      );
      if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
        _life.forward();
      }
      _schedule(remaining);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final toast = widget.toast;
    final tint = toast.kind.color(skin);
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedBuilder(
        animation: Listenable.merge([_enter, _leave]),
        builder: (context, child) {
          final enter = DesktopMotion.spring.transform(_enter.value);
          final leave = DesktopMotion.ease.transform(_leave.value);
          final opacity = (_enter.value * (1 - leave)).clamp(0.0, 1.0);
          final dy = (1 - enter) * 18 + leave * 8;
          final scale = 0.92 + 0.08 * enter - 0.06 * leave;
          return Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(scale: scale, child: child),
            ),
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: skin.shadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                constraints: const BoxConstraints(minWidth: 260),
                padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
                decoration: BoxDecoration(
                  color: skin.pop,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: skin.line2),
                ),
                child: Stack(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: tint.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            toast.icon ?? toast.kind.icon(),
                            size: 15,
                            color: tint,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            toast.message,
                            style: DesktopType.dense(
                              skin.text,
                            ).copyWith(height: 1.35),
                          ),
                        ),
                        if (toast.actionLabel != null) ...[
                          const SizedBox(width: 6),
                          _ToastAction(
                            label: toast.actionLabel!,
                            color: tint,
                            onTap: () {
                              toast.onAction?.call();
                              _dismiss();
                            },
                          ),
                        ],
                        const SizedBox(width: 2),
                        _ToastClose(
                          onTap: () {
                            _dismiss();
                          },
                        ),
                      ],
                    ),
                    // 生命条：线性缩到 0，悬停时暂停（样例 :hover 暂停动画）。
                    Positioned(
                      left: -12,
                      right: -10,
                      bottom: -11,
                      child: AnimatedBuilder(
                        animation: _life,
                        builder: (context, _) {
                          final remaining = 1 - _life.value;
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: remaining.clamp(0.0, 1.0),
                              child: Container(
                                height: 2,
                                color: tint.withValues(alpha: 0.65),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
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

class _ToastAction extends StatelessWidget {
  const _ToastAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: DesktopType.denseStrong(color),
      ),
      child: Text(label),
    );
  }
}

class _ToastClose extends StatelessWidget {
  const _ToastClose({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    // 样例 `Shell.tsx:326`：`aria-label=Close`——只有图标，读屏不然没有名字。
    return Tooltip(
      message: MaterialLocalizations.of(context).closeButtonTooltip,
      child: SizedBox(
        width: 24,
        height: 24,
        child: IconButton(
          onPressed: onTap,
          padding: EdgeInsets.zero,
          iconSize: 13,
          constraints: const BoxConstraints.tightFor(width: 24, height: 24),
          style: IconButton.styleFrom(
            foregroundColor: skin.text3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
          ),
          icon: const Icon(DesktopIcons.close),
        ),
      ),
    );
  }
}
