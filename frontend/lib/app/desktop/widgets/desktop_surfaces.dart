import 'package:flutter/material.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 样例 `.eyebrow`：大写小字眉标。
class DesktopEyebrow extends StatelessWidget {
  const DesktopEyebrow(this.text, {this.color, this.padding, super.key});

  final String text;
  final Color? color;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Text(
        text.toUpperCase(),
        style: DesktopType.eyebrow(color ?? skin.text3),
      ),
    );
  }
}

/// 样例 `.page`：限宽 1560、左右 24-52 自适应、底部为播放条留白。
class DesktopPage extends StatelessWidget {
  const DesktopPage({
    required this.children,
    this.maxWidth = DesktopMetrics.pageMaxWidth,
    this.topPadding,
    this.staggerChildren = false,
    super.key,
  });

  final List<Widget> children;
  final double maxWidth;
  final double? topPadding;

  /// 首页按样例给每个顶层区块挂 55ms 交错入场；其他页面保持即显。
  final bool staggerChildren;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = (width * 0.03).clamp(
      DesktopMetrics.pageHorizontalMin,
      DesktopMetrics.pageHorizontalMax,
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            topPadding ?? DesktopMetrics.pageTopPadding,
            horizontal,
            DesktopMetrics.playerBarClearance,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++)
                staggerChildren
                    ? DesktopStagger(index: i, child: children[i])
                    : children[i],
            ],
          ),
        ),
      ),
    );
  }
}

/// 样例 `.page-head`：眉标 + 衬线大标题 + 副标题 + 右侧动作区。
class DesktopPageHead extends StatelessWidget {
  const DesktopPageHead({
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions = const <Widget>[],
    this.actionsRightAlignedWhenWrapped = false,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;
  final bool actionsRightAlignedWhenWrapped;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (eyebrow != null) DesktopEyebrow(eyebrow!),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(title, style: DesktopType.display(skin.text)),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(subtitle!, style: DesktopType.body(skin.text2)),
          ),
      ],
    );
    // 样例 `.head-actions` 是不换行 flex；窄窗口只让整组动作换到标题下方。
    final actionContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          actions[index],
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 26),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (actions.isEmpty || !actionsRightAlignedWhenWrapped) {
            return Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 20,
              runSpacing: 14,
              children: [
                heading,
                if (actions.isNotEmpty)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
              ],
            );
          }

          if (constraints.maxWidth < DesktopMetrics.pageHeadSplitBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerRight, child: actionContent),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 20),
              actionContent,
            ],
          );
        },
      ),
    );
  }
}

/// 样例 `.sect` + `.sect-head`：区块标题与「查看全部」链接。
class DesktopSection extends StatelessWidget {
  const DesktopSection({
    required this.title,
    required this.child,
    this.eyebrow,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    super.key,
  });

  final String title;
  final Widget child;
  final String? eyebrow;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom:
            compact
                ? DesktopMetrics.sectionGapCompact
                : DesktopMetrics.sectionGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null) DesktopEyebrow(eyebrow!),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          title,
                          style: DesktopType.sectionTitle(skin.text),
                        ),
                      ),
                    ],
                  ),
                ),
                if (actionLabel != null)
                  DesktopLink(label: actionLabel!, onPressed: onAction),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// 样例 `.link`：强调色文字 + 右尖括号。
class DesktopLink extends StatelessWidget {
  const DesktopLink({
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailing = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      enabled: onPressed != null,
      builder:
          (context, hovered) => GestureDetector(
            onTap: onPressed,
            behavior: HitTestBehavior.opaque,
            child: Opacity(
              opacity: hovered ? 0.75 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 13, color: skin.accent),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.link(skin.accent),
                      ),
                    ),
                    if (trailing)
                      Icon(DesktopIcons.chevron, size: 14, color: skin.accent),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

/// 样例 `.card`：半透明面板 + 发丝描边 + 18 圆角。
class DesktopCard extends StatelessWidget {
  const DesktopCard({
    required this.child,
    this.title,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(24, 22, 24, 22),
    super.key,
  });

  final Widget child;
  final String? title;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    // `.card { backdrop-filter: blur(24px) saturate(1.3) }`：模糊的是背后的
    // 环境光，而不是卡片内容，所以滤镜放在容器外层。
    // 卡片间距必须留在滤镜**外面**：放进 ClipRRect 里时那 16px 全透明带
    // 也会被模糊采样，卡与卡之间出现一条糊掉的条纹（CSS 的 margin 本来就是
    // 元素外的东西），同时白付一份 16px 高的模糊面积。
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
        child: BackdropFilter.grouped(
          filterConfig: ImageFilterConfig(
            desktopGlassFilter(blur: 24, saturation: 1.3),
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: skin.panel,
              borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
              border: Border.all(color: skin.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title!,
                            style: DesktopType.cardTitle(skin.text),
                          ),
                        ),
                        if (action != null) action!,
                      ],
                    ),
                  ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 样例 `.mini-prog`：4px 进度条，右侧百分比小字。
class DesktopProgress extends StatelessWidget {
  const DesktopProgress({
    required this.fraction,
    this.label,
    this.large = false,
    this.color,
    super.key,
  });

  final double fraction;
  final String? label;
  final bool large;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final clamped = fraction.clamp(0.0, 1.0);
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: large ? 6 : 4,
        child: Stack(
          children: [
            ColoredBox(color: skin.raise3),
            FractionallySizedBox(
              widthFactor: clamped,
              child: ColoredBox(color: color ?? skin.accent),
            ),
          ],
        ),
      ),
    );
    if (label == null) {
      return bar;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        bar,
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(label!, style: DesktopType.micro(skin.text3)),
        ),
      ],
    );
  }
}

