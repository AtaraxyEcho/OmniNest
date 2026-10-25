part of 'mobile_ui.dart';

/// 玻璃面的高斯模糊层。
///
/// 两态都需要：样例的 `.bottom-nav`、`.mini-player` 在浅态仍是半透明白
/// 加 `backdrop-filter`，模糊是这一档表面的一部分，不是暗态专属。
class MobileEnvBlur extends StatelessWidget {
  const MobileEnvBlur({required this.sigma, required this.child, super.key});

  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}

/// 模块全屏页的玻璃圆动作钮（样例 .icon-button：48px 圆、深绿玻璃底、
/// 白 10% 细描边）。图标可给 Material [IconData] 或样例同源矢量
/// [OmniIconsData]，二者取其一。
class MobileGlassIconButton extends StatelessWidget {
  const MobileGlassIconButton({
    required this.tooltip,
    this.icon,
    this.vector,
    required this.onPressed,
    super.key,
  }) : assert(icon != null || vector != null, '图标二选一');

  final String tooltip;
  final IconData? icon;
  final OmniIconsData? vector;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final glyph =
        vector != null
            ? OmniIcon(icon: vector!, size: 20, color: context.env.ink)
            : Icon(icon, size: 20, color: context.env.ink);
    return SizedBox.square(
      dimension: 48,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          icon: glyph,
          style: IconButton.styleFrom(
            backgroundColor: context.env.iconButtonGlass,
            foregroundColor: context.env.ink,
            side: BorderSide(color: context.env.line10),
            minimumSize: const Size.square(48),
          ),
        ),
      ),
    );
  }
}

/// 原型 `.recycle-actions button` / 眉标动作位的行内图标钮：38 见方、
/// 透明底、弱化前景；用于删除、新建这类挂在行内或眉标右侧的轻动作。
class MobileEnvInlineIconButton extends StatelessWidget {
  const MobileEnvInlineIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.iconSize = 18,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox.square(
            dimension: 38,
            child: Icon(icon, size: iconSize, color: context.env.inkMuted),
          ),
        ),
      ),
    );
  }
}