/// 样例 `.kv`：左标签右值的两列定义表。
class DesktopKeyValues extends StatelessWidget {
  const DesktopKeyValues({
    required this.entries,
    this.alignValuesRight = true,
    super.key,
  });

  final List<MapEntry<String, String>> entries;
  final bool alignValuesRight;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.key, style: DesktopType.dense(skin.text3)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      entry.value,
                      textAlign:
                          alignValuesRight ? TextAlign.right : TextAlign.left,
                      style: DesktopType.dense(skin.text),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 样例 `.empty`：圆形光晕章 + 标题/说明分层 + soft 按钮动作。
class DesktopEmpty extends StatelessWidget {
  const DesktopEmpty({
    required this.message,
    this.icon = DesktopIcons.info,
    this.description,
    this.actionLabel,
    this.onAction,
    this.large = false,
    this.small = false,
    super.key,
  });

  final String message;
  final IconData icon;

  /// 可选第二行说明；不传时保持单段空态，兼容既有 23 处调用点。
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 整页级空态（样例 `.empty.big`：`padding 90px 20px`）。
  final bool large;

  /// 面板内嵌空态（样例 `.empty-sm`：`padding 24px 16px`，图标 18 + 11）。
  /// 与 [large] 同时为真时按整页级渲染。
  final bool small;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final accent = skin.accent;
    final compact = small && !large;
    // 样例 `polish.css:235-239` 的三档内边距（`.empty` 被 polish 覆盖成 44/24）。
    final padding =
        large
            ? const EdgeInsets.symmetric(vertical: 90, horizontal: 20)
            : compact
            ? const EdgeInsets.symmetric(vertical: 24, horizontal: 16)
            : const EdgeInsets.symmetric(vertical: 44, horizontal: 24);
    final iconSize = compact ? 18.0 : 24.0;
    // `box-sizing: content-box`：圆由「图标 + 内边距」撑出，不写死直径。
    final iconPadding = compact ? 11.0 : 16.0;
    return Semantics(
      container: true,
      // 样例 `ui.tsx:128`：空态是 `role=status`，读屏会主动播报。
      liveRegion: true,
      label: message,
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: compact ? 6 : 10),
              child: Container(
                padding: EdgeInsets.all(iconPadding),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // `radial-gradient(circle at 30% 25%, accent 22%, accent 8%)`：
                  // 圆心换算成 Alignment 就是 (30%,25%) → (-0.4,-0.5)；CSS 的
                  // 默认半径是 farthest-corner（正方形对角 ≈1.03 个边长），
                  // 压成 0.5 会让边缘过早掉到 8%，整体发暗。
                  gradient: RadialGradient(
                    center: const Alignment(-0.4, -0.5),
                    radius: 1.03,
                    colors: [
                      accent.withValues(alpha: 0.22),
                      accent.withValues(alpha: 0.08),
                    ],
                  ),
                  // `0 0 0 7px accent 6%`：圆外的柔光环。
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.06),
                      blurRadius: 0,
                      spreadRadius: 7,
                    ),
                  ],
                ),
                // `inset 0 0 0 1px accent 22%` 画在盒内：用 foregroundDecoration
                // 而不是 border，后者会按 CSS `border` 语义把边宽算进盒子尺寸，
                // 圆就从 56 涨到 58。
                foregroundDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                ),
                child: Icon(icon, size: iconSize, color: accent),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                message,
                textAlign: TextAlign.center,
                // `.empty > strong`：15 / 600 / 正文色。
                style: DesktopType.medium(
                  skin.text,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (description != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    description!,
                    textAlign: TextAlign.center,
                    // `.empty p`：13 / 1.55 / text3。
                    style: DesktopType.dense(skin.text3).copyWith(height: 1.55),
                  ),
                ),
              ),
            if (actionLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: DesktopButton(
                  label: actionLabel!,
                  variant: DesktopButtonVariant.soft,
                  onPressed: onAction,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 样例 `.img`：加载期为微光底，解码后 600ms 淡入；失败保留底面不露破图。
class DesktopImage extends StatelessWidget {
  const DesktopImage({
    required this.url,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.cacheWidth,
    this.fallbackIcon,
    super.key,
  });

  final String? url;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// 缩略图场景按显示尺寸限制解码宽度；null 保持原图解码（全屏查看器用）。
  final int? cacheWidth;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final placeholder = _ImageShimmer(borderRadius: borderRadius);
    final skin = DesktopSkin.of(context);
    final fallback = ColoredBox(
      color: skin.raise2,
      child:
          fallbackIcon == null
              ? null
              : Center(child: Icon(fallbackIcon, size: 28, color: skin.text3)),
    );
    Widget content = fallback;
    final source = url;
    if (source != null && source.isNotEmpty) {
      content = Image.network(
        source,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        cacheWidth: cacheWidth,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          // 解码完成才把图挂上去，首帧从 0 淡到 1（`.img.ok`）。
          if (wasSynchronouslyLoaded || frame != null) {
            return _ImageFadeIn(child: child);
          }
          return placeholder;
        },
        loadingBuilder:
            (context, child, progress) =>
                progress == null ? child : placeholder,
        errorBuilder: (context, error, stack) => fallback,
      );
    }
    if (borderRadius != null) {
      content = ClipRRect(borderRadius: borderRadius!, child: content);
    }
    return content;
  }
}