/// 模块全屏页玻璃横幅（样例 module-overlay > header）：返回圆钮 +
/// 居中标题/副题 + 右侧动作钮位；hosted 模块页（音乐/照片/影视/通知）
/// 由根级路由承载时统一使用。
class MobileModuleHeader extends StatelessWidget {
  const MobileModuleHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.backTooltip,
    this.actions = const <Widget>[],
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final String? backTooltip;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 90,
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 7),
        child: Center(
          child: Row(
            children: [
              MobileGlassIconButton(
                tooltip:
                    backTooltip ??
                    MaterialLocalizations.of(context).backButtonTooltip,
                vector: OmniIcons.chevronLeft,
                onPressed: onBack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.env.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: context.env.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              for (final action in actions) ...[
                const SizedBox(width: 8),
                action,
              ],
              // 样例页头是 [48 返回][中列][48 动作] 三列网格；无动作的页面
              // 缺右列会把中列整体右移 28px，补等宽占位保持标题居中。
              if (actions.isEmpty) const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }
}

/// 样例形态确认面板（底部玻璃 sheet）：对齐原型 `.danger-confirm`——
/// 52 图块 + 衬线 23 标题 + 9px 说明 + 两个等宽按钮，危险动作为 #b95f5f
/// 实底白字，常规动作为酸绿实底深字。
///
/// 托管态所有二次确认统一走本入口，替代工位直角确认窗。
Future<bool> showMobileConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final l10n = MaterialLocalizations.of(context);
  final result = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    backgroundColor: context.env.sheetSolid,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      return MobileSheetSemantics(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color:
                        destructive
                            ? StatusTintColors.dangerFill
                            : context.env.accentInk.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: OmniIcon(
                    icon: destructive ? OmniIcons.close : OmniIcons.check,
                    size: 22,
                    color:
                        destructive
                            ? context.env.statusDanger
                            : context.env.accentInk,
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTypography.serifFamily,
                    fontFamilyFallback: AppTypography.serifFamilyFallback,
                    // ignore: font_size_whitelist
                    fontSize: 23,
                    height: 1.0,
                    fontWeight: FontWeight.w400,
                    color: context.env.ink,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9, // ignore: font_size_whitelist
                    height: 1.55,
                    color: context.env.inkMuted,
                  ),
                ),
                const SizedBox(height: 17),
                Row(
                  children: [
                    Expanded(
                      child: _MobileConfirmButton(
                        label: cancelLabel ?? l10n.cancelButtonLabel,
                        background: context.env.line07,
                        foreground: context.env.ink,
                        onTap: () => Navigator.of(sheetContext).pop(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MobileConfirmButton(
                        label: confirmLabel ?? l10n.okButtonLabel,
                        background:
                            destructive
                                ? StatusTintColors.dangerInk
                                : context.env.actionFill,
                        foreground:
                            destructive
                                ? _dangerForeground
                                : context.env.actionFillInk,
                        onTap: () => Navigator.of(sheetContext).pop(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

/// 确认面板底部按钮：45 高、r13、10px 标签（原型 `.danger-confirm button`）。
class _MobileConfirmButton extends StatelessWidget {
  const _MobileConfirmButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MobilePressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 45),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(13),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10, // ignore: font_size_whitelist
            color: foreground,
          ),
        ),
      ),
    );
  }
}

/// 样例 .env-switch 的几何与动效：34×20 胶囊轨道 + 14px 圆点，右移 14px，
/// 200ms ease。颜色由调用方给出：环境面板取极性表，阅读调色板用自己的实底。
class MobilePillSwitch extends StatelessWidget {
  const MobilePillSwitch({
    required this.value,
    required this.onChanged,
    required this.trackOn,
    required this.trackOff,
    required this.knobOn,
    required this.knobOff,
    this.knobShadow,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color trackOn;
  final Color trackOff;
  final Color knobOn;
  final Color knobOff;
  final List<BoxShadow>? knobShadow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.ease,
          width: 34,
          height: 20,
          decoration: BoxDecoration(
            color: value ? trackOn : trackOff,
            borderRadius: BorderRadius.circular(10),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.ease,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? knobOn : knobOff,
                  boxShadow: knobShadow,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 环境面板用的样例 .env-switch：关=白 14% 轨道 + 墨白旋钮，
/// 开=酸绿轨道 + 深墨旋钮；浅态旋钮是白的，靠投影与浅灰轨道分离。
class MobileEnvSwitch extends StatelessWidget {
  const MobileEnvSwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MobilePillSwitch(
      value: value,
      onChanged: onChanged,
      trackOn: context.env.switchOn,
      trackOff: context.env.switchOff,
      knobOn: context.env.switchKnobOn,
      knobOff: context.env.switchKnobOff,
      // 浅态旋钮是白的，落在 16% 的浅灰轨道上必须靠投影分离；
      // 暗态旋钮本来就是浅色实底配深色轨道，不加这层。
      knobShadow:
          context.env.brightness == Brightness.light
              ? const [
                BoxShadow(
                  color: _knobShadow,
                  offset: Offset(0, 1),
                  blurRadius: 3,
                ),
              ]
              : null,
    );
  }
}

/// 样例 section-title 段头：眉标（9px 语义档·字距 1.5·w700 弱化）+
/// Instrument Serif 标题 + 右侧动作钮位；模块页 hosted 内容统一使用。
class MobileEnvSectionHeader extends StatelessWidget {
  const MobileEnvSectionHeader({
    required this.title,
    this.eyebrow,
    this.action,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null && eyebrow!.isNotEmpty)
          Text(
            eyebrow!.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // 样例 .section-title > small 眉标：9px + 字距 1.5，浅态第 4 层把它
            // 与 .notif-group 一起换成 rgba(26,29,27,.58)，暗态是主墨 43%——同一档
            // groupLabelInk。行高 1.45 只在浅层声明，暗态无人声明，两态按 1.45 走。
            style: TextStyle(
              color: context.env.groupLabelInk,
              fontSize: AppTypography.labelNano,
              height: 1.45,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTypography.serifFamily,
                  fontFamilyFallback: AppTypography.serifFamilyFallback,
                  color: context.env.ink,
                  // 样例 .section-title 的 h2 是 21，不是卡片区头档（24）。
                  fontSize: AppTypography.headlineSection,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
            ),
            if (action != null) ...[const SizedBox(width: 12), action!],
          ],
        ),
      ],
    );
  }
}

/// rootNavigator 模态层的宿主环境快照。
///
/// `showModalBottomSheet` 默认经根导航器呈现，面板子树不在移动壳层的
/// Theme 与 `MobileShellScope` 内：壳层暗皮肤、模块调色板重绑与托管标记
/// 全部丢失，表现为白底输入框与浅色面板。打开面板前在宿主页面上下文
/// 捕获环境，面板 builder 用 [wrap] 重放；非托管态原样返回子级。
class MobileSheetAmbience {
  MobileSheetAmbience.capture(BuildContext context)
    : _theme = Theme.of(context),
      _hosted = MobileShellScope.isHosted(context);

  final ThemeData _theme;
  final bool _hosted;

  /// 面板是否由移动壳层承载（决定圆角与实底面板色等形态）。
  bool get hosted => _hosted;

  /// 在面板子树重放宿主主题与托管标记。
  Widget wrap(Widget child) {
    if (!_hosted) {
      return child;
    }
    return Theme(
      data: _theme,
      child: MobileShellScope(hosted: true, child: child),
    );
  }
}

/// 原型 `.feature-list > button` 行：42 图标舱 + 名称/明细 + 尾部状态位
/// 与可选箭头，发丝线分隔；用于挂载账户、导入任务、共享条目等
/// 无进度条的条目列表。
///
/// 与 `.transfer-row` 的差别是不带 3px 进度条，行高 69 由内容自撑。
class MobileFeatureListRow extends StatelessWidget {
  const MobileFeatureListRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.neutralIcon = false,
    super.key,
  });

  final OmniIconsData icon;
  final String title;
  final String detail;

  /// 尾部状态丸等控件；无内容时不占位。
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 可进入下一层的行显示 16px 弱化箭头（原型行尾 chevron）。
  final bool showChevron;

  /// 原型 `.notif-icon.neutral`：弱化前景 + 白 5% 底，用于无状态条目。
  final bool neutralIcon;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 69),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.env.line07)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  neutralIcon
                      ? context.env.surfaceTint
                      : context.env.accentInk.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(13),
            ),
            child: OmniIcon(
              icon: icon,
              size: 18,
              color: neutralIcon ? context.env.inkMuted : context.env.accentInk,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.env.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9, // ignore: font_size_whitelist
                    color: context.env.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          if (showChevron) ...[
            const SizedBox(width: 8),
            OmniIcon(
              icon: OmniIcons.chevron,
              size: 16,
              color: context.env.ink40,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) {
      return row;
    }
    return MobilePressable(semanticLabel: title, onTap: onTap, child: row);
  }
}