/// 图片加载期的微光底（样例 `.img:not(.ok){animation:shimmer 1.8s}`）。
class _ImageShimmer extends StatefulWidget {
  const _ImageShimmer({required this.borderRadius});

  final BorderRadius? borderRadius;

  @override
  State<_ImageShimmer> createState() => _ImageShimmerState();
}

class _ImageShimmerState extends State<_ImageShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DesktopMotion.imageShimmer,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
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
    final base = skin.raise2;
    final highlight = Color.lerp(base, skin.text, 0.06)!;
    final radius = widget.borderRadius ?? BorderRadius.zero;
    return AnimatedBuilder(
      animation: _controller,
      builder:
          (context, _) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment(-1.6 + _controller.value * 3.2, 0),
                end: Alignment(-0.6 + _controller.value * 3.2, 0),
                colors: [base, highlight, base],
              ),
            ),
          ),
    );
  }
}

/// 解码完成后的 600ms 淡入；首帧渲染时才把透明度推到 1。
class _ImageFadeIn extends StatefulWidget {
  const _ImageFadeIn({required this.child});

  final Widget child;

  @override
  State<_ImageFadeIn> createState() => _ImageFadeInState();
}

class _ImageFadeInState extends State<_ImageFadeIn> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _shown = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: DesktopMotion.of(context, DesktopMotion.imageFade),
      curve: DesktopMotion.ease,
      child: widget.child,
    );
  }
}

/// 卡片 hover 抬升 + 轻微放大，对应样例 `.tilt` / `.album:hover`。
class DesktopHoverLift extends StatelessWidget {
  const DesktopHoverLift({
    required this.child,
    this.onTap,
    this.onSecondaryTap,
    this.lift = 4,
    this.tooltip,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final double lift;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget content = DesktopHover(
      enabled: onTap != null,
      builder:
          (context, hovered) => TweenAnimationBuilder<double>(
            // 样例 `.stat:hover { transform: translateY(-3px) }` 与
            // `.album:hover { translateY(-4px) }` 都是固定 px，时长 350ms
            // 且走 `--spring`；用百分比位移会让卡片越高抬得越多。
            tween: Tween<double>(end: hovered ? -lift : 0),
            duration: MotionToken.reduced(context, DesktopMotion.lift),
            curve: DesktopMotion.spring,
            builder:
                (context, dy, child) =>
                    Transform.translate(offset: Offset(0, dy), child: child),
            child: child,
          ),
    );
    content = GestureDetector(
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
    if (tooltip != null) {
      content = Tooltip(message: tooltip!, child: content);
    }
    return content;
  }
}
